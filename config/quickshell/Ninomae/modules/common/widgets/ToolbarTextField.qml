import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic // Pin the Basic TextField: the Material one (now picked up on Qt 6.11) floats the placeholder onto the top edge while focused
import qs.modules.common
TextField {
    id: filterField
    property alias colBackground: background.color
    Layout.fillHeight: true
    implicitWidth: 200
    padding: 10
    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    // Classic on/off blink. The previous fade animated opacity continuously, which made the
    // whole window redraw every frame (240 fps here) for as long as the field had focus.
    cursorDelegate: Rectangle {
        id: cursor
        width: 2
        color: Appearance.colors.colPrimary
        property bool blinkOn: true
        visible: filterField.cursorVisible && blinkOn
        Timer {
            interval: 530
            repeat: true
            running: filterField.cursorVisible
            onTriggered: cursor.blinkOn = !cursor.blinkOn
            onRunningChanged: cursor.blinkOn = true
        }
        Connections { // Stay solid while typing or moving the cursor
            target: filterField
            function onCursorPositionChanged() { cursor.blinkOn = true; }
        }
    }
    background: Rectangle {
        id: background
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.container
    }
}
