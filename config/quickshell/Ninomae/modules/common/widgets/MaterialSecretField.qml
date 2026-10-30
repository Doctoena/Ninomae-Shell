import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
/**
 * MaterialTextArea's filled look for a secret (an API key): hidden as dots until the eye button shows it.
 * Single line, so editingFinished fires on Enter as well as on losing focus. secret: false makes it a
 * plain field in the same look (e.g. a server URL next to its key).
 */
TextField {
    id: root
    property bool secret: true
    property bool revealed: false
    Material.theme: Material.System
    Material.accent: Appearance.colors.colPrimary
    Material.primary: Appearance.colors.colPrimary
    Material.background: Appearance.colors.colSurfaceContainer
    Material.foreground: Appearance.colors.colOnSurface
    Material.containerStyle: Material.Filled
    renderType: Text.QtRendering
    echoMode: revealed || !secret ? TextInput.Normal : TextInput.Password
    rightPadding: secret ? revealButton.width + 12 : 12
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
            color: root.activeFocus ? Appearance.colors.colPrimary :
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
    RippleButton {
        id: revealButton
        anchors {
            right: parent.right
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: 11
        visible: root.secret && root.text.length > 0
        onClicked: root.revealed = !root.revealed
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: root.revealed ? "visibility_off" : "visibility"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledToolTip {
            text: root.revealed ? Translation.tr("Hide") : Translation.tr("Show")
        }
    }
}
