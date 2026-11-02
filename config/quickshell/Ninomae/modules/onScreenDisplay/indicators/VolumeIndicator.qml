import qs.services
import QtQuick
import qs.modules.onScreenDisplay
// The volume: its level in the icon, "Muted" (a quiet icon and bar) while muted
OsdValueIndicator {
    readonly property real volume: Audio.sink?.audio?.volume ?? 0
    readonly property bool muted: Audio.sink?.audio?.muted ?? false
    value: volume
    active: !muted
    icon: muted ? "volume_off" : volume < 0.01 ? "volume_mute" : volume < 0.5 ? "volume_down" : "volume_up"
    name: Translation.tr("Volume")
    valueText: muted ? Translation.tr("Muted") : Math.round(volume * 100) + "%"
}
