import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
AndroidQuickToggleButton {
    id: root
    name: Translation.tr("Game mode")
    statusText: ""
    buttonIcon: "gamepad"
    toggled: GameModeService.active
    mainAction: () => GameModeService.toggle()
    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}
