import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// The in-game overlay's Now playing, at the foot of its panel: the music or video playing (MprisController's
// player), its art, title and artist, previous, play/pause, next. Hidden with nothing playing
Rectangle {
    id: root
    readonly property var player: MprisController.activePlayer
    visible: player !== null
    implicitHeight: 64
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    RowLayout {
        anchors { fill: parent; margins: 8; rightMargin: 10 }
        spacing: 10
        ClippingRectangle { // The cover art, cut to round corners
            Layout.preferredWidth: 48; Layout.preferredHeight: 48
            radius: Appearance.rounding.container
            color: Appearance.colors.colLayer4
            MaterialSymbol { anchors.centerIn: parent; text: "music_note"; iconSize: 24; color: Appearance.colors.colSubtext }
            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 96
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.player?.trackTitle || root.player?.identity || ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: text !== ""
                text: root.player?.trackArtist ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        MediaButton { icon: "skip_previous"; available: root.player?.canGoPrevious ?? false; onClicked: root.player.previous() }
        MediaButton {
            icon: root.player?.isPlaying ? "pause" : "play_arrow"
            main: true
            available: root.player?.canTogglePlaying ?? false
            onClicked: root.player.togglePlaying()
        }
        MediaButton { icon: "skip_next"; available: root.player?.canGoNext ?? false; onClicked: root.player.next() }
    }
}
