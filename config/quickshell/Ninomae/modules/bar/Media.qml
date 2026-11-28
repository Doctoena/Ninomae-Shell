import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris

/**
 * Bar player (Ca), in the middle of the bar while something plays, in the colour of its cover (CoverTint): the cover,
 * round, is the play/pause button, a fine ring round it showing how far through the track you are over a faint full
 * circle (quieter while paused); pointed at or paused, the cover darkens with play/pause on it. Then one line: the
 * title, a dot (as between the bar's parts), the artist in the cover's colour.
 * Left click opens the media panel (previous / next are there), middle click plays/pauses, right click (or mouse
 * forward) skips, mouse back goes to the previous track.
 */
Item {
    id: root
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle, activePlayer?.trackArtist)
    readonly property string artistText: (activePlayer?.trackArtist ?? "") || AppSearch.playerName(activePlayer)
    // Kept through the gaps where a browser drops the length (TrackTiming.qml); none at all: no ring
    TrackTiming { id: timing; player: root.activePlayer }
    readonly property real maxMediaWidth: 420
    // The cover's colour as it glides between tracks: the bar's capsule behind the player is lit with it (BarContent)
    readonly property color accentColour: accentFade.color

    // ── Album art (fetched by services/CoverArt.qml, shared with the media panel and the sidebar) ──
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property string displayedArtFilePath: CoverArt.coverFor(activePlayer)
    // The cover shown: the last one stays while the next downloads (its path is empty until then), so a track
    // change doesn't flash the note badge in between
    property string shownArt: ""
    onDisplayedArtFilePathChanged: if (displayedArtFilePath !== "" || artUrl === "") shownArt = displayedArtFilePath
    readonly property bool hasArt: shownArt !== ""
    CoverTint { id: tint; cover: root.shownArt }
    // The cover's colours, gliding to the next cover's (through hidden Rectangles' own colour, as in the drawer)
    Rectangle { id: accentFade; visible: false; color: tint.accent; Behavior on color { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } } }
    Rectangle { id: subtextFade; visible: false; color: tint.subtext; Behavior on color { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } } }
    Component.onCompleted: {
        shownArt = displayedArtFilePath;
        settle();
    }

    // ── Track change: the old line slides out fading, the player resizes while the text is away, the new one
    // slides in. The cover crossfades as the new one loads ──
    property string settledTitle: ""
    property string settledArtist: ""
    property bool changing: false // The old title and artist are held while they fade out
    readonly property string titleShown: changing ? settledTitle : cleanedTitle
    readonly property string artistShown: changing ? settledArtist : artistText
    function settle() {
        settledTitle = cleanedTitle;
        settledArtist = artistText;
    }
    onCleanedTitleChanged: {
        if (settledTitle === "") settle(); // The first track: nothing to change from
        else if (!changing && cleanedTitle !== settledTitle) {
            changing = true;
            trackSwap.restart();
        }
    }
    // The artist alone changing (a player filling it in late) just updates. Checked a moment later: a new track's
    // title and artist arrive together, and the title's change has to start the swap first
    onArtistTextChanged: Qt.callLater(() => { if (!changing && cleanedTitle === settledTitle) settledArtist = artistText; })
    SequentialAnimation {
        id: trackSwap
        ParallelAnimation {
            NumberAnimation { target: textLine; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: textShift; property: "x"; to: -6; duration: 140; easing.type: Easing.InCubic }
        }
        ScriptAction { // The new text in place (still unseen): the player's width glides to fit it
            script: {
                root.settle();
                root.changing = false;
                textShift.x = 6;
            }
        }
        PauseAnimation { duration: 90 }
        ParallelAnimation {
            NumberAnimation { target: textLine; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: textShift; property: "x"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        }
    }

    implicitWidth: pill.width
    implicitHeight: pill.height

    Item {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: 36 // As every part of the bar
        // Rounded up: a fraction of a pixel short and the title elides its last letters
        width: Math.min(root.maxMediaWidth, Math.ceil(contentRow.implicitWidth) + contentRow.anchors.leftMargin + contentRow.anchors.rightMargin)
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton | Qt.BackButton | Qt.ForwardButton
            onPressed: (event) => {
                if (event.button === Qt.LeftButton) GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
                else if (!root.activePlayer) return;
                else if (event.button === Qt.MiddleButton) root.activePlayer.togglePlaying();
                else if (event.button === Qt.BackButton) root.activePlayer.previous();
                else root.activePlayer.next(); // Right / forward
            }
        }

        RowLayout {
            id: contentRow
            // The ring at the very left: it's the round end of the capsule behind the player (BarContent); 10 px after
            // the line to the capsule's other end
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 0; rightMargin: 10 }
            spacing: 9

            // ── The cover, round, in its progress ring: the play/pause button ──
            Item {
                id: coverButton
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 30
                implicitHeight: 30
                readonly property bool showControl: playMouse.containsMouse || !root.isPlaying

                UsageRing { // How far through the track, from the top, clockwise, over a faint full circle
                    anchors.fill: parent
                    visible: timing.hasLength
                    size: 30
                    stroke: 1.5
                    fraction: timing.length > 0 ? timing.position / timing.length : 0
                    colour: accentFade.color
                    trackColour: ColorUtils.transparentize(accentFade.color, 0.82)
                    icon: ""
                    opacity: root.isPlaying ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }
                Item {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    Rectangle { // Badge when there's no art
                        anchors.fill: parent
                        radius: width / 2
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                        visible: !root.hasArt
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "music_note"
                            fill: 1
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                            opacity: coverButton.showControl ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                    ClippingRectangle { // The cover
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        visible: root.hasArt
                        // Two covers crossfading: the new one fades in over the old, which then lets go of its picture
                        // Cached: covers are stored by their URL's hash, so a file never changes under its name, and
                        // the old cover comes back from memory at once rather than being read again mid-swap
                        Image {
                            id: oldCover
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(44, 44)
                        }
                        StyledImage {
                            id: cover
                            anchors.fill: parent
                            source: root.shownArt
                            fillMode: Image.PreserveAspectCrop
                            retainWhileLoading: false // Empty until the new one's ready, so it can fade in over the old
                            sourceSize: Qt.size(44, 44)
                            property string lastSource: ""
                            onSourceChanged: {
                                oldCover.source = lastSource;
                                lastSource = source;
                            }
                            onStatusChanged: if (status === Image.Ready) oldCoverRelease.restart()
                            Timer { id: oldCoverRelease; interval: 600; onTriggered: oldCover.source = "" }
                        }
                    }
                    Rectangle { // Darkening, with play/pause on it, when pointed at or paused
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                        opacity: coverButton.showControl ? (playMouse.pressed ? 0.7 : 0.55) : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "pause" : "play_arrow"
                        fill: 1
                        iconSize: 15
                        color: "white"
                        opacity: coverButton.showControl ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        // A new symbol (play ↔ pause) springs in from half size. A handler, not a Behavior on text:
                        // StyledText already has one of those
                        onTextChanged: playSymbolPop.restart()
                        NumberAnimation on scale { id: playSymbolPop; running: false; from: 0.5; to: 1; duration: 280; easing.type: Easing.OutBack }
                    }
                }
                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activePlayer?.togglePlaying()
                }
            }

            // ── One line: the title, a dot, the artist (they slide across on a track change, see trackSwap) ──
            RowLayout {
                id: textLine
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: 6
                transform: Translate { id: textShift }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: implicitWidth
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Medium
                    // Not the main font's own weight axis: it won over font.weight, so the title was measured at one
                    // weight and drawn wider at another, and lost its last letters
                    font.variableAxes: ({})
                    color: Appearance.colors.colOnLayer0
                    opacity: root.isPlaying ? 1 : 0.6
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    elide: Text.ElideRight
                    text: root.titleShown
                }
                Rectangle {
                    visible: artist.text.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 3
                    implicitHeight: 3
                    radius: 1.5
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.4
                }
                StyledText {
                    id: artist
                    visible: text.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: subtextFade.color
                    opacity: root.isPlaying ? 1 : 0.6
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    text: root.artistShown
                }
            }
        }
    }
}
