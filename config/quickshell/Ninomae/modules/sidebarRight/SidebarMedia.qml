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
 * What's playing, as a card tinted by the cover's colour with a soft halo behind it, like the app search's
 * chosen result: where it plays (the player's icon and name), the title big and the artist, previous / play /
 * next, then the times with a scrubber between them. withSliders puts the sidebar's sliders (volume…) inside
 * it, under a hairline: one block for sound while something plays. Clicking the card opens the full player.
 * No layers: the colour is the cover's average (ColorQuantizer, on the CPU), and only the cover is clipped.
 * The corners are set from outside (it joins the tiles above it).
 */
Rectangle {
    id: root
    property bool withSliders: false
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property string title: StringUtils.cleanMusicTitle(player?.trackTitle) || Translation.tr("Unknown title")
    readonly property string artist: player?.trackArtist ?? ""
    TrackTiming { id: timing; player: root.player }
    readonly property real progress: timing.hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0
    readonly property bool canSeek: (player?.canSeek ?? false) && timing.hasLength

    readonly property string artPath: CoverArt.coverFor(player) // Fetched by services/CoverArt.qml
    readonly property bool hasArt: artPath !== ""
    readonly property string sourceIcon: Quickshell.iconPath(player?.desktopEntry ?? "", true)

    ColorQuantizer {
        id: quantizer
        source: root.artPath
        depth: 0 // One colour: the cover's average
        rescaleSize: 16
    }
    readonly property color tint: hasArt && quantizer.colors.length > 0 ? quantizer.colors[0] : Appearance.colors.colPrimary

    color: ColorUtils.mix(Appearance.colors.colLayer3, tint, 0.84)
    Behavior on color { ColorAnimation { duration: 300 } }
    border.width: 1.5
    border.color: ColorUtils.transparentize(tint, 0.6)
    radius: Appearance.rounding.normal
    implicitHeight: 92 + (withSliders ? slidersLoader.implicitHeight + 1 : 0)
    clip: true

    Halo { // The halo behind the cover
        colour: root.tint
        strength: 0.5
        reach: 45
        centreX: cover.x + cover.width / 2
        centreY: cover.y + cover.height / 2
    }

    MouseArea { // Clicking the card opens the full player
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 92
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            GlobalStates.sidebarRightOpen = false;
            GlobalStates.mediaControlsOpen = true;
        }
    }

    Rectangle { // The cover, or a note on a squircle when there's none
        id: cover
        x: 12
        y: 12
        width: 68
        height: 68
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer4
        MaterialSymbol {
            anchors.centerIn: parent
            visible: !root.hasArt
            text: "music_note"
            iconSize: 30
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
                sourceSize: Qt.size(136, 136)
            }
        }
    }

    ColumnLayout { // Where it plays, the title, the artist
        anchors { left: cover.right; right: controls.left; top: parent.top; leftMargin: 14; rightMargin: 8; topMargin: 11 }
        spacing: 0
        RowLayout {
            spacing: 5
            IconImage {
                visible: root.sourceIcon !== ""
                implicitSize: 14
                source: root.sourceIcon
            }
            StyledText {
                Layout.fillWidth: true
                text: root.player?.identity ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: ColorUtils.mix(Appearance.colors.colOnLayer3, root.tint, 0.55)
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.family: Appearance.font.family.title
            font.weight: Font.Black
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer3
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.artist
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: ColorUtils.mix(Appearance.colors.colOnLayer3, root.tint, 0.65)
        }
    }

    RowLayout {
        id: controls
        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 18 }
        spacing: 2
        IconButton {
            size: 32
            symbol: "skip_previous"
            tip: Translation.tr("Previous")
            enabled: root.player?.canGoPrevious ?? false
            colBackground: "transparent"
            onClicked: root.player?.previous()
        }
        IconButton {
            size: 38
            symbol: root.isPlaying ? "pause" : "play_arrow"
            tip: root.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
            toggled: true
            onClicked: root.player?.togglePlaying()
        }
        IconButton {
            size: 32
            symbol: "skip_next"
            tip: Translation.tr("Next")
            enabled: root.player?.canGoNext ?? false
            colBackground: "transparent"
            onClicked: root.player?.next()
        }
    }

    RowLayout { // The times, with the scrubber between them
        anchors { left: cover.right; right: parent.right; leftMargin: 14; rightMargin: 12; top: parent.top; topMargin: 64 }
        spacing: 8
        opacity: timing.hasLength ? 1 : 0 // Keeps its place so the card doesn't jump
        TimeText { text: StringUtils.friendlyTimeForSeconds(timing.position) }
        SlimSlider {
            Layout.fillWidth: true
            ringColor: root.color
            enabled: root.canSeek
            wheelEnabled: false // A stray scroll shouldn't jump the track
            level: root.progress
            onMoved: if (root.canSeek) root.player.position = value * timing.length
        }
        TimeText { text: StringUtils.friendlyTimeForSeconds(timing.length) }
    }

    Rectangle { // A hairline over the sliders
        visible: root.withSliders
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 92; leftMargin: 12; rightMargin: 12 }
        height: 1
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
    }
    Loader {
        id: slidersLoader
        active: root.withSliders
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 93 }
        sourceComponent: QuickSliders {
            color: "transparent"
            ringColor: root.color
        }
    }

    component TimeText: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.family: Appearance.font.family.numbers
        font.variableAxes: ({})
        color: Appearance.colors.colSubtext
    }
}
