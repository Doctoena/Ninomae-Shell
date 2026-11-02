import qs.services
import QtQuick
import qs.modules.onScreenDisplay
// Caps Lock, as the other rows without a bar, On/Off in a pill: the accent while on, quiet while off
OsdValueIndicator {
    active: CapsLock.capsLockActive
    showBar: false
    valuePill: true
    icon: "keyboard_capslock"
    name: Translation.tr("Caps Lock")
    valueText: CapsLock.capsLockActive ? Translation.tr("On") : Translation.tr("Off")
}
