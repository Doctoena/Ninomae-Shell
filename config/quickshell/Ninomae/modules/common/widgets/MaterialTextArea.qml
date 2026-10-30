import qs.modules.common
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
/**
 * Material 3 styled TextArea (filled style)
 * https://m3.material.io/components/text-fields/overview
 * Note: We don't use NativeRendering because it makes the small placeholder text look weird
 */
TextArea {
    id: root
    Material.theme: Material.System
    Material.accent: Appearance.colors.colPrimary
    Material.primary: Appearance.colors.colPrimary
    Material.background: Appearance.colors.colSurfaceContainer
    Material.foreground: Appearance.colors.colOnSurface
    Material.containerStyle: Material.Filled
    renderType: Text.QtRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.colors.colOutline
    background: Rectangle {
        implicitHeight: 56
        color: Appearance.colors.colSurfaceContainer
        topLeftRadius: 4
        topRightRadius: 4
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: root.focus ? Appearance.colors.colPrimary :
                root.hovered ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap
}
