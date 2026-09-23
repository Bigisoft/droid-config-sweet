import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import org.nemomobile.systemsettings 1.0

// sweet: charging limits with any values, for a phone that stays plugged in.
//
// This is only a front end. The limiter itself is mce's charging module, the
// same one behind Settings > Battery > "Battery ageing protection". That page
// offers just two limits, 80% and 90%, but BatteryStatus exposes the mode and
// both thresholds as writable, so everything here goes through the stock API
// and mce keeps owning the policy. Nothing new runs in the background.
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

    readonly property var modeOptions: [
        BatteryStatus.EnableCharging,
        BatteryStatus.ApplyChargingThresholds,
        BatteryStatus.ApplyChargingThresholdsAfterFull
    ]

    readonly property var presets: [
        { name: "Always plugged in", resume: 50, stop: 60 },
        { name: "Everyday", resume: 75, stop: 80 },
        { name: "Deep cycle", resume: 20, stop: 80 }
    ]

    readonly property bool limitsApply: battery.chargingMode === BatteryStatus.ApplyChargingThresholds
                                        || battery.chargingMode === BatteryStatus.ApplyChargingThresholdsAfterFull
    readonly property bool chargerConnected: battery.chargerStatus === BatteryStatus.Connected

    // mce's own view: "enabled", "disabled" or "unknown". This is the only
    // place that says whether a limit is holding charging off right now.
    property string chargingState: "unknown"

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
    // round would briefly start a full charge.
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
    }

    function presetIndex() {
        for (var i = 0; i < presets.length; ++i) {
            if (presets[i].resume === battery.chargeEnableLimit
                    && presets[i].stop === battery.chargeDisableLimit)
                return i
        }
        return -1
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
                text: "Mode"
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
                            onClicked: battery.chargingMode = modelData
                        }
                    }
                }
            }

            SectionHeader {
                visible: limitsApply
                text: "Limits"
            }

            ComboBox {
                id: presetCombo
                visible: limitsApply
                label: "Preset"
                value: {
                    var i = presetIndex()
                    return i < 0 ? "Custom" : presets[i].name
                }
                description: "Always plugged in keeps the battery around half full, "
                             + "which ages it the least. Heat does more damage than "
                             + "any limit, so keep the phone out of its case and out "
                             + "of the sun."

                Binding {
                    target: presetCombo
                    property: "currentIndex"
                    value: presetIndex()
                }

                menu: ContextMenu {
                    Repeater {
                        model: page.presets
                        MenuItem {
                            text: modelData.name + "  (" + modelData.resume + "-"
                                  + modelData.stop + "%)"
                            onClicked: setLimits(modelData.resume, modelData.stop)
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
                // elsewhere (the stock Battery page, mcetool) shows up here.
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
                        setLimits(Math.min(battery.chargeEnableLimit, dragged - minimumGap), dragged)
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
                        setLimits(dragged, battery.chargeDisableLimit)
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
                             + "is unplugged."
                onClicked: battery.chargingForced = !battery.chargingForced
            }
        }

        VerticalScrollDecorator {}
    }
}
