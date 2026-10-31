import qs.modules.common
import qs.modules.common.functions
import QtQuick
/**
 * The text boxes' look (MaterialTextArea, MaterialTextField, MaterialSecretField): a filled squircle like the
 * buttons beside them, lighter on hover, with an accent outline while typing. A box with placeholderText is
 * taller and shows it as its label: inside the box while it's empty, small at the top once there's text
 * or you're typing (the fields leave room for it: topPadding).
 *   background: TextFieldBackground { field: root }
 */
Rectangle {
    id: root
    required property Item field
    readonly property bool hasLabel: (root.field.placeholderText ?? "") !== ""
    readonly property bool floated: root.field.activeFocus || root.field.length > 0
    implicitHeight: root.hasLabel ? 52 : 40
    radius: Appearance.rounding.container
    color: root.field.hovered && !root.field.activeFocus ? Appearance.m3colors.m3surfaceContainerHighest
        : Appearance.m3colors.m3surfaceContainerHigh
    border.width: root.field.activeFocus ? 2 : 0
    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
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
