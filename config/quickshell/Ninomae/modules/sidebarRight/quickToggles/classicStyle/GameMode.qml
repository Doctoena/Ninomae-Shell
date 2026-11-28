import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
QuickToggleButton {
    id: root
    buttonIcon: "gamepad"
    toggled: GameModeService.active
    onClicked: GameModeService.toggle()
    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}