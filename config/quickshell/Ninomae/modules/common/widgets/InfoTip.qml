import qs.modules.common
import QtQuick

// The little (i) after a settings label: hover it for `tip`. Hidden while there's no tip
MaterialSymbol {
    id: root
    property string tip: ""
    visible: tip !== ""
    text: "info"
    iconSize: Appearance.font.pixelSize.large
    color: Appearance.colors.colSubtext
    MouseArea {
        id: infoMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.WhatsThisCursor
        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: infoMouseArea.containsMouse
            text: root.tip
        }
    }
}
