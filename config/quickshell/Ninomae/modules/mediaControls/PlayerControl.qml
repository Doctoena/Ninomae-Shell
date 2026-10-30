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
 * One player in the media drawer: cover + title/artist, a wavy seek bar with times, and a
 * centred control row. Theme colours throughout, with a faint blurred cover glow behind.
 */
Item {
    id: root
    required property MprisPlayer player
    property var visualizerPoints: []
    property real maxVisualizerValue: 1000
    property int visualizerSmoothing: 2
    property real radius: Appearance.rounding.large

    readonly property bool isPlaying: player?.isPlaying ?? false
    // Length and position, kept through the gaps where a browser drops them (TrackTiming.qml). With no
    // length at all there's no progress, seeking or times to show (a seek would jump to 0:00)
    TrackTiming { id: timing; player: root.player }
    readonly property bool hasLength: timing.hasLength
    readonly property real progress: hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0
    readonly property bool canShuffle: (player?.shuffleSupported ?? false) && (player?.canControl ?? false)
    readonly property bool canLoop: (player?.loopSupported ?? false) && (player?.canControl ?? false)

    // ── Cover art (downloaded once, shared with the bar: services/CoverArt.qml) ──
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property string displayedArtFilePath: CoverArt.localUrl(artUrl)
    onArtUrlChanged: CoverArt.request(artUrl)
    Component.onCompleted: CoverArt.request(artUrl)


    implicitHeight: content.implicitHeight + 36

    // ── Faint blurred cover glow, clipped to the card ──
    // No layers: the clip is a ClippingRectangle, and the "blur" is the cover decoded at 14px and
    // stretched (smooth scaling makes it soft). Both used to be offscreen layers, the kind of GPU work
    // that hung the Intel iGPU in the drawers
    ClippingRectangle {
        id: glow
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        Image {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize: Qt.size(14, 14)
            smooth: true
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
            opacity: status === Image.Ready ? 0.28 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        Rectangle { // Fade the glow out toward the controls
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Appearance.colors.colLayer0 }
            }
        }
        WaveVisualizer { // Subtle, behind the controls
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 70
            opacity: 0.6
            live: root.isPlaying
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: Appearance.colors.colPrimary
        }
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 14

        // ── Cover + track info ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Item {
                id: cover
                implicitWidth: 92
                implicitHeight: 92
                Rectangle { // Shown until the art loads, or when there is none
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                    MaterialSymbol { anchors.centerIn: parent; text: "music_note"; fill: 1; iconSize: 36; color: Appearance.colors.colPrimary }
                }
                ClippingRectangle {
                    id: coverArt
                    anchors.fill: parent
                    visible: root.displayedArtFilePath !== ""
                    radius: Appearance.rounding.normal
                    color: "transparent"
                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        sourceSize: Qt.size(184, 184)
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Rectangle { // Which player this is
                    Layout.bottomMargin: 4
                    implicitWidth: sourceRow.implicitWidth + 16
                    implicitHeight: 22
                    radius: 8
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
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
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
            }
        }

        // ── Seek bar + times ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Item {
                Layout.fillWidth: true
                implicitHeight: 24
                Loader {
                    anchors.fill: parent
                    active: (root.player?.canSeek ?? false) && root.hasLength
                    sourceComponent: StyledSlider {
                        configuration: StyledSlider.Configuration.Wavy
                        animateWave: root.isPlaying // Still while paused
                        highlightColor: Appearance.colors.colPrimary
                        trackColor: Appearance.m3colors.m3surfaceContainerHighest
                        handleColor: Appearance.colors.colPrimary
                        tooltipContent: StringUtils.friendlyTimeForSeconds(value * timing.length)
                        value: root.progress
                        onMoved: root.player.position = value * timing.length
                    }
                }
                Loader {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    active: !((root.player?.canSeek ?? false) && root.hasLength)
                    sourceComponent: StyledProgressBar {
                        wavy: root.isPlaying
                        highlightColor: Appearance.colors.colPrimary
                        trackColor: Appearance.m3colors.m3surfaceContainerHighest
                        value: root.progress
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                opacity: root.hasLength ? 1 : 0 // Keeps its height so the card doesn't jump
                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(timing.position)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(timing.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Controls ──
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 2
            spacing: 14
            ControlButton { // Shuffle
                small: true
                visible: root.canShuffle
                active: root.player?.shuffle ?? false
                iconName: "shuffle"
                onClicked: root.player.shuffle = !root.player.shuffle
            }
            ControlButton {
                iconName: "skip_previous"
                enabled: root.player?.canGoPrevious ?? false
                onClicked: root.player.previous()
            }
            Rectangle { // Play / pause: a squircle, rounder while paused
                implicitWidth: 60
                implicitHeight: 60
                radius: playMouse.pressed ? 14 : root.isPlaying ? 18 : 24
                color: playMouse.containsMouse ? Qt.lighter(Appearance.colors.colPrimary, 1.06) : Appearance.colors.colPrimary
                Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial } }
                Behavior on color { ColorAnimation { duration: 150 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: 30
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
                iconName: "skip_next"
                enabled: root.player?.canGoNext ?? false
                onClicked: root.player.next()
            }
            ControlButton { // Repeat: off → playlist → track
                small: true
                visible: root.canLoop
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

    component ControlButton: Rectangle {
        id: ctl
        property string iconName
        property bool small: false
        property bool active: false
        signal clicked()
        implicitWidth: small ? 36 : 46
        implicitHeight: implicitWidth
        radius: small ? 12 : 15 // Squircles, like the quick toggles' icons
        opacity: enabled ? 1 : 0.4
        color: active ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
            : small ? (ctlMouse.containsMouse ? Appearance.m3colors.m3surfaceContainerHigh : "transparent")
            : (ctlMouse.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: ctlMouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ctl.iconName
            fill: 1
            iconSize: ctl.small ? 19 : 24
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
