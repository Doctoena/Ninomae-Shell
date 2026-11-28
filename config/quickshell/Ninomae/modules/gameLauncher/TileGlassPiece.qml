import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * The glass piece on a library tile's cover while it's pointed at (GameGridItem, and Add a game's preview of one):
 * the name over its hours and when it was last played (New in the accent: never played), and a button on the accent
 * squircle (▶, or Add). Darker than the panels' glass (glass): a tile has no blur of its own, so a cover's logo would
 * read through it. A fine light along its top
 */
Rectangle {
    id: piece
    property string name
    property int minutes: 0
    property real lastPlayed: 0 // 0: not shown (a tile at rest passes 0: no clock work for a library of them)
    property string buttonIcon: "play_arrow"
    property string buttonTip: Translation.tr("Play")
    property bool showButton: true
    readonly property bool buttonHovered: buttonMouse.containsMouse
    signal buttonClicked()
    // The glass of the pieces on a cover (this, and the tile's state badge)
    readonly property color glass: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.2)

    height: 46
    radius: 13
    color: glass
    border { width: 1; color: ColorUtils.transparentize("white", 0.9) }

    EdgeLight { // The fine light along its top, brightest in the middle
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: piece.radius; rightMargin: piece.radius }
        strength: 0.3
    }
    Column {
        anchors { left: parent.left; leftMargin: 11; right: button.visible ? button.left : parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        StyledText {
            width: parent.width
            text: piece.name
            color: Appearance.colors.colOnLayer3
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        Row {
            width: parent.width
            spacing: 5
            clip: true
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: piece.minutes >= 60 ? Math.floor(piece.minutes / 60) + " h" : piece.minutes > 0 ? piece.minutes + " min" : Translation.tr("New")
                color: piece.minutes > 0 ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({}) // Not Roboto Flex's tuning
            }
            Rectangle { // A dot between, as the glass pieces elsewhere
                visible: piece.lastPlayed > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 3; radius: 1.5
                color: Appearance.colors.colSubtext
                opacity: 0.6
            }
            StyledText {
                visible: piece.lastPlayed > 0
                anchors.verticalCenter: parent.verticalCenter
                text: visible ? GameLauncherService.agoText(piece.lastPlayed) : ""
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }
    }
    Rectangle {
        id: button
        visible: piece.showButton
        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
        width: 36; height: 36
        radius: 10
        color: buttonMouse.pressed ? Appearance.colors.colPrimaryActive
            : buttonMouse.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
        Behavior on color { ColorAnimation { duration: 120 } }
        MaterialSymbol {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: piece.buttonIcon === "play_arrow" ? 1 : 0 // ▶ looks centred a pixel right
            text: piece.buttonIcon
            iconSize: piece.buttonIcon === "play_arrow" ? 21 : 18
            fill: 1
            color: Appearance.colors.colOnPrimary
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: piece.buttonClicked()
        }
        StyledToolTip { text: piece.buttonTip; extraVisibleCondition: buttonMouse.containsMouse }
    }
}
