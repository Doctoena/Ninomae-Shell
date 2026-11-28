import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// The top of the in-game overlay's panel: the game's banner art (a faint controller without), its name, this
// session's and all-time hours, the frame rate on the right when MangoHud gives one (fpsText, its average and low,
// and a small graph of the last minutes), and over a fullscreen game (showStatus) the clock and battery the hidden
// bar would show, in its corner. Its foot joins the quick actions under it
ClippingRectangle {
    id: root
    property string art: ""
    property string gameName: ""
    property string sessionText: ""
    property bool showStatus: false
    property string fpsText: "" // Empty: no frame rate
    property string fpsDetail: ""
    property var fpsPoints: [] // For LineGraph: Qt.point(x, value), 0–1
    implicitHeight: 200
    topLeftRadius: Appearance.rounding.normal
    topRightRadius: Appearance.rounding.normal
    bottomLeftRadius: Appearance.rounding.joined
    bottomRightRadius: Appearance.rounding.joined
    color: Appearance.colors.colLayer3
    MaterialSymbol {
        visible: root.art === ""
        anchors { left: parent.left; top: parent.top; margins: 14 }
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
            GradientStop { position: 0.3; color: "transparent" }
            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.08) }
        }
    }
    Rectangle { // The clock and battery, over a fullscreen game
        visible: root.showStatus
        anchors { right: parent.right; top: parent.top; margins: 10 }
        implicitWidth: statusRow.implicitWidth + 20
        implicitHeight: 28
        radius: Appearance.rounding.chip + 1
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.25)
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
    RowLayout {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.gameName
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Black
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: text !== ""
                text: root.sessionText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
            }
        }
        ColumnLayout { // The frame rate
            visible: root.fpsText !== ""
            Layout.alignment: Qt.AlignBottom
            spacing: -4
            StyledText {
                Layout.alignment: Qt.AlignRight
                text: root.fpsText
                font.family: Appearance.font.family.numbers
                font.pixelSize: 40
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.alignment: Qt.AlignRight
                text: root.fpsDetail
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
            }
            LineGraph {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: 8
                Layout.preferredWidth: 120
                Layout.preferredHeight: 12
                visible: root.fpsPoints.length > 1
                points: root.fpsPoints
                guides: false
            }
        }
    }
}
