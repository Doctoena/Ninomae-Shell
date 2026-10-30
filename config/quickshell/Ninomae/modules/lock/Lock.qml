pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.lock
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
Scope {
    id: root
    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: [Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }
    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext
        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                }
            }
        }
        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff(true); // Behind the lock nobody can answer a save dialog: go ahead after the wait
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot(true);
                return;
            }
            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring();
            // Unlock the screen before exiting, or the compositor will display a
            // fallback lock you can't interact with.
            GlobalStates.screenLocked = false;
            // Refocus last focused window on unlock (hack)
            Quickshell.execDetached(["bash", "-c", `sleep 0.2; hyprctl dispatch 'hl.dsp.workspace.toggle_special()'; hyprctl dispatch 'hl.dsp.workspace.toggle_special()'`])
            // Reset
            lockContext.reset();
        }
    }
    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        WlSessionLockSurface {
            color: "transparent"
            Loader {
                active: GlobalStates.screenLocked
                anchors.fill: parent
                opacity: active ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                sourceComponent: LockSurface {
                    context: lockContext
                }
            }
        }
    }
    // Blur layer hack removed for Hyprland 0.55+ (Lua config):
    // it relied on `hyprctl keyword monitor ... addreserved` and the
    // `dwindle:pseudotile` option, neither of which exist anymore.
    IpcHandler {
        target: "lock"
        function activate(): void {
            GlobalStates.screenLocked = true;
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }
    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"
        onPressed: {
            GlobalStates.screenLocked = true;
        }
    }
    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"
        onPressed: {
            lockContext.shouldReFocus();
        }
    }
    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            Hyprland.dispatch('hl.dsp.global("quickshell:lock")')
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
