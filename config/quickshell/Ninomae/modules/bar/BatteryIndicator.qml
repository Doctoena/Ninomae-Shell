import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
// Bar battery: the battery icon and the percentage, no background of their own (like Wi-Fi and
// Bluetooth next to it). Lavender while charging, red when low. Hover shows the battery drawer.
MouseArea {
    id: root
    property color statusColor: Battery.isLowAndUnplugged ? Appearance.colors.colError
        : Battery.isCharging ? Appearance.colors.colPrimary
        : Appearance.colors.colOnLayer0
    Behavior on statusColor { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    implicitWidth: row.implicitWidth + 2 + 3 // Pads sized so the gaps to the tray arrow and the status icons match
    implicitHeight: 30
    hoverEnabled: true

    Rectangle { // Segment of the shared right-side pill
        anchors.fill: parent
        radius: 10
        color: root.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Row {
        id: row
        anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
        spacing: 5
        MaterialSymbol {
            // The upright glyph is ~9px of ink in a square advance; a narrow centred box hugs the ink
            width: 12
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: Battery.icon // The level as the glyph's fill
            fill: 1
            iconSize: Appearance.font.pixelSize.large
            color: root.statusColor
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Battery.percent + "%"
            color: root.statusColor
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            font.family: Appearance.font.family.numbers
            font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
        }
    }

    BatteryPopup {
        hoverTarget: root
    }
}
