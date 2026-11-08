import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
// Bar battery: the battery icon and the percentage on a card of its own, one of the joined pieces on the right
// of the bar (its corners are set from there). Lavender while charging, red when low. Hover shows the battery drawer.
MouseArea {
    id: root
    property real radiusLeft: Appearance.rounding.container
    property real radiusRight: Appearance.rounding.container
    property color statusColor: Battery.isLowAndUnplugged ? Appearance.colors.colError
        : Battery.isCharging ? Appearance.colors.colPrimary
        : Appearance.colors.colOnLayer0
    Behavior on statusColor { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    implicitWidth: row.implicitWidth + 22
    implicitHeight: 36 // As every card on the bar
    hoverEnabled: true

    Rectangle {
        anchors.fill: parent
        topLeftRadius: root.radiusLeft
        bottomLeftRadius: root.radiusLeft
        topRightRadius: root.radiusRight
        bottomRightRadius: root.radiusRight
        color: root.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Row {
        id: row
        anchors.centerIn: parent
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
