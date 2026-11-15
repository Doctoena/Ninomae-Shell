pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * One player in the media drawer, in the colour of its cover (CoverTint): the picture as a wide banner with the
 * app, the title and the artist on it; joined under it, the seek bar with the times and shuffle / previous /
 * play-pause / next / repeat; then the app's own volume (its PipeWire streams, matched by app name) and Open,
 * which brings the app's window up.
 */
Item {
    id: root
    required property MprisPlayer player
    property real radius: Appearance.rounding.large // The drawer's bottom corners

    readonly property real padding: 10
    readonly property real outer: Math.max(Appearance.rounding.normal, radius - padding) // The pieces' outer corners
    readonly property real inner: Appearance.rounding.joined

    readonly property bool isPlaying: player?.isPlaying ?? false
    // Length and position, kept through the gaps where a browser drops them (TrackTiming.qml). With no
    // length at all there's no progress, seeking or times to show (a seek would jump to 0:00)
    TrackTiming { id: timing; player: root.player }
    readonly property bool hasLength: timing.hasLength
    readonly property real progress: hasLength ? Math.max(0, Math.min(1, timing.position / timing.length)) : 0
    readonly property bool canSeek: (player?.canSeek ?? false) && hasLength
    readonly property bool canShuffle: (player?.shuffleSupported ?? false) && (player?.canControl ?? false)
    readonly property bool canLoop: (player?.loopSupported ?? false) && (player?.canControl ?? false)

    // ── Cover art (fetched by services/CoverArt.qml, shared with the bar and the sidebar) and its colours ──
    readonly property string displayedArtFilePath: CoverArt.coverFor(player)
    CoverTint { id: tint; cover: root.displayedArtFilePath }
    // The colours glide to the next cover's. Each through a hidden Rectangle's own colour: a Behavior on a custom
    // property at this delegate's root crashed quickshell (QQmlData::deferData) whenever the drawer opened
    readonly property color pieceColor: pieceFade.color
    readonly property color buttonColor: buttonFade.color
    readonly property color accent: accentFade.color
    readonly property color onAccent: onAccentFade.color
    readonly property color subtext: subtextFade.color
    ColourFade { id: pieceFade; color: tint.surface(Appearance.colors.colLayer2, 0.2) }
    ColourFade { id: buttonFade; color: tint.surface(Appearance.colors.colLayer4, 0.24) }
    ColourFade { id: accentFade; color: tint.accent }
    ColourFade { id: onAccentFade; color: tint.onAccent }
    ColourFade { id: subtextFade; color: tint.subtext }

    // ── Which app, and the site for a browser ("Zen Browser · YouTube") ──
    readonly property string appName: AppSearch.playerName(player)
    readonly property string site: {
        const url = String(player?.metadata?.["xesam:url"] ?? "");
        return /music\.youtube\.com/.test(url) ? "YouTube Music" : /youtube\.com|youtu\.be/.test(url) ? "YouTube"
            : /soundcloud\.com/.test(url) ? "SoundCloud" : /twitch\.tv/.test(url) ? "Twitch" : "";
    }

    // ── The app's volume: its playing streams, by the same app name the control centre shows. All of them are
    // tracked: a stream's properties (its names) only arrive once it is ──
    readonly property var allStreams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)
    PwObjectTracker { objects: root.allStreams }
    readonly property var streams: allStreams.filter(n => AppSearch.streamAppName(n) === root.appName)
    readonly property bool hasVolume: streams.length > 0
    readonly property real volume: streams[0]?.audio?.volume ?? 0
    readonly property bool muted: streams.length > 0 && streams.every(n => n.audio?.muted ?? false)
    // Open: the player raises itself if it can, else its window (by the same app name) is brought up
    readonly property var appWindow: ToplevelManager.toplevels.values.find(w => AppSearch.appName([w.appId]) === root.appName) ?? null
    readonly property bool canOpen: (player?.canRaise ?? false) || appWindow !== null
    function open() {
        if (player?.canRaise) player.raise();
        else appWindow?.activate();
        GlobalStates.mediaControlsOpen = false;
    }

    implicitHeight: column.implicitHeight + padding

    // ── Title and artist: on a new track the pair fades out sliding left, changes, and fades back in. As one
    // block: StyledText's own change animation slides each line back to where it was first made, which in a
    // layout is the top (the artist landed on the title) ──
    readonly property string liveTitle: StringUtils.cleanMusicTitle(player?.trackTitle, player?.trackArtist) || Translation.tr("Untitled")
    readonly property string liveArtist: player?.trackArtist ?? ""
    property string shownTitle: liveTitle
    property string shownArtist: liveArtist
    onLiveTitleChanged: titleSwap.restart()
    onLiveArtistChanged: titleSwap.restart()
    SequentialAnimation {
        id: titleSwap
        ParallelAnimation {
            NumberAnimation { target: titleBlock; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InCubic }
            NumberAnimation { target: titleShift; property: "x"; to: -6; duration: 120; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                root.shownTitle = root.liveTitle;
                root.shownArtist = root.liveArtist;
                titleShift.x = 6;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: titleBlock; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: titleShift; property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.padding; rightMargin: root.padding; topMargin: 4 }
        spacing: 4

        // ── The picture, wide, with the app, title and artist on it ──
        ClippingRectangle {
            id: banner
            Layout.fillWidth: true
            implicitHeight: Math.round(width * 9 / 16)
            topLeftRadius: root.outer; topRightRadius: root.outer
            bottomLeftRadius: root.inner; bottomRightRadius: root.inner
            color: root.pieceColor
            MaterialSymbol { // No art (yet)
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
                visible: cover.status !== Image.Ready && oldCover.status !== Image.Ready
                text: "music_note"; fill: 1; iconSize: 56
                color: root.accent
            }
            // Fills the banner, whatever its shape (a square album cover loses its top and bottom). Two covers
            // crossfade on a new track: the new one fades in over the old, which then lets its picture go
            Image {
                id: oldCover
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                sourceSize: cover.sourceSize
            }
            StyledImage {
                id: cover
                anchors.fill: parent
                source: root.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                retainWhileLoading: false // Empty until the new one's ready, so it can fade in over the old
                sourceSize: Qt.size(Math.round(banner.width * 2), Math.round(banner.height * 2))
                property string lastSource: ""
                onSourceChanged: {
                    oldCover.source = lastSource;
                    lastSource = source;
                }
                onStatusChanged: if (status === Image.Ready) oldCoverRelease.restart()
                Timer { id: oldCoverRelease; interval: 700; onTriggered: oldCover.source = "" }
            }
            Rectangle { // A shade up from the bottom for the title
                id: titleShade
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * 0.62
                // Dark (the drawer's own colour, a touch of the cover's): a light picture under a tinted shade
                // went a muddy lilac
                readonly property color shade: tint.surface(Appearance.colors.colLayer0, 0.12)
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: ColorUtils.transparentize(titleShade.shade, 0.45) }
                    GradientStop { position: 1; color: ColorUtils.transparentize(titleShade.shade, 0.08) }
                }
            }
            Rectangle { // The app (and site), top left
                x: 12; y: 12
                implicitWidth: sourceRow.implicitWidth + 16
                implicitHeight: 24
                radius: Appearance.rounding.chip
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.18)
                Row {
                    id: sourceRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        id: sourceSymbol
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isPlaying ? "graphic_eq" : "pause_circle"
                        fill: 1; iconSize: 13; color: root.accent
                    // A new symbol (play ↔ pause) springs in from half size. A handler, not a Behavior on text:
                    // StyledText already has one of those
                    onTextChanged: sourceSymbolPop.restart()
                    NumberAnimation on scale { id: sourceSymbolPop; running: false; from: 0.5; to: 1; duration: 280; easing.type: Easing.OutBack }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: [root.appName || Translation.tr("Player"), root.site].filter(s => s).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
            ColumnLayout {
                id: titleBlock
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 12 }
                spacing: 0
                transform: Translate { id: titleShift }
                StyledText {
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.title
                    font.pixelSize: 22
                    font.weight: Font.Black
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: root.shownTitle
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.subtext
                    elide: Text.ElideRight
                    visible: text.length > 0
                    text: root.shownArtist
                }
            }
        }

        // ── Seek bar, then the times either side of the controls ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: seekColumn.implicitHeight + 20
            topLeftRadius: root.inner; topRightRadius: root.inner
            bottomLeftRadius: volumePiece.visible ? root.inner : root.outer; bottomRightRadius: bottomLeftRadius
            color: root.pieceColor
            ColumnLayout {
                id: seekColumn
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                spacing: 4
                SlimSlider {
                    Layout.fillWidth: true
                    ringColor: root.pieceColor
                    accentColor: root.accent
                    enabled: root.canSeek
                    wheelEnabled: false // A stray scroll shouldn't jump the track
                    opacity: root.hasLength ? 1 : 0.4
                    level: root.progress
                    onMoved: if (root.canSeek) root.player.position = value * timing.length
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: controls.implicitHeight
                    TimeText { // Keeps its place with no length, so the controls don't move
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        opacity: root.hasLength ? 1 : 0
                        text: StringUtils.friendlyTimeForSeconds(timing.position)
                    }
                    RowLayout {
                        id: controls
                        anchors.centerIn: parent
                        spacing: 6
                        ControlButton { // Shuffle: always there, dimmed for players that can't (browsers)
                            flat: true
                            enabled: root.canShuffle
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
                            implicitWidth: 50
                            implicitHeight: 50
                            radius: playMouse.pressed ? 12 : root.isPlaying ? 15 : 20
                            color: playMouse.containsMouse ? Qt.lighter(root.accent, 1.06) : root.accent
                            Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            MaterialSymbol {
                                id: playSymbol
                                anchors.centerIn: parent
                                text: root.isPlaying ? "pause" : "play_arrow"
                                fill: 1
                                iconSize: 26
                                color: root.onAccent
                                // A new symbol (play ↔ pause) springs in from half size. A handler, not a Behavior on text:
                                // StyledText already has one of those
                                onTextChanged: playSymbolPop.restart()
                                NumberAnimation on scale { id: playSymbolPop; running: false; from: 0.5; to: 1; duration: 280; easing.type: Easing.OutBack }
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
                        ControlButton { // Repeat: off → playlist → track. Always there, dimmed for players that can't
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
                    TimeText {
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        opacity: root.hasLength ? 1 : 0
                        text: StringUtils.friendlyTimeForSeconds(timing.length)
                    }
                }
            }
        }

        // ── The app's volume, and Open ──
        Rectangle {
            id: volumePiece
            Layout.fillWidth: true
            visible: root.hasVolume || root.canOpen
            implicitHeight: 50
            topLeftRadius: root.inner; topRightRadius: root.inner
            bottomLeftRadius: root.outer; bottomRightRadius: root.outer
            color: root.pieceColor
            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 10 }
                spacing: 6
                ControlButton { // Mute
                    visible: root.hasVolume
                    flat: true
                    size: 32
                    iconName: root.muted || root.volume === 0 ? "volume_off" : root.volume < 0.5 ? "volume_down" : "volume_up"
                    onClicked: {
                        const mute = !root.muted;
                        root.streams.forEach(n => { if (n.audio) n.audio.muted = mute; });
                    }
                }
                SlimSlider {
                    Layout.fillWidth: true
                    visible: root.hasVolume
                    ringColor: root.pieceColor
                    accentColor: root.accent
                    opacity: root.muted ? 0.5 : 1
                    level: root.volume
                    onMoved: root.streams.forEach(n => { if (n.audio) n.audio.volume = value; })
                }
                StyledText {
                    visible: root.hasVolume
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.volume * 100)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.subtext
                }
                Item { Layout.fillWidth: true; visible: !root.hasVolume }
                Rectangle { // Open: the app's window
                    visible: root.canOpen
                    Layout.leftMargin: 4
                    implicitWidth: openRow.implicitWidth + 18
                    implicitHeight: 30
                    radius: Appearance.rounding.chip
                    color: openMouse.containsMouse ? Qt.lighter(root.buttonColor, 1.15) : root.buttonColor
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Row {
                        id: openRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "open_in_new"; iconSize: 15; color: root.accent }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Open")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.open()
                    }
                }
            }
        }
    }

    // A colour that glides to its next value (the cover's colours on a new track)
    component ColourFade: Rectangle {
        visible: false
        Behavior on color { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }
    }

    component TimeText: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.numbers
        font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
        color: root.subtext
    }

    // A squircle control in the cover's colours; `flat` ones (shuffle, repeat, mute) have no card until pointed
    // at, `active` ones show in the accent
    component ControlButton: Rectangle {
        id: ctl
        property string iconName
        property real size: 40
        property bool flat: false
        property bool active: false
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 3 // Squircles, like the quick toggles' icons
        opacity: enabled ? 1 : 0.4
        color: active ? ColorUtils.transparentize(root.accent, 0.8)
            : flat ? (ctlMouse.containsMouse ? root.buttonColor : "transparent")
            : (ctlMouse.containsMouse ? Qt.lighter(root.buttonColor, 1.15) : root.buttonColor)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: ctlMouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ctl.iconName
            fill: 1
            iconSize: Math.round(ctl.size * 0.5)
            color: ctl.active ? root.accent : Appearance.colors.colOnLayer0
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
