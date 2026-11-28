import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
// Bar battery (B2): a tiny upright battery, a fine rim and its cap, filled inside to the level, and the percentage, the
// accent line under them while pointed at (which also shows the battery drawer). The accent while charging, red when low.
MouseArea {
    id: root
    property color statusColor: Battery.isLowAndUnplugged ? Appearance.colors.colError
        : Battery.isCharging ? Appearance.colors.colPrimary
        : Appearance.colors.colOnLayer0
    Behavior on statusColor { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    implicitWidth: row.implicitWidth + 10
    implicitHeight: 36 // As every part of the bar
    hoverEnabled: true

    HoverLine { shown: root.containsMouse; capsule: true }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Item { // The battery: its cap, its rim, the charge filling it from the bottom
            anchors.verticalCenter: parent.verticalCenter
            width: 9
            height: 16
            readonly property color rimColour: Battery.isLowAndUnplugged || Battery.isCharging ? root.statusColor
                : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 4
                height: 2
                radius: 1
                color: parent.rimColour
            }
            Rectangle {
                y: 2
                width: 9
                height: 14
                radius: 2.5
                color: "transparent"
                border { width: 1.25; color: parent.rimColour }
                Rectangle {
                    x: 2
                    width: 5
                    anchors { bottom: parent.bottom; bottomMargin: 2 }
                    height: Math.max(1.5, 10 * Math.min(1, Battery.percent / 100))
                    radius: 1.2
                    color: root.statusColor
                    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
            }
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
