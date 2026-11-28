pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
/**
 * Service for monitoring Caps Lock state changes.
 * Event driven: Hyprland has a non-consuming Caps_Lock bind that fires the
 * "capsLock" global shortcut (see keybinds.lua), so there's no polling.
 */
Singleton {
    id: root
    signal capsLockChanged()
    property bool capsLockActive: false
    property bool ready: false
    Component.onCompleted: checkCapsLock()
    function checkCapsLock() {
        capsLockProc.runNow(); // Pressed again mid-check: checks again after, instead of being dropped
    }
    PollingProcess {
        id: capsLockProc
        command: ["hyprctl", "devices", "-j"]
        onResult: text => {
            {
                try {
                    const devicesData = JSON.parse(text);
                    const mainKeyboard = devicesData.keyboards.find(kb => kb.main === true);
                    if (mainKeyboard) {
                        const newCapsLockState = mainKeyboard.capsLock ?? false;
                        const changed = root.ready && root.capsLockActive !== newCapsLockState;
                        root.capsLockActive = newCapsLockState;
                        if (changed) root.capsLockChanged();
                        root.ready = true;
                    }
                } catch (e) {
                    console.error("[CapsLock] Error parsing hyprctl output:", e);
                }
            }
        }
    }
    // Check on release so the xkb state has already been updated
    GlobalShortcut {
        name: "capsLock"
        description: "Caps Lock pressed (re-checks Caps Lock state)"
        onReleased: root.checkCapsLock()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                root.checkCapsLock();
            }
        }
    }
}
