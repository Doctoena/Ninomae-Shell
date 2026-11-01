import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// The in-game overlay's game card: its banner art (a faint controller without), its name, and this session's
// and all-time hours
OverlayPanel {
    id: root
    property string art: ""
    property string gameName: ""
    property string sessionText: ""
    implicitHeight: 170
    MaterialSymbol {
        visible: root.art === ""
        anchors { right: parent.right; top: parent.top; margins: 18 }
        text: "sports_esports"
        iconSize: 72
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
    }
    ClippingRectangle { // The art cut to the card's round corners, inside its border; none without art
        visible: root.art !== ""
        anchors { fill: parent; margins: root.border.width }
        radius: root.radius - root.border.width
        color: "transparent"
        Image {
            anchors.fill: parent
            source: root.art !== "" ? "file://" + root.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 800
        }
        Rectangle { // Keeps the text readable on any art
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.3; color: "transparent" }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.05) }
            }
        }
    }
    ColumnLayout {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
        spacing: 2
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.gameName
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            visible: text !== ""
            text: root.sessionText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
