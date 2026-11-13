import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A filter over a panel's list (News: All / Updates, Achievements: Unlocked / All / Locked), on its banner's
// corner: joined to the chips beside it (rounded at the row's ends), tinted in the accent when it's the one showing.
// overArt: on a banner's art, where the tint is lost among the art's colours, the one showing is the accent itself
Rectangle {
    id: fc
    property string label
    property string symbol: ""
    property bool on: false
    property bool overArt: false
    readonly property bool _solid: on && overArt
    signal picked()
    readonly property bool filterChip: true
    // Where it sits among the chips shown beside it (not the Repeater that made them)
    readonly property var _row: (parent?.visibleChildren ?? []).filter(c => c.filterChip === true)
    readonly property int _at: _row.indexOf(fc)
    width: fcRow.implicitWidth + 22; height: 30
    topLeftRadius: _at <= 0 ? Appearance.rounding.small : Appearance.rounding.joined
    bottomLeftRadius: topLeftRadius
    topRightRadius: _at === _row.length - 1 ? Appearance.rounding.small : Appearance.rounding.joined
    bottomRightRadius: topRightRadius
    color: _solid ? Appearance.colors.colPrimary : on ? Appearance.colors.colLayer3Accent
        : fcHover.hovered ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
    Behavior on color { ColorAnimation { duration: 140 } }
    Row {
        id: fcRow
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            visible: fc.symbol !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: fc.symbol; iconSize: 16
            fill: fc.on ? 1 : 0
            color: fc._solid ? Appearance.colors.colOnPrimary : fc.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: fc.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: fc._solid ? Appearance.colors.colOnPrimary : fc.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
        }
    }
    HoverHandler { id: fcHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: fc.picked() }
}
