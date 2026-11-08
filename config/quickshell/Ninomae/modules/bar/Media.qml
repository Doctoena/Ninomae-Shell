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
 * Bar player, in the middle of the bar while something plays: the cover,
 * title and artist with the time, previous / play-pause / next, and the
 * track's progress along the bottom edge. As the sidebar's player. Left click opens the media panel, middle click
 * plays/pauses, right click (or mouse forward) skips, mouse back goes to the previous track.
 */
Item {
    id: root
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle)
    readonly property string artistText: (activePlayer?.trackArtist ?? "") || (activePlayer?.identity ?? "")
    // Kept through the gaps where a browser drops the length (TrackTiming.qml); none at all: no progress or times
    TrackTiming { id: timing; player: root.activePlayer }
    readonly property real trackProgress: timing.hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0
    readonly property string timeText: timing.hasLength
        ? `${StringUtils.friendlyTimeForSeconds(timing.position)} / ${StringUtils.friendlyTimeForSeconds(timing.length)}` : ""
    readonly property real maxMediaWidth: 420
    readonly property bool hovered: mouseArea.containsMouse || playMouse.containsMouse || prevButton.pointed || nextButton.pointed

    // ── Album art (fetched by services/CoverArt.qml, shared with the media panel and the sidebar) ──
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property string displayedArtFilePath: CoverArt.coverFor(activePlayer)
    // The cover shown: the last one stays while the next downloads (its path is empty until then), so a track
    // change doesn't flash the note badge in between
    property string shownArt: ""
    onDisplayedArtFilePathChanged: if (displayedArtFilePath !== "" || artUrl === "") shownArt = displayedArtFilePath
    readonly property bool hasArt: shownArt !== ""
    Component.onCompleted: {
        shownArt = displayedArtFilePath;
        settle();
    }

    // ── Track change: the old title slides out fading, the card resizes while the text is away, the new one
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
            NumberAnimation { target: textColumn; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: textShift; property: "x"; to: -6; duration: 140; easing.type: Easing.InCubic }
        }
        ScriptAction { // The new text in place (still unseen): the card's width glides to fit it
            script: {
                root.settle();
                root.changing = false;
                textShift.x = 6;
            }
        }
        PauseAnimation { duration: 90 }
        ParallelAnimation {
            NumberAnimation { target: textColumn; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: textShift; property: "x"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        }
    }

    implicitWidth: pill.width
    implicitHeight: pill.height

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: 36 // As every card on the bar
        width: Math.min(root.maxMediaWidth, contentRow.implicitWidth + contentRow.anchors.leftMargin + contentRow.anchors.rightMargin)
        radius: Appearance.rounding.container
        color: root.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        MouseArea {
            id: mouseArea
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

        Rectangle { // Track progress along the bottom edge, on a faint track
            visible: timing.hasLength
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 10; rightMargin: 10; bottomMargin: 2 }
            height: 2
            radius: 1
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
            Rectangle {
                width: parent.width * root.trackProgress
                height: parent.height
                radius: 1
                color: Appearance.colors.colPrimary
                // Steps once a second (~1-2 px) rather than gliding: a glide never ends while playing,
                // so the bar redrew at the full refresh rate (240 Hz) the whole time music played
            }
        }
        RowLayout {
            id: contentRow
            // The art and the buttons as far from the card's sides as from its top and bottom
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 5; rightMargin: 5 }
            spacing: 8

            // ── Cover art in a squircle ──
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                Rectangle { // Badge when there's no art
                    anchors.fill: parent
                    radius: Appearance.rounding.chip
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                    visible: !root.hasArt
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        fill: 1
                        iconSize: 15
                        color: Appearance.colors.colPrimary
                    }
                }
                ClippingRectangle { // The cover, dimmed while paused
                    anchors.fill: parent
                    radius: Appearance.rounding.chip
                    color: "transparent"
                    visible: root.hasArt
                    opacity: root.isPlaying ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    // Two covers crossfading: the new one fades in over the old, which then lets go of its picture
                    // Cached: covers are stored by their URL's hash, so a file never changes under its name, and the
                    // old cover comes back from memory at once rather than being read again mid-swap
                    Image {
                        id: oldCover
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(52, 52)
                    }
                    StyledImage {
                        id: cover
                        anchors.fill: parent
                        source: root.shownArt
                        fillMode: Image.PreserveAspectCrop
                        retainWhileLoading: false // Empty until the new one's ready, so it can fade in over the old
                        sourceSize: Qt.size(52, 52)
                        property string lastSource: ""
                        onSourceChanged: {
                            oldCover.source = lastSource;
                            lastSource = source;
                        }
                        onStatusChanged: if (status === Image.Ready) oldCoverRelease.restart()
                        Timer { id: oldCoverRelease; interval: 600; onTriggered: oldCover.source = "" }
                    }
                }
            }

            // ── Title, artist and time (they slide across on a track change, see trackSwap) ──
            ColumnLayout {
                id: textColumn
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: -3
                transform: Translate { id: textShift }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: root.titleShown
                }
                StyledText {
                    id: subtitle
                    Layout.fillWidth: true
                    // Measured with every digit a 0: the time ticking doesn't nudge the card's width each second
                    Layout.preferredWidth: subtitleMetrics.advanceWidth
                    visible: text.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: [root.artistShown, root.timeText].filter(t => t).join(" · ")
                    TextMetrics {
                        id: subtitleMetrics
                        font: subtitle.font
                        text: subtitle.text.replace(/[0-9]/g, "0")
                    }
                }
            }

            // ── Previous / play-pause / next ──
            SkipButton {
                id: prevButton
                symbol: "skip_previous"
                enabled: root.activePlayer?.canGoPrevious ?? false
                onClicked: root.activePlayer?.previous()
            }
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                radius: playMouse.pressed ? 6 : 8
                color: playMouse.containsMouse ? Qt.lighter(Appearance.colors.colPrimary, 1.08) : Appearance.colors.colPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on radius { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: 16
                    color: Appearance.colors.colOnPrimary
                }
                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activePlayer?.togglePlaying()
                }
            }
            SkipButton {
                id: nextButton
                symbol: "skip_next"
                enabled: root.activePlayer?.canGoNext ?? false
                onClicked: root.activePlayer?.next()
            }
        }
    }

    // A small previous / next button: just the glyph, a soft squircle behind it while pointed at
    component SkipButton: Rectangle {
        id: skip
        property string symbol
        signal clicked()
        readonly property bool pointed: skipMouse.containsMouse
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 22
        implicitHeight: 26
        radius: Appearance.rounding.chip
        opacity: enabled ? 1 : 0.4
        color: pointed ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: skip.symbol
            fill: 1
            iconSize: 16
            color: skip.pointed ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
        }
        MouseArea {
            id: skipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: skip.clicked()
        }
    }
}
