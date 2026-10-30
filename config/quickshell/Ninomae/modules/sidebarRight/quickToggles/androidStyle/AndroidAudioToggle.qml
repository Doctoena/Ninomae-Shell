import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
AndroidQuickToggleButton {
    id: root
    name: Translation.tr("Sound")
    statusText: toggled ? Translation.tr("Unmuted") : Translation.tr("Muted")
    toggled: !Audio.sink?.audio?.muted
    buttonIcon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
    mainAction: () => {
        if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
    }
    altAction: () => {
        root.openMenu()
    }
    StyledToolTip {
        text: Translation.tr("Audio output | Right-click for volume mixer & device selector")
    }
}
