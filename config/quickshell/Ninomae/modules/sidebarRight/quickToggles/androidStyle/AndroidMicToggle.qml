import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
AndroidQuickToggleButton {
    id: root
    name: Translation.tr("Mic")
    statusText: toggled ? Translation.tr("Enabled") : Translation.tr("Muted")
    toggled: !Audio.source?.audio?.muted
    buttonIcon: Audio.source?.audio?.muted ? "mic_off" : "mic"
    mainAction: () => {
        if (Audio.source?.audio) Audio.source.audio.muted = !Audio.source.audio.muted
    }
    altAction: () => {
        root.openMenu()
    }
    StyledToolTip {
        text: Translation.tr("Audio input | Right-click for volume mixer & device selector")
    }
}
