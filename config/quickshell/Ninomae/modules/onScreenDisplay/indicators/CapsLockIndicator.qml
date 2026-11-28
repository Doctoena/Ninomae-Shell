import qs.services
import QtQuick
import qs.modules.onScreenDisplay
// Caps Lock: the compact row (no bar): the ring full and lit while on, the shell's switch saying on or off
OsdValueIndicator {
    active: CapsLock.capsLockActive
    showBar: false
    icon: "keyboard_capslock"
    name: Translation.tr("Caps Lock")
}
