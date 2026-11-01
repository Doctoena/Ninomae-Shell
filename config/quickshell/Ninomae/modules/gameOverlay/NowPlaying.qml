import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The in-game overlay's Now playing: the music or video playing (MprisController's player), its art, title and
// artist, previous, play/pause, next. Hidden with nothing playing
OverlayPanel {
    id: root
    readonly property var player: MprisController.activePlayer
    visible: player !== null
    implicitHeight: 88
    RowLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 14
        Rectangle {
            Layout.preferredWidth: 64; Layout.preferredHeight: 64
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            clip: true
            MaterialSymbol { anchors.centerIn: parent; text: "music_note"; iconSize: 28; color: Appearance.colors.colSubtext }
            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 128
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.player?.trackTitle || root.player?.identity || ""
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: text !== ""
                text: root.player?.trackArtist ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
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
