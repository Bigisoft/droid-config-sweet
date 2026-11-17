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
                         + "saving mode (dimmer screen, less background activity). Turning "
                         + "it off again also ends power saving mode."
        }
    ]

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

    function select(index) {
        var key = modes[index].key
        modeSetting.value = key
        systemdManager.typedCall("StartUnit",
                                 [{ "type": "s", "value": "sweet-performance-request@" + key + ".service" },
                                  { "type": "s", "value": "replace" }])
    }

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
                currentIndex: page.indexOf(modeSetting.value)
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

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.modes[page.indexOf(modeSetting.value)].description
            }
        }
    }
}
