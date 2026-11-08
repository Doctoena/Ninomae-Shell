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

    // ── Album art (downloaded once, shared with the media panel: services/CoverArt.qml) ──
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property string displayedArtFilePath: CoverArt.localUrl(artUrl)
    readonly property bool hasArt: displayedArtFilePath !== ""
    onArtUrlChanged: CoverArt.request(artUrl)
    Component.onCompleted: CoverArt.request(artUrl)

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
                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        sourceSize: Qt.size(52, 52)
                    }
                }
            }

            // ── Title, artist and time (crossfade on track change) ──
            ColumnLayout {
                id: textColumn
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: -3
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: root.cleanedTitle
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
                    text: [root.artistText, root.timeText].filter(t => t).join(" · ")
                    TextMetrics {
                        id: subtitleMetrics
                        font: subtitle.font
                        text: subtitle.text.replace(/[0-9]/g, "0")
                    }
                }
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
