import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import Nemo.DBus 2.0

// sweet: Performance / Balanced / Battery saver, like the modes in MIUI's
// Battery & performance settings.
//
// This page is only a front end. It remembers the choice in dconf and starts
// sweet-performance-request@<mode>.service on the session bus; that hands the
// mode to the root side (sweet-performance.path -> sweet-performance-apply),
// which sets the CPU and GPU limits and, for Battery saver, mce's forced power
// saving mode. The thermal daemons keep their own caps, so no choice here can
// overheat the phone. See /usr/bin/droid/sweet-performance-apply for the
// values and why it works this way.
//
// What the phone really runs is read back from /run/sweet-performance-applied,
// written by the root side, so a change that did not take is visible here
// instead of the page just repeating the saved choice.
Page {
    id: page

    readonly property var modes: [
        {
            key: "performance",
            name: "Performance",
            description: "The processor and graphics start from a faster clock, so apps "
                         + "and games react sooner. Uses more battery and runs warmer. "
                         + "Avoid it on a worn battery: a heavy load can make it shut "
                         + "the phone off."
        },
        {
            key: "balanced",
            name: "Balanced",
            description: "The normal behaviour: the processor speeds up only when there "
                         + "is work to do."
        },
        {
            key: "saver",
            name: "Battery saver",
            description: "Caps the processor and graphics speed and turns on power "
                         + "saving mode (dimmer screen, less background activity) until "
                         + "the charger is next connected. The speed caps stay until you "
                         + "pick another mode."
        }
    ]

    // "" until read; otherwise the mode the root side last applied.
    property string applied: ""
    property bool requestFailed: false

    ConfigurationValue {
        id: modeSetting
        key: "/desktop/sweet/performance/mode"
        defaultValue: "balanced"
    }

    DBusInterface {
        id: systemdManager
        bus: DBus.SessionBus
        service: "org.freedesktop.systemd1"
        path: "/org/freedesktop/systemd1"
        iface: "org.freedesktop.systemd1.Manager"
    }

    function indexOf(key) {
        for (var i = 0; i < modes.length; ++i) {
            if (modes[i].key === key)
                return i
        }
        return 1
    }

    function nameOf(key) {
        var i = indexOf(key)
        return modes[i].key === key ? modes[i].name : key
    }

    function readApplied() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                page.applied = String(xhr.responseText).trim()
        }
        xhr.open("GET", "file:///run/sweet-performance-applied")
        xhr.send()
    }

    function select(index) {
        var key = modes[index].key
        modeSetting.value = key
        requestFailed = false
        systemdManager.typedCall("StartUnit",
                                 [{ "type": "s", "value": "sweet-performance-request@" + key + ".service" },
                                  { "type": "s", "value": "replace" }],
                                 function () { recheck.restart() },
                                 function () { page.requestFailed = true })
    }

    function statusText() {
        if (requestFailed)
            return "Could not pass the mode on to the system. Try again."
        if (applied === "")
            return ""
        if (applied === modeSetting.value)
            return "Active: " + nameOf(applied)
        return "Still active: " + nameOf(applied) + ". The change has not been applied yet."
    }

    // The root side runs a moment after the request; look again a few times.
    Timer {
        id: recheck
        interval: 700
        repeat: true
        property int count: 0
        onRunningChanged: if (running) count = 0
        onTriggered: {
            page.readApplied()
            count++
            if (count >= 6 || page.applied === modeSetting.value)
                stop()
        }
    }

    onStatusChanged: if (status === PageStatus.Active) readApplied()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: "Performance"
            }

            ComboBox {
                id: modeBox
                label: "Mode"
                menu: ContextMenu {
                    Repeater {
                        model: page.modes
                        MenuItem {
                            text: modelData.name
                            onClicked: page.select(index)
                        }
                    }
                }
            }

            // A plain currentIndex binding is replaced by ComboBox on the
            // first pick; a Binding element keeps following the setting (as
            // ChargingLimits.qml and the stock Battery page do).
            Binding {
                target: modeBox
                property: "currentIndex"
                value: page.indexOf(modeSetting.value)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.modes[page.indexOf(modeSetting.value)].description
            }

            Item {
                width: 1
                height: Theme.paddingMedium
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                visible: text !== ""
                text: page.statusText()
            }
        }
    }
}
