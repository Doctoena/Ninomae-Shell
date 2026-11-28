import qs.modules.common
import qs.modules.common.functions
import Quickshell
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A control centre row's icon, on a squircle at the start of the row: a network's signal, a device's kind.
// `accent` for the one in use (the network you're on, a connected device). On glass the others are a light tint
Rectangle {
    id: root
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    property string symbol
    property bool accent: false
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: 36
    implicitHeight: 36
    radius: 11
    color: accent ? Appearance.colors.colPrimary
        : glass ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9) : Appearance.m3colors.m3surfaceContainerHighest
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: 20
        fill: 1
        color: root.accent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
    }
}
