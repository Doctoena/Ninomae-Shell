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
 * Bar music widget: a pill with the round cover art inside a lavender progress ring,
 * title + artist, and a play/pause button. Left click opens the media panel, middle click
 * plays/pauses, right click (or mouse forward) skips, mouse back goes to the previous track.
 */
Item {
    id: root
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool hasMedia: activePlayer !== null
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property string artistText: (activePlayer?.trackArtist ?? "") || (activePlayer?.identity ?? "")
    // Kept through the gaps where a browser drops the length (TrackTiming.qml); none at all: no progress line
    TrackTiming { id: timing; player: root.activePlayer }
    readonly property real trackProgress: timing.hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0
    readonly property real maxMediaWidth: 300
    readonly property bool hovered: mouseArea.containsMouse || playMouse.containsMouse

    // ── Album art (downloaded once, shared with the media panel: services/CoverArt.qml) ──
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property string displayedArtFilePath: CoverArt.localUrl(artUrl)
    readonly property bool hasArt: displayedArtFilePath !== ""
    onArtUrlChanged: CoverArt.request(artUrl)
    Component.onCompleted: CoverArt.request(artUrl)


    Layout.fillHeight: false
    Layout.maximumWidth: maxMediaWidth
    implicitWidth: pill.width
    implicitHeight: pill.height

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        height: 30
        width: Math.min(root.maxMediaWidth, contentRow.implicitWidth + contentRow.anchors.leftMargin + contentRow.anchors.rightMargin)
        radius: 10
        color: root.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent" // A segment of the bar's shared right-side pill
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        clip: true

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

        Rectangle { // Track progress, along the bottom edge
            visible: root.hasMedia
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 2 }
            width: (parent.width - 16) * root.trackProgress
            height: 2
            radius: 1
            color: Appearance.colors.colPrimary
            // Steps once a second (~1-2 px) rather than gliding: a glide never ends while playing,
            // so the bar redrew at the full refresh rate (240 Hz) the whole time music played
        }
        RowLayout {
            id: contentRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 2; rightMargin: root.hasMedia ? 4 : 12 }
            spacing: 8

            // ── Cover art in a squircle (the track's progress runs along the segment's bottom edge) ──
            Item {
                id: artRing
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26

                // Badge when there's no art (or nothing playing)
                Rectangle {
                    anchors.centerIn: parent
                    width: 24; height: 24
                    radius: 8
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                    visible: !root.hasArt
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        fill: 1
                        iconSize: 15
                        color: root.hasMedia ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1Inactive
                    }
                }

                // The cover, dimmed while paused
                ClippingRectangle {
                    anchors.centerIn: parent
                    width: 24; height: 24
                    radius: 8
                    color: "transparent"
                    visible: root.hasArt
                    opacity: root.isPlaying ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        sourceSize: Qt.size(48, 48)
                    }
                }
            }

            // ── Title + artist (crossfade on track change) ──
            ColumnLayout {
                id: textColumn
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.maximumWidth: root.maxMediaWidth - 26 - 22 - contentRow.spacing * 2 - 7
                spacing: -3
                visible: Config.options.bar.verbose || !root.hasMedia
                StyledText {
                    Layout.fillWidth: true
                    visible: root.hasMedia
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: root.cleanedTitle
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.hasMedia && root.artistText.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: root.artistText
                }
                StyledText {
                    visible: !root.hasMedia
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1Inactive
                    text: Translation.tr("No media")
                }

                // Fade out and back in when the track changes
                Connections {
                    target: root
                    function onCleanedTitleChanged() { swap.restart(); }
                }
                SequentialAnimation {
                    id: swap
                    NumberAnimation { target: textColumn; property: "opacity"; to: 0; duration: 120; easing.type: Easing.OutCubic }
                    NumberAnimation { target: textColumn; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                }
            }

            // ── Play / pause ──
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasMedia
                implicitWidth: 22
                implicitHeight: 22
                radius: playMouse.pressed ? 6 : 8
                color: playMouse.containsMouse ? Appearance.colors.colPrimary
                    : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on radius { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: 15
                    color: playMouse.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                }
                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activePlayer?.togglePlaying()
                }
            }
        }
    }
}
