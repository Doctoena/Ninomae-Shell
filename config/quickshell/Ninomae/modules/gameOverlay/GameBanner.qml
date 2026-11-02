import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// The top of the in-game overlay's panel: the game's banner art (a faint controller without), its name, this
// session's and all-time hours, and over a fullscreen game (showStatus) the clock and battery the hidden bar
// would show, in its corner
ClippingRectangle {
    id: root
    property string art: ""
    property string gameName: ""
    property string sessionText: ""
    property bool showStatus: false
    implicitHeight: 180
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    MaterialSymbol {
        visible: root.art === ""
        anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
        text: "sports_esports"
        iconSize: 72
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
    }
    Image {
        anchors.fill: parent
        visible: root.art !== ""
        source: root.art !== "" ? "file://" + root.art : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 900
    }
    Rectangle { // Keeps the text readable on any art
        anchors.fill: parent
        visible: root.art !== ""
        gradient: Gradient {
            GradientStop { position: 0.25; color: "transparent" }
            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.05) }
        }
    }
    Rectangle { // The clock and battery, over a fullscreen game
        visible: root.showStatus
        anchors { right: parent.right; top: parent.top; margins: 10 }
        implicitWidth: statusRow.implicitWidth + 20
        implicitHeight: 28
        radius: Appearance.rounding.chip + 2
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15)
        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: 10
            StyledText {
                text: DateTime.time
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Row {
                visible: Battery.available
                spacing: 3
                readonly property bool low: !Battery.isPluggedIn && Battery.percent <= 20
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.isPluggedIn ? "battery_charging_full" : parent.low ? "battery_alert" : "battery_full"
                    iconSize: 16
                    color: parent.low ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.percent + "%"
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: parent.low ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                }
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
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            visible: text !== ""
            text: root.sessionText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
