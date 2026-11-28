import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * A page in a window's page list (Settings, the control centre): its icon on a squircle and its name. The open
 * one (`toggled`): the squircle in accent, the name in accent on a neutral row. `marked` (Settings' glass): no
 * squircle or row for the open one, its icon and name in the accent and a short accent bar at its left edge, the
 * soft card when pointed at. `expanded: false` shows the icon alone, in the middle of the row, with the name beside
 * it on hover.
 */
RippleButton {
    id: button
    property string symbol
    property real symbolRotation: 0
    property bool expanded: true
    property bool marked: false
    implicitHeight: 44
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: marked ? Appearance.colors.colWellRowHover : Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundToggled: marked ? "transparent" : Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundToggledHover: marked ? Appearance.colors.colWellRowHover : Appearance.m3colors.m3surfaceContainerHighest
    colRipple: marked ? Appearance.colors.colWellRowActive : Appearance.colors.colLayer1Active
    colRippleToggled: marked ? Appearance.colors.colWellRowActive : Appearance.m3colors.m3surfaceContainerHighest
    LitBar {
        visible: button.marked
        shown: button.toggled
        length: 18
        x: 1
        color: Appearance.colors.colPrimary
    }
    StyledToolTip { // Icons only: the name on hover, beside it (above, the window's edge would push it off centre)
        x: parent.width + 8
        y: (parent.height - height) / 2
        text: button.text
        visible: !button.expanded && button.hovered
    }
    leftPadding: 0
    rightPadding: 0
    contentItem: Item { // Placed by hand: collapsed, the squircle sits exactly in the middle of the row
        implicitHeight: 30
        Rectangle {
            id: squircle
            x: button.expanded ? 6 : Math.round((parent.width - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            radius: Appearance.rounding.segment
            color: button.toggled && !button.marked ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary) // Not black: no dark flash
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: button.symbol
                rotation: button.symbolRotation
                iconSize: Appearance.font.pixelSize.larger
                fill: button.toggled ? 1 : 0
                color: !button.toggled ? Appearance.colors.colOnSurfaceVariant : button.marked ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary
            }
        }
        StyledText {
            visible: button.expanded
            anchors { left: squircle.right; leftMargin: 12; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: button.text
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: button.toggled ? Font.DemiBold : Font.Medium
            color: button.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }
    }
}
