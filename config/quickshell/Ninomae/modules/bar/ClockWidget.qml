import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
// Bar clock: a card with the time and a muted date; hover shows the clock/weather drawer. The last of the joined
// pieces on the right of the bar: its corners are set from there
Item {
    id: root
    property real radiusLeft: Appearance.rounding.container
    property real radiusRight: Appearance.rounding.container
    implicitWidth: pill.width
    implicitHeight: pill.height

    Rectangle {
        id: pill
        anchors.centerIn: parent
        height: 36 // As every card on the bar
        width: row.implicitWidth + 28
        topLeftRadius: root.radiusLeft
        bottomLeftRadius: root.radiusLeft
        topRightRadius: root.radiusRight
        bottomRightRadius: root.radiusRight
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
                text: Qt.formatDate(DateTime.clock.date, "ddd d MMM") // "Sat 7 Nov", as the sidebar's "Saturday 7 November"
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
