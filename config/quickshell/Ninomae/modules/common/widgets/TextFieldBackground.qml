import qs.modules.common
import qs.modules.common.functions
import Quickshell
import QtQuick
/**
 * The text boxes' look (StyledTextArea, StyledTextField, StyledSecretField): a filled squircle like the
 * buttons beside them, lighter on hover, with an accent outline while typing. A box with placeholderText is
 * taller and shows it as its label: inside the box while it's empty, small at the top once there's text
 * or you're typing (the fields leave room for it: topPadding).
 *   background: TextFieldBackground { field: root }
 * A settings row's field (StyledSecretField) sets the card's colours and its group's corners instead (`asRow`).
 * In a glass window (Settings) a darker field with a fine light rim, as the search boxes; a row's
 * field is clear on its well, the soft card when pointed at.
 */
Rectangle {
    id: root
    required property Item field
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    property bool asRow: false
    readonly property bool hasLabel: (root.field.placeholderText ?? "") !== ""
    readonly property bool floated: root.field.activeFocus || root.field.length > 0
    property color restColor: Appearance.m3colors.m3surfaceContainerHigh
    property color hoverColor: Appearance.m3colors.m3surfaceContainerHighest
    property real topRadius: -1 // -1: as `radius`
    property real bottomRadius: -1
    implicitHeight: root.hasLabel ? 52 : 40
    radius: Appearance.rounding.container
    topLeftRadius: topRadius >= 0 ? topRadius : radius
    topRightRadius: topRadius >= 0 ? topRadius : radius
    bottomLeftRadius: bottomRadius >= 0 ? bottomRadius : radius
    bottomRightRadius: bottomRadius >= 0 ? bottomRadius : radius
    readonly property bool lifted: root.field.hovered && !root.field.activeFocus
    color: !root.glass ? (lifted ? root.hoverColor : root.restColor)
        : root.asRow ? (lifted ? Appearance.colors.colWellRowHover : "transparent")
        : lifted ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45) : Appearance.colors.colGlassField
    border.width: root.field.activeFocus ? 2 : root.glass && !root.asRow ? 1 : 0
    border.color: root.field.activeFocus ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : Appearance.colors.colGlassFieldRim
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Text { // The label (placeholderText)
        visible: root.hasLabel
        x: root.field.leftPadding
        width: parent.width - root.field.leftPadding - root.field.rightPadding
        y: root.floated ? 7 : (parent.height - height) / 2
        text: root.field.placeholderText ?? ""
        elide: Text.ElideRight
        renderType: Text.QtRendering
        font.family: Appearance.font.family.main
        font.pixelSize: root.floated ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
        color: root.floated && root.field.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        Behavior on y {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on font.pixelSize {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
