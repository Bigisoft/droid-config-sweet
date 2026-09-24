import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import Nemo.DBus 2.0
import org.nemomobile.systemsettings 1.0

// sweet: charging profiles, for a phone that is sometimes carried and sometimes
// left plugged in as a server.
//
// This is only a front end. The limiter itself is mce's charging module, the
// same one behind Settings > Battery > "Battery ageing protection". That page
// offers just two limits, 80% and 90%, but BatteryStatus exposes the mode and
// both thresholds as writable, so everything here goes through the stock API
// and mce keeps owning the policy. Nothing new runs in the background.
//
// A profile is just a mode plus a pair of limits written to mce. The one
// piece of state this page adds is in dconf: which profile was picked last, and
// the values of the Custom profile, so that choosing Custom again restores
// them instead of leaving whatever a template set.
//
// mce drives input_suspend on this device (etc/mce/61-sweet-charging.ini).
// While charging is paused, the charger stops supplying the phone at all and it
// runs from the battery with the cable attached, draining down to the resume
// level. Holding the battery idle while the charger powers the phone would be
// kinder to it, but the only nodes that could do that (charging_enabled,
// battery_charging_enabled) were measured to have no effect on sweet.
//
// mce protects itself, so no setting here can hurt the phone. It clamps both
// limits to 0-100, treats a pair where resume >= stop as "charge to 100%",
// always charges below 5%, and re-enables charging whenever the cable is
// unplugged.

Page {
    id: page

    // mce needs resume < stop. Keeping a gap also stops the charger from
    // flapping on and off around one percentage point.
    readonly property int minimumGap: 2
    readonly property int lowestResume: 5
    readonly property int lowestStop: lowestResume + minimumGap

    // Why these ranges: a lithium cell ages fastest when it is hot and when it
    // sits near full, and barely at all from shallow cycles in the middle.
    // The server ranges keep about 10% between the limits so the charger
    // switches rarely without the battery ever leaving mid-range.
    readonly property var profiles: [
        {
            key: "daily",
            name: "Daily use",
            mode: BatteryStatus.ApplyChargingThresholds,
            resume: 75, stop: 80,
            description: "For a phone that is carried around and charged overnight. "
                         + "Stopping at 80% avoids the top of the charge, where the "
                         + "battery wears fastest, and still lasts a day."
        },
        {
            key: "server",
            name: "Server",
            mode: BatteryStatus.ApplyChargingThresholds,
            resume: 40, stop: 50,
            description: "For a phone left plugged in all the time. Around half full "
                         + "is where the battery ages least."
        },
        {
            key: "server_reserve",
            name: "Server with outage reserve",
            mode: BatteryStatus.ApplyChargingThresholds,
            resume: 50, stop: 60,
            description: "Plugged in all the time, but with more charge held back so "
                         + "the phone keeps running longer if the power goes out."
        },
        {
            key: "full",
            name: "Full charge",
            mode: BatteryStatus.EnableCharging,
            resume: -1, stop: -1,
            description: "Charge to 100%, for a trip or a long day away from a "
                         + "charger. Switch back afterwards: sitting at 100% ages the "
                         + "battery fastest."
        }
    ]
    readonly property int customIndex: profiles.length

    readonly property var modeOptions: [
        BatteryStatus.EnableCharging,
        BatteryStatus.ApplyChargingThresholds,
        BatteryStatus.ApplyChargingThresholdsAfterFull
    ]

    readonly property bool limitsApply: battery.chargingMode === BatteryStatus.ApplyChargingThresholds
                                        || battery.chargingMode === BatteryStatus.ApplyChargingThresholdsAfterFull
    readonly property bool chargerConnected: battery.chargerStatus === BatteryStatus.Connected

    // mce's own view: "enabled", "disabled" or "unknown". This is the only
    // place that says whether a limit is holding charging off right now.
    property string chargingState: "unknown"

    // The profile shown as selected. The one picked last on this page, as long
    // as mce still holds its values. If something else changed them (the stock
    // Battery page, mcetool), whichever template matches, otherwise Custom.
    readonly property int activeIndex: {
        var last = profileIndexOf(lastProfile.value)
        if (last === customIndex || (last >= 0 && matches(profiles[last])))
            return last
        for (var i = 0; i < profiles.length; ++i) {
            if (matches(profiles[i]))
                return i
        }
        return customIndex
    }

    ConfigurationValue {
        id: lastProfile
        key: "/desktop/sweet/charging/profile"
        defaultValue: ""
    }

    // -1 means Custom has never been set; it then starts from whatever mce
    // holds at that moment.
    ConfigurationValue {
        id: customMode
        key: "/desktop/sweet/charging/custom_mode"
        defaultValue: -1
    }

    ConfigurationValue {
        id: customResume
        key: "/desktop/sweet/charging/custom_resume"
        defaultValue: -1
    }

    ConfigurationValue {
        id: customStop
        key: "/desktop/sweet/charging/custom_stop"
        defaultValue: -1
    }

    function profileIndexOf(key) {
        if (key === "custom")
            return customIndex
        for (var i = 0; i < profiles.length; ++i) {
            if (profiles[i].key === key)
                return i
        }
        return -1
    }

    function matches(profile) {
        if (battery.chargingMode !== profile.mode)
            return false
        if (profile.mode === BatteryStatus.EnableCharging)
            return true
        return battery.chargeEnableLimit === profile.resume
                && battery.chargeDisableLimit === profile.stop
    }

    function rangeText(resume, stop) {
        return resume + "-" + stop + "%"
    }

    function profileSummary(index) {
        if (index === customIndex) {
            if (customMode.value < 0)
                return "Custom"
            if (customMode.value === BatteryStatus.EnableCharging)
                return "Custom  (always charge)"
            return "Custom  (" + rangeText(customResume.value, customStop.value) + ")"
        }
        var p = profiles[index]
        if (p.mode === BatteryStatus.EnableCharging)
            return p.name + "  (100%)"
        return p.name + "  (" + rangeText(p.resume, p.stop) + ")"
    }

    function modeText(mode) {
        if (mode === BatteryStatus.EnableCharging)
            return "Always charge"
        if (mode === BatteryStatus.ApplyChargingThresholds)
            return "Keep within limits"
        if (mode === BatteryStatus.ApplyChargingThresholdsAfterFull)
            return "Charge to full once, then keep within limits"
        if (mode === BatteryStatus.DisableCharging)
            return "Never charge (set outside this page)"
        return "Unknown"
    }

    function modeDescription(mode) {
        if (mode === BatteryStatus.EnableCharging)
            return "Charge to 100% whenever a charger is connected."
        if (mode === BatteryStatus.ApplyChargingThresholds)
            return "Stop charging at the upper limit. While paused, the phone runs from "
                    + "the battery even with the cable attached, until the battery drops "
                    + "to the lower limit."
        if (mode === BatteryStatus.ApplyChargingThresholdsAfterFull)
            return "After each time the charger is connected, charge to 100% first, then "
                    + "keep within the limits."
        return ""
    }

    function statusText() {
        if (!chargerConnected)
            return "On battery, charger not connected"
        if (chargingState === "disabled")
            return "Paused by limit. Running from battery until "
                    + battery.chargeEnableLimit + "%"
        if (chargingState === "enabled") {
            if (battery.chargingForced)
                return "Charging to 100% this time"
            if (limitsApply)
                return "Charging, up to " + battery.chargeDisableLimit + "%"
            return "Charging"
        }
        return "Unknown"
    }

    // Writes the two limits in an order that never leaves an invalid pair
    // behind, even for a moment. mce re-evaluates on every single write and
    // reads resume >= stop as "charge to 100%", so writing them the wrong way
    // round would briefly start a full charge. Returns what was written.
    function setLimits(resume, stop) {
        stop = Math.max(lowestStop, Math.min(100, Math.round(stop)))
        resume = Math.max(lowestResume, Math.min(stop - minimumGap, Math.round(resume)))
        if (resume < battery.chargeDisableLimit) {
            battery.chargeEnableLimit = resume
            battery.chargeDisableLimit = stop
        } else {
            battery.chargeDisableLimit = stop
            battery.chargeEnableLimit = resume
        }
        return { resume: resume, stop: stop }
    }

    // Limits first, then the mode: switching into a threshold mode then acts
    // on the new range straight away rather than on the previous one.
    function apply(mode, resume, stop) {
        if (mode !== BatteryStatus.EnableCharging && resume >= 0 && stop >= 0)
            setLimits(resume, stop)
        battery.chargingMode = mode
    }

    function selectProfile(index) {
        if (index === customIndex) {
            if (customMode.value < 0) {
                // First use: Custom starts as a copy of what is active now, in
                // a threshold mode so the sliders have something to act on.
                customMode.value = limitsApply ? battery.chargingMode
                                               : BatteryStatus.ApplyChargingThresholds
                customResume.value = battery.chargeEnableLimit
                customStop.value = battery.chargeDisableLimit
            }
            apply(customMode.value, customResume.value, customStop.value)
            lastProfile.value = "custom"
        } else {
            var p = profiles[index]
            apply(p.mode, p.resume, p.stop)
            lastProfile.value = p.key
        }
    }

    // Any hand edit below lands in Custom, so a template is never changed
    // behind the user's back and the edit is there to come back to.
    function saveAsCustom(mode, resume, stop) {
        customMode.value = mode
        customResume.value = resume
        customStop.value = stop
        lastProfile.value = "custom"
    }

    BatteryStatus {
        id: battery
    }

    DBusInterface {
        id: mceRequest
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    DBusInterface {
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/signal"
        iface: "com.nokia.mce.signal"
        signalsEnabled: true

        function charging_state_ind(state) {
            page.chargingState = state
        }
    }

    Component.onCompleted: {
        mceRequest.typedCall("get_charging_state", [], function (state) {
            page.chargingState = state
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: "Charging limits"
            }

            DetailItem {
                label: "Battery"
                value: battery.chargePercentage + "%"
            }

            DetailItem {
                label: "Now"
                value: statusText()
            }

            Label {
                visible: !battery.chargingSuspendendable
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: "mce reports that it cannot control charging on this device, so "
                      + "these settings have no effect. Check "
                      + "/etc/mce/61-sweet-charging.ini and the input_suspend node."
            }

            SectionHeader {
                text: "Profile"
            }

            ComboBox {
                id: profileCombo
                label: "Profile"
                value: activeIndex === customIndex ? "Custom" : profiles[activeIndex].name
                description: activeIndex === customIndex
                             ? "Your own mode and limits. Changing anything under Details "
                               + "saves it here."
                             : profiles[activeIndex].description

                Binding {
                    target: profileCombo
                    property: "currentIndex"
                    value: page.activeIndex
                }

                menu: ContextMenu {
                    Repeater {
                        model: page.profiles.length + 1
                        MenuItem {
                            text: profileSummary(index)
                            onClicked: selectProfile(index)
                        }
                    }
                }
            }

            SectionHeader {
                text: "Details"
            }

            ComboBox {
                id: modeCombo
                label: "Charging"
                value: modeText(battery.chargingMode)
                description: modeDescription(battery.chargingMode)

                Binding {
                    target: modeCombo
                    property: "currentIndex"
                    value: page.modeOptions.indexOf(battery.chargingMode)
                }

                menu: ContextMenu {
                    Repeater {
                        model: page.modeOptions
                        MenuItem {
                            text: modeText(modelData)
                            onClicked: {
                                battery.chargingMode = modelData
                                saveAsCustom(modelData, battery.chargeEnableLimit,
                                             battery.chargeDisableLimit)
                            }
                        }
                    }
                }
            }

            Slider {
                id: stopSlider
                visible: limitsApply
                width: parent.width
                minimumValue: lowestStop
                maximumValue: 100
                stepSize: 1
                label: "Stop charging at"
                valueText: Math.round(value) + "%"

                // Follows mce except while being dragged, so a change made
                // elsewhere (a profile, the stock Battery page, mcetool) shows
                // up here.
                Binding {
                    target: stopSlider
                    property: "value"
                    value: battery.chargeDisableLimit
                    when: !stopSlider.down
                }

                // Committed on release only. Every write makes mce re-evaluate
                // and possibly toggle input_suspend, so live updates while
                // dragging would flap the charger.
                //
                // The dragged value is captured as it moves because on release
                // the Binding above re-activates in the same signal as
                // onDownChanged, and may already have put mce's old value back.
                property int dragged: -1
                onValueChanged: if (down) dragged = Math.round(value)
                onDownChanged: {
                    if (!down && dragged >= 0) {
                        var w = setLimits(Math.min(battery.chargeEnableLimit, dragged - minimumGap), dragged)
                        saveAsCustom(battery.chargingMode, w.resume, w.stop)
                        dragged = -1
                    }
                }
            }

            Slider {
                id: resumeSlider
                visible: limitsApply
                width: parent.width
                minimumValue: lowestResume
                maximumValue: Math.max(lowestResume + 1, stopSlider.value - minimumGap)
                stepSize: 1
                label: "Resume charging at"
                valueText: Math.round(value) + "%"

                Binding {
                    target: resumeSlider
                    property: "value"
                    value: battery.chargeEnableLimit
                    when: !resumeSlider.down
                }

                property int dragged: -1
                onValueChanged: if (down) dragged = Math.round(value)
                onDownChanged: {
                    if (!down && dragged >= 0) {
                        var w = setLimits(dragged, battery.chargeDisableLimit)
                        saveAsCustom(battery.chargingMode, w.resume, w.stop)
                        dragged = -1
                    }
                }
            }

            TextSwitch {
                visible: chargerConnected && battery.chargingMode !== BatteryStatus.EnableCharging
                automaticCheck: false
                checked: battery.chargingForced
                text: "Charge to 100% this time"
                description: "Ignore the limits until the battery is full or the charger "
                             + "is unplugged. The profile stays as it is."
                onClicked: battery.chargingForced = !battery.chargingForced
            }
        }

        VerticalScrollDecorator {}
    }
}
