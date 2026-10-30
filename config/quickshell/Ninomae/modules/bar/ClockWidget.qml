import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
// Bar clock: a pill with the time and a muted date; hover shows the clock/weather drawer
Item {
    id: root
    implicitWidth: pill.width
    implicitHeight: pill.height

    Rectangle {
        id: pill
        anchors.centerIn: parent
        height: 30
        width: row.implicitWidth + 24
        radius: 11 // Rounded rectangle, like the rest of the bar
        color: mouseArea.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                text: DateTime.time
            }
            Rectangle { // Separator dot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 3; implicitHeight: 3; radius: 1.5
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Qt.formatDate(DateTime.clock.date, "ddd, MMM d")
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        ClockWidgetTooltip {
            hoverTarget: mouseArea
        }
    }
}
