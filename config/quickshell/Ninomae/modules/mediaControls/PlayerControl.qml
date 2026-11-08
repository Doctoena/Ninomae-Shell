pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets

/**
 * One player in the media drawer: a big cover on the left; beside it which app it is, the title and artist,
 * a slim seek bar with the times, and shuffle / previous / play-pause / next / repeat. A soft glow of the
 * cover's colours sits behind it all.
 */
Item {
    id: root
    required property MprisPlayer player
    property real radius: Appearance.rounding.large

    readonly property bool isPlaying: player?.isPlaying ?? false
    // Length and position, kept through the gaps where a browser drops them (TrackTiming.qml). With no
    // length at all there's no progress, seeking or times to show (a seek would jump to 0:00)
    TrackTiming { id: timing; player: root.player }
    readonly property bool hasLength: timing.hasLength
    readonly property real progress: hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0
    readonly property bool canSeek: (player?.canSeek ?? false) && hasLength
    readonly property bool canShuffle: (player?.shuffleSupported ?? false) && (player?.canControl ?? false)
    readonly property bool canLoop: (player?.loopSupported ?? false) && (player?.canControl ?? false)

    // ── Cover art (fetched by services/CoverArt.qml, shared with the bar and the sidebar) ──
    readonly property string displayedArtFilePath: CoverArt.coverFor(player)

    implicitHeight: row.implicitHeight

    // ── The cover's colours, glowing softly from the left ──
    // No layers: the clip is a ClippingRectangle, and the "blur" is the cover decoded at 14px and
    // stretched (smooth scaling makes it soft). Both used to be offscreen layers, the kind of GPU work
    // that hung the Intel iGPU in the drawers
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        Image {
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize: Qt.size(14, 14)
            smooth: true
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
            opacity: status === Image.Ready ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6) }
                GradientStop { position: 1.0; color: Appearance.colors.colLayer0 }
            }
        }
    }

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 16

        // ── Cover ──
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.leftMargin: 16
            Layout.topMargin: 16
            Layout.bottomMargin: 18
            implicitWidth: 168
            implicitHeight: 168
            Rectangle { // Shown until the art loads, or when there is none
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                MaterialSymbol { anchors.centerIn: parent; text: "music_note"; fill: 1; iconSize: 56; color: Appearance.colors.colPrimary }
            }
            ClippingRectangle {
                anchors.fill: parent
                visible: root.displayedArtFilePath !== ""
                radius: Appearance.rounding.normal
                color: "transparent"
                StyledImage {
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    sourceSize: Qt.size(336, 336)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 14
            Layout.rightMargin: 16
            spacing: 2

            // ── Which player this is ──
            Rectangle {
                Layout.bottomMargin: 4
                implicitWidth: sourceRow.implicitWidth + 16
                implicitHeight: 22
                radius: Appearance.rounding.chip
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                Row {
                    id: sourceRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: root.isPlaying ? "graphic_eq" : "pause_circle"; fill: 1; iconSize: 13; color: Appearance.colors.colPrimary }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.player?.identity ?? Translation.tr("Player")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // ── Title and artist ──
            StyledText {
                Layout.fillWidth: true
                font.family: Appearance.font.family.title
                font.pixelSize: 22
                font.weight: Font.Black
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Untitled")
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                visible: text.length > 0
                text: root.player?.trackArtist ?? ""
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            // ── Seek bar and times ──
            SlimSlider {
                Layout.fillWidth: true
                Layout.topMargin: 8
                ringColor: Appearance.colors.colLayer0
                enabled: root.canSeek
                wheelEnabled: false // A stray scroll shouldn't jump the track
                opacity: root.hasLength ? 1 : 0.4
                level: root.progress
                onMoved: if (root.canSeek) root.player.position = value * timing.length
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                opacity: root.hasLength ? 1 : 0 // Keeps its height so the card doesn't jump
                TimeText { text: StringUtils.friendlyTimeForSeconds(timing.position) }
                Item { Layout.fillWidth: true }
                TimeText { text: StringUtils.friendlyTimeForSeconds(timing.length) }
            }

            // ── Controls ──
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                spacing: 6
                ControlButton { // Shuffle: always there, dimmed for players that can't (browsers)
                    size: 30
                    flat: true
                    enabled: root.canShuffle
                    active: root.player?.shuffle ?? false
                    iconName: "shuffle"
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
                ControlButton {
                    size: 38
                    iconName: "skip_previous"
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player.previous()
                }
                Rectangle { // Play / pause: a squircle, rounder while paused
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: playMouse.pressed ? 11 : root.isPlaying ? 14 : 19
                    color: playMouse.containsMouse ? Qt.lighter(Appearance.colors.colPrimary, 1.06) : Appearance.colors.colPrimary
                    Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "pause" : "play_arrow"
                        fill: 1
                        iconSize: 24
                        color: Appearance.colors.colOnPrimary
                    }
                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player?.togglePlaying()
                    }
                }
                ControlButton {
                    size: 38
                    iconName: "skip_next"
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player.next()
                }
                ControlButton { // Repeat: off → playlist → track. Always there, dimmed for players that can't
                    size: 30
                    flat: true
                    enabled: root.canLoop
                    active: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                    iconName: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                    onClicked: {
                        const s = root.player.loopState;
                        root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                            : s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
                    }
                }
            }
        }
    }

    component TimeText: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.numbers
        font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
        color: Appearance.colors.colSubtext
    }

    // A squircle control; `flat` ones (shuffle, repeat) have no card until pointed at, `active` ones show in accent
    component ControlButton: Rectangle {
        id: ctl
        property string iconName
        property real size: 38
        property bool flat: false
        property bool active: false
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 3 // Squircles, like the quick toggles' icons
        opacity: enabled ? 1 : 0.4
        color: active ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
            : flat ? (ctlMouse.containsMouse ? Appearance.m3colors.m3surfaceContainerHigh : "transparent")
            : (ctlMouse.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: ctlMouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ctl.iconName
            fill: 1
            iconSize: Math.round(ctl.size * 0.5)
            color: ctl.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
        }
        MouseArea {
            id: ctlMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: ctl.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: ctl.clicked()
        }
    }
}
