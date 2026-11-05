import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A filter over a panel's list (News: All / Updates, Achievements: All / Unlocked / Locked), in a row of them:
// neutral, accent when it's the one showing
Rectangle {
    id: fc
    property string label
    property string symbol: ""
    property bool on: false
    signal picked()
    width: fcRow.implicitWidth + 20; height: 30; radius: Appearance.rounding.segment
    color: on ? Appearance.colors.colPrimary : fcHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color { ColorAnimation { duration: 140 } }
    Row {
        id: fcRow
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            visible: fc.symbol !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: fc.symbol; iconSize: 16
            color: fc.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: fc.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: fc.on ? Font.DemiBold : Font.Medium
            color: fc.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
    }
    HoverHandler { id: fcHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: fc.picked() }
}
