import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
// One option in a row of choices (ConfigSelectionArray). Squircle style like the rest of the shell: the
// row's outer ends are rounded rectangles, every option stays on the neutral surface, and the chosen
// one shows as an accent squircle behind its icon (a check, for text-only options) with its name in accent
GroupButton {
    id: root
    horizontalPadding: 10
    verticalPadding: 6
    bounce: false
    baseHeight: 24 + verticalPadding * 2 // Same with or without the squircle, so a row of options lines up
    property string buttonIcon
    property bool leftmost: false
    property bool rightmost: false
    readonly property bool hasIcon: buttonIcon.length > 0
    readonly property real outerRadius: 10
    readonly property real innerRadius: 4
    leftRadius: leftmost ? outerRadius : innerRadius
    rightRadius: rightmost ? outerRadius : innerRadius
    buttonRadiusPressed: outerRadius
    colBackground: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
    colBackgroundActive: Appearance.m3colors.m3surfaceContainerHighest
    colBackgroundToggled: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundToggledHover: Appearance.m3colors.m3surfaceContainerHighest
    colBackgroundToggledActive: Appearance.m3colors.m3surfaceContainerHighest
    contentItem: RowLayout {
        spacing: 6
        Rectangle {
            visible: root.hasIcon || root.toggled
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 24
            implicitHeight: 24
            radius: 8
            color: root.toggled ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary) // Not "transparent" (black): it would flash dark
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.hasIcon ? root.buttonIcon : "check"
                iconSize: Appearance.font.pixelSize.large
                fill: root.toggled ? 1 : 0
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
        }
        StyledText {
            visible: root.buttonText?.length > 0
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: root.hasIcon ? 2 : 0
            text: root.buttonText
            font.weight: root.toggled ? Font.DemiBold : Font.Normal
            color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }
    }
}
