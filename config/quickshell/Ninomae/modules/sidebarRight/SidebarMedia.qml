import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets

/**
 * What's playing, in one row under the sliders: the cover, title and artist with the time, previous / play /
 * next, and the progress as a thin line along the bottom. The cover's own colour washes in from the left.
 * No layers: the wash is a gradient of the cover's main colour (ColorQuantizer works it out on the CPU), and
 * only the small cover is clipped, as the bar's is. The corners are set from outside (it joins the sliders).
 */
Rectangle {
    id: root
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property string title: StringUtils.cleanMusicTitle(player?.trackTitle) || Translation.tr("Unknown title")
    readonly property string artist: (player?.trackArtist ?? "") || (player?.identity ?? "")
    TrackTiming { id: timing; player: root.player }
    readonly property real progress: timing.hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0

    readonly property string artPath: CoverArt.coverFor(player) // Fetched by services/CoverArt.qml
    readonly property bool hasArt: artPath !== ""

    color: Appearance.colors.colLayer3
    radius: Appearance.rounding.normal
    implicitHeight: 64

    ColorQuantizer {
        id: quantizer
        source: root.artPath
        depth: 0 // One colour: the cover's average
        rescaleSize: 16
    }
    readonly property color washColor: hasArt && quantizer.colors.length > 0 ? quantizer.colors[0] : Appearance.colors.colPrimary

    Rectangle { // The wash, from the cover's side
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius; topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius; bottomRightRadius: root.bottomRightRadius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ColorUtils.transparentize(root.washColor, 0.72) }
            GradientStop { position: 0.75; color: ColorUtils.transparentize(root.washColor, 1) }
        }
    }

    MouseArea { // Clicking the card opens the full player
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            GlobalStates.sidebarRightOpen = false;
            GlobalStates.mediaControlsOpen = true;
        }
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 8; bottomMargin: 3 }
        spacing: 10
        Rectangle { // The cover, or a note on a squircle when there's none
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer4
            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.hasArt
                text: "music_note"
                iconSize: 22
                color: Appearance.colors.colOnLayer4
            }
            ClippingRectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                visible: root.hasArt
                StyledImage {
                    anchors.fill: parent
                    source: root.artPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    sourceSize: Qt.size(88, 88)
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer3
            }
            StyledText {
                Layout.fillWidth: true
                text: root.artist + (timing.hasLength
                    ? `${root.artist ? " · " : ""}${StringUtils.friendlyTimeForSeconds(timing.position)} / ${StringUtils.friendlyTimeForSeconds(timing.length)}` : "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
        IconButton {
            size: 30
            symbol: "skip_previous"
            tip: Translation.tr("Previous")
            enabled: root.player?.canGoPrevious ?? false
            colBackground: "transparent"
            onClicked: root.player?.previous()
        }
        IconButton {
            size: 34
            symbol: root.isPlaying ? "pause" : "play_arrow"
            tip: root.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
            toggled: true
            onClicked: root.player?.togglePlaying()
        }
        IconButton {
            size: 30
            symbol: "skip_next"
            tip: Translation.tr("Next")
            enabled: root.player?.canGoNext ?? false
            colBackground: "transparent"
            onClicked: root.player?.next()
        }
    }

    Rectangle { // Progress, along the bottom
        visible: timing.hasLength
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14; bottomMargin: 5 }
        height: 3
        radius: 2
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.88)
        Rectangle {
            width: parent.width * root.progress
            height: parent.height
            radius: 2
            color: Appearance.colors.colPrimary
            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
        }
    }
}
