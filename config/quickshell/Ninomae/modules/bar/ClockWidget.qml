import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
// Bar clock (R3): the time bold in the accent and a muted date, in its own lit capsule (BarContent), the accent line
// under it while pointed at (which also shows the clock/weather drawer). The rightmost of the bar's parts
Item {
    id: root
    implicitWidth: pill.width
    implicitHeight: pill.height

    Rectangle {
        id: pill
        anchors.centerIn: parent
        height: 36 // As every part of the bar
        width: row.implicitWidth + 26
        color: "transparent"
        HoverLine { shown: mouseArea.containsMouse; capsule: true }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 7
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                text: DateTime.time
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtextGlass
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
