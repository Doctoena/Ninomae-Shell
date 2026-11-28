import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import QtQuick
/**
 * Material 3 dialog button. See https://m3.material.io/components/dialogs/overview
 */
RippleButton {
    id: root
    property bool primary: false // Filled lavender main action
    padding: 14
    implicitHeight: 34
    implicitWidth: buttonTextWidget.implicitWidth + padding * 2
    buttonRadius: Appearance.rounding.container
    property color colEnabled: Appearance?.colors.colOnSurfaceVariant ?? "#cbc5ca"
    property color colDisabled: Appearance?.colors.colOutline ?? "#8D8C96"
    // In a glass window (Settings, the control centre): the soft card with a rim (GlassFinish, B2)
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    colBackground: primary ? Appearance.colors.colPrimary : glass ? Appearance.colors.colWellRowHover : Appearance.colors.colLayer2
    colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : glass ? Appearance.colors.colWellRowActive : Appearance.colors.colLayer2Hover
    colRipple: primary ? Appearance.colors.colPrimaryActive : glass ? Appearance.colors.colWellRowActive : Appearance.colors.colLayer2Active
    GlassFinish {
        visible: root.glass
        radius: root.buttonRadius
        hovered: root.hovered
    }
    property alias colText: buttonTextWidget.color
    Behavior on colBackground {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    contentItem: StyledText {
        id: buttonTextWidget
        anchors.fill: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        text: buttonText
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
        font.weight: Font.Medium
        color: !root.enabled ? root.colDisabled : root.primary ? Appearance.colors.colOnPrimary : root.colEnabled
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
