import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// sweet: adjustable camera-flash brightness.
//
// The top-menu flashlight shortcut is on/off only, because it goes through
// droidmedia-flashlight -> droid_media_camera_set_torch_mode(), which takes no
// level. The LED itself accepts 0-500 and covers an order of magnitude of
// light. This drives it directly; sweet-torchd applies what is set here.
//
// One piece of state: the level, where zero means off. The switch below is a
// view of that same value rather than a second setting, so sliding to zero and
// switching off are the same act and cannot disagree.

Column {
    width: parent.width

    ConfigurationValue {
        id: torchLevel
        key: "/desktop/sweet/torch/level"
        defaultValue: 0
    }

    // Remembered so the switch can restore the brightness you last chose
    // rather than jumping back to the vendor default.
    ConfigurationValue {
        id: lastLevel
        key: "/desktop/sweet/torch/last_level"
        defaultValue: 200
    }

    TextSwitch {
        text: "Flashlight"
        description: "Adjustable brightness. The top menu shortcut stays a "
                     + "quick on/off at the vendor's default level."
        checked: torchLevel.value > 0
        automaticCheck: false
        onClicked: {
            if (torchLevel.value > 0) {
                lastLevel.value = torchLevel.value
                torchLevel.value = 0
                slider.value = 0
            } else {
                var restore = Math.max(lastLevel.value, slider.minimumValue + slider.stepSize)
                torchLevel.value = restore
                slider.value = restore
            }
        }
    }

    Slider {
        id: slider
        width: parent.width

        // Zero is off, not "dimmest" - a slider that reads 0% while the lamp
        // is still lit is a lie. 400 is held below the hardware maximum of 500
        // on purpose: that draws ~464 mA into a small LED with no thermal
        // feedback on this path, and the vendor's own default is 200.
        minimumValue: 0
        maximumValue: 400
        stepSize: 20
        label: "Brightness"
        valueText: value <= 0
                   ? "Off"
                   : Math.round(value / maximumValue * 100) + "%"

        // Seeded once rather than bound, so assigning below does not break a
        // binding and loop back into itself.
        Component.onCompleted: value = torchLevel.value

        // Live while dragging. Changing the level means dropping led:switch_0
        // and raising it again, but that round trip measures 0.23 ms - a 1.4%
        // dark duty cycle even at 60 Hz, which is not visible. The timer only
        // exists to keep dconf writes down to ~20/s rather than one per frame.
        //
        // Math.round matters: Slider.value is a real, and dconf would store
        // "330.0", which the LED driver rejects outright.
        onValueChanged: if (down) applyTimer.restart()

        onDownChanged: {
            if (!down) {
                applyTimer.stop()
                commit()
            }
        }

        function commit() {
            var v = Math.round(value)
            if (v > 0) {
                lastLevel.value = v
            }
            torchLevel.value = v
        }

        Timer {
            id: applyTimer
            interval: 50
            onTriggered: slider.commit()
        }
    }
}
