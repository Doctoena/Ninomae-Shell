import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
AndroidQuickToggleButton {
    id: root
    name: Translation.tr("Internet")
    statusText: Network.networkName
    toggled: Network.wifiStatus !== "disabled"
    buttonIcon: Network.materialSymbol
    mainAction: () => Network.toggleWifi()
    altAction: () => {
        root.openMenu()
    }
    StyledToolTip {
        text: Network.networkName || Translation.tr("Internet")
    }
}
