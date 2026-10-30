import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell.Hyprland
AndroidQuickToggleButton {
    id: root
    name: Translation.tr("Screen snip")
    statusText: ""
    buttonIcon: "screenshot_region"
    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        delayedActionTimer.start()
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            Hyprland.dispatch('hl.dsp.global("quickshell:regionScreenshot")')
        }
    }
    StyledToolTip {
        text: Translation.tr("Screen snip")
    }
}
