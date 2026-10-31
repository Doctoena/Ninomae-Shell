import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings → Input: keyboard repeat, mouse and touchpad. Saved in the shell config and applied live by
// services/DeviceSettings.qml (which also puts them back after a Hyprland reload)
ContentPage {
    id: page
    readonly property var input: Config.options.input

    // Only show the touchpad section when there is one
    property bool hasTouchpad: false
    Process {
        running: true
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.hasTouchpad = JSON.parse(text).mice.some(m => m.name.includes("touchpad"));
                } catch (e) {}
            }
        }
    }

    ContentSection {
        id: keyboardSection
        icon: "keyboard"
        title: Translation.tr("Keyboard")
        spacing: 10
        // Layouts: services/KeyboardLayout.qml writes hypr/hyprland/keyboard.lua, and the shortcuts move with it
        readonly property var layoutEntry: KeyboardLayout.layouts.find(l => l.layout === KeyboardLayout.layout)
        Component.onCompleted: { KeyboardLayout.loadLayouts(); KeyboardLayout.refreshLogin(); }
        ConfigComboBox {
            icon: "language"
            text: Translation.tr("Layout")
            tooltip: Translation.tr("Shortcuts stay on the same physical keys whatever the layout. Settings → Keybinds shows them as your layout prints them")
            currentValue: KeyboardLayout.layout
            fallbackText: KeyboardLayout.layout
            options: KeyboardLayout.layouts.map(l => ({ displayName: l.name, value: l.layout }))
            onSelected: v => KeyboardLayout.set(v, "")
        }
        ConfigComboBox {
            visible: (keyboardSection.layoutEntry?.variants.length ?? 0) > 0
            icon: "tune"
            text: Translation.tr("Variant")
            currentValue: KeyboardLayout.variant
            fallbackText: KeyboardLayout.variant
            options: [{ displayName: Translation.tr("Standard"), value: "" }]
                .concat((keyboardSection.layoutEntry?.variants ?? []).map(v => ({ displayName: v.name, value: v.variant })))
            onSelected: v => KeyboardLayout.set(KeyboardLayout.layout, v)
        }
        SettingRow {
            visible: KeyboardLayout.loginLayout !== "" && KeyboardLayout.loginLayout !== KeyboardLayout.current
            icon: "login"
            text: Translation.tr("The login screen uses a different layout")
            tooltip: Translation.tr("Asks for your password, then the login screen uses this layout from the next time it shows")
            RippleButtonWithIcon {
                materialIcon: "sync"
                mainText: Translation.tr("Use this one")
                onClicked: KeyboardLayout.setLoginScreen()
            }
        }
        ConfigSpinBox {
            icon: "speed"
            text: Translation.tr("Repeat rate")
            suffix: Translation.tr("per second")
            option: "input.keyboard.repeatRate"
            from: 10
            to: 80
            stepSize: 5
        }
        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Delay before repeating")
            suffix: "ms"
            option: "input.keyboard.repeatDelay"
            from: 100
            to: 1000
            stepSize: 25
        }
        StyledTextArea { // Hold a key in here to feel the two above
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            placeholderText: Translation.tr("Try it here: hold down a key")
        }
        ConfigSwitch {
            buttonIcon: "dialpad"
            text: Translation.tr("Num Lock on at login")
            option: "input.keyboard.numlockByDefault"
        }
    }

    ContentSection {
        id: mouseSection
        icon: "mouse"
        title: Translation.tr("Mouse")
        spacing: 10
        readonly property var accelProfiles: [
            { displayName: Translation.tr("Flat"), icon: "trending_flat", value: "flat",
                about: Translation.tr("the same distance at any speed, often preferred for games.\nAt 0 % speed it matches Windows with \"Enhance pointer precision\" off") },
            { displayName: Translation.tr("Adaptive"), icon: "trending_up", value: "adaptive",
                about: Translation.tr("the pointer goes further the faster you move") }
        ]
        ConfigSpinBox {
            icon: "speed"
            text: Translation.tr("Pointer speed")
            option: "input.mouse.sensitivity"
            factor: 100
            suffix: "%"
            from: -100
            to: 100
            stepSize: 5
        }
        ConfigChoiceRow {
            icon: "trending_up"
            text: Translation.tr("Acceleration")
            option: "input.mouse.accelProfile"
            options: mouseSection.accelProfiles
            tooltip: mouseSection.accelProfiles.map(a => `${a.displayName}: ${a.about}`).join("\n")
        }
        ConfigSwitch {
            buttonIcon: "front_hand"
            text: Translation.tr("Left-handed")
            option: "input.mouse.leftHanded"
            tooltip: Translation.tr("Swaps the left and right buttons")
        }
        ContentSubsection {
            title: Translation.tr("Scrolling")
            ConfigSpinBox {
                icon: "swap_vert"
                text: Translation.tr("Scroll speed")
                option: "input.mouse.scrollFactor"
                factor: 100
                suffix: "%"
                from: 10
                to: 300
                stepSize: 10
            }
            ConfigSwitch {
                buttonIcon: "swipe_vertical"
                text: Translation.tr("Natural scrolling")
                option: "input.mouse.naturalScroll"
                tooltip: Translation.tr("Content moves the way your fingers do, like on a phone")
            }
        }
    }

    ContentSection {
        visible: page.hasTouchpad
        icon: "touchpad_mouse"
        title: Translation.tr("Touchpad")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Tap to click")
            option: "input.touchpad.tapToClick"
        }
        ConfigSwitch {
            buttonIcon: "drag_pan"
            text: Translation.tr("Tap and drag")
            visible: page.input.touchpad.tapToClick
            option: "input.touchpad.tapAndDrag"
            tooltip: Translation.tr("Tap, then keep your finger down to drag")
        }
        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Two-finger click to right-click")
            option: "input.touchpad.clickfinger"
        }
        ConfigSwitch {
            buttonIcon: "keyboard_hide"
            text: Translation.tr("Ignore the touchpad while typing")
            option: "input.touchpad.disableWhileTyping"
        }
        ContentSubsection {
            title: Translation.tr("Scrolling")
            ConfigSpinBox {
                icon: "swap_vert"
                text: Translation.tr("Scroll speed")
                option: "input.touchpad.scrollFactor"
                factor: 100
                suffix: "%"
                from: 10
                to: 300
                stepSize: 10
            }
            ConfigSwitch {
                buttonIcon: "swipe_vertical"
                text: Translation.tr("Natural scrolling")
                option: "input.touchpad.naturalScroll"
                tooltip: Translation.tr("Content moves the way your fingers do, like on a phone")
            }
        }
    }
}
