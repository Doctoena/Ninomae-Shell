import qs.modules.common
import QtQuick
import QtQuick.Controls.Basic
/**
 * The shell's single-line text box (looks: TextFieldBackground)
 */
TextField {
    id: root
    renderType: Text.QtRendering // Not NativeRendering: small text looked uneven
    color: Appearance.colors.colOnSurface
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: "transparent" // TextFieldBackground shows it, as the label
    clip: true
    leftPadding: 14
    rightPadding: 14
    // A label (placeholderText) takes the top of the box: TextFieldBackground draws it there
    topPadding: placeholderText !== "" ? 24 : 10
    bottomPadding: placeholderText !== "" ? 8 : 10
    background: TextFieldBackground { field: root }
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }
}
