import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * A segment in a GlassPiece (a filter or a page): an icon if it has one, its name, and its count if given (quiet), on
 * the accent squircle while it's the one on. Doesn't take the keys (the page keeps them). picked() on a click
 */
RippleButton {
    id: seg
    property string label
    property string iconName: ""
    property int count: -1 // -1: none shown
    property bool on: false
    signal picked()
    focusPolicy: Qt.NoFocus
    implicitWidth: segRow.implicitWidth + 22
    implicitHeight: 28
    buttonRadius: Appearance.rounding.segment
    colBackground: on ? Appearance.colors.colLayer3Accent : ColorUtils.transparentize(Appearance.colors.colLayer3Accent, 1)
    colBackgroundHover: on ? Appearance.colors.colLayer3AccentHover : ColorUtils.transparentize("white", 0.92)
    colRipple: Appearance.colors.colLayer3Active
    onClicked: picked()
    contentItem: Item {
        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: seg.iconName !== ""
                text: seg.iconName; iconSize: 17; fill: seg.on ? 1 : 0
                color: seg.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: seg.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: seg.on ? Font.DemiBold : Font.Medium
                color: seg.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: seg.count >= 0
                text: seg.count
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({}) // Not Roboto Flex's tuning
                color: seg.on ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.25) : Appearance.colors.colSubtext
            }
        }
    }
}
