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
 * One player in the media drawer (G1b), in a well on the drawer's glass, lit by its cover (CoverTint): the picture
 * runs to the well's edges at the top and fades into it, the app, the title and the artist on the fade; then straight
 * on the well the seek bar with the times on its line, shuffle / previous / play-pause / next / repeat, and the app's
 * own volume (its PipeWire streams, matched by app name) with Open, which brings the app's window up.
 */
Item {
    id: root
    required property MprisPlayer player
    property real radius: Appearance.rounding.large // The drawer's bottom corners

    readonly property real padding: 10
    readonly property real outer: Math.max(Appearance.rounding.normal, radius - padding) // The well's corners
    // What the well looks like over the drawer's glass, for the picture to fade into and the sliders' rings
    readonly property color wellColor: ColorUtils.mix(Appearance.m3colors.m3background, Appearance.colors.colLayer0, 0.6)

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
    readonly property color pieceColor: pieceFade.color // Behind the picture while there's none
    readonly property color accent: accentFade.color
    readonly property color onAccent: onAccentFade.color
    readonly property color subtext: subtextFade.color
    ColourFade { id: pieceFade; color: tint.surface(Appearance.colors.colLayer2, 0.2) }
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

    implicitHeight: column.implicitHeight + 4 + padding

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

    GlassWell {
        anchors { fill: column; margins: 0 }
        radius: root.outer
    }
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.padding; rightMargin: root.padding; topMargin: 4 }
        spacing: 0

        // ── The picture, to the well's edges at the top, fading into it; the app, title and artist on the fade ──
        ClippingRectangle {
            id: banner
            Layout.fillWidth: true
            Layout.margins: 1 // Inside the well's rim
            implicitHeight: Math.round(width * 9 / 16) + 20
            topLeftRadius: root.outer - 1; topRightRadius: root.outer - 1
            color: root.pieceColor
            MaterialSymbol { // No art (yet)
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -30
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
                // Fixed: the banner's width only changes with the drawer's (a size bound to it would re-decode)
                sourceSize: Qt.size(880, 880)
                property string lastSource: ""
                onSourceChanged: {
                    oldCover.source = lastSource;
                    lastSource = source;
                }
                onStatusChanged: if (status === Image.Ready) oldCoverRelease.restart()
                Timer { id: oldCoverRelease; interval: 700; onTriggered: oldCover.source = "" }
            }
            Rectangle { // The fade into the well, the title on it
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * 0.7
                gradient: Gradient {
                    GradientStop { position: 0; color: ColorUtils.transparentize(root.wellColor, 1) }
                    GradientStop { position: 0.7; color: ColorUtils.transparentize(root.wellColor, 0.1) }
                    GradientStop { position: 1; color: root.wellColor }
                }
            }
            ColumnLayout {
                id: titleBlock
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 15; rightMargin: 15; bottomMargin: 2 }
                spacing: 0
                transform: Translate { id: titleShift }
                Row { // The app (and site), its squircle saying whether it's playing
                    Layout.bottomMargin: 4
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 6.5
                        color: ColorUtils.transparentize("white", 0.88)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.isPlaying ? "graphic_eq" : "pause"
                            fill: 1; iconSize: 13; color: root.accent
                            // A new symbol (play ↔ pause) springs in from half size. A handler, not a Behavior on
                            // text: StyledText already has one of those
                            onTextChanged: sourceSymbolPop.restart()
                            NumberAnimation on scale { id: sourceSymbolPop; running: false; from: 0.5; to: 1; duration: 280; easing.type: Easing.OutBack }
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: [root.appName || Translation.tr("Player"), root.site].filter(s => s).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtextGlass
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.title
                    font.pixelSize: 26
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

        // ── Straight on the well: the seek bar with the times on its line, the controls, the volume and Open ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 6; Layout.bottomMargin: 10
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TimeText { // Keeps its place with no length, so the bar doesn't move
                    opacity: root.hasLength ? 1 : 0
                    text: StringUtils.friendlyTimeForSeconds(timing.position)
                }
                SlimSlider {
                    Layout.fillWidth: true
                    ringColor: root.wellColor
                    accentColor: root.accent
                    enabled: root.canSeek
                    wheelEnabled: false // A stray scroll shouldn't jump the track
                    opacity: root.hasLength ? 1 : 0.4
                    level: root.progress
                    onMoved: if (root.canSeek) root.player.position = value * timing.length
                }
                TimeText {
                    opacity: root.hasLength ? 1 : 0
                    text: StringUtils.friendlyTimeForSeconds(timing.length)
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -2
                spacing: 8
                ControlButton { // Shuffle: always there, dimmed for players that can't (browsers)
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
                Item { // Play / pause: the accent squircle with a soft glow, rounder while paused
                    implicitWidth: 50
                    implicitHeight: 50
                    Rectangle { // The glow, following the squircle's shape
                        anchors { fill: playButton; margins: -3 }
                        radius: playButton.radius + 3
                        color: ColorUtils.transparentize(root.accent, 0.8)
                    }
                    Rectangle {
                        id: playButton
                        anchors.fill: parent
                        radius: playMouse.pressed ? 12 : root.isPlaying ? 15 : 20
                        color: playMouse.containsMouse ? Qt.lighter(root.accent, 1.06) : root.accent
                        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle { // A light along its top
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.radius; rightMargin: parent.radius }
                            height: 1
                            color: ColorUtils.transparentize("white", 0.4)
                        }
                        MaterialSymbol {
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
                }
                ControlButton {
                    iconName: "skip_next"
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player.next()
                }
                ControlButton { // Repeat: off → playlist → track. Always there, dimmed for players that can't
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
            RowLayout { // The app's volume, and Open
                Layout.fillWidth: true
                visible: root.hasVolume || root.canOpen
                spacing: 8
                ControlButton { // Mute
                    visible: root.hasVolume
                    size: 30
                    iconName: root.muted || root.volume === 0 ? "volume_off" : root.volume < 0.5 ? "volume_down" : "volume_up"
                    iconColor: Appearance.colors.colSubtextGlass
                    onClicked: {
                        const mute = !root.muted;
                        root.streams.forEach(n => { if (n.audio) n.audio.muted = mute; });
                    }
                }
                SlimSlider {
                    Layout.fillWidth: true
                    visible: root.hasVolume
                    ringColor: root.wellColor
                    accentColor: root.accent
                    opacity: root.muted ? 0.5 : 1
                    level: root.volume
                    onMoved: root.streams.forEach(n => { if (n.audio) n.audio.volume = value; })
                }
                TimeText {
                    visible: root.hasVolume
                    Layout.preferredWidth: 24
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.volume * 100)
                }
                Item { Layout.fillWidth: true; visible: !root.hasVolume }
                Rectangle { // A dot between the volume and Open, as the bar's parts
                    visible: root.hasVolume && root.canOpen
                    implicitWidth: 3; implicitHeight: 3; radius: 1.5
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.6)
                }
                Rectangle { // Open: the app's window. Quiet, a soft card when pointed at
                    visible: root.canOpen
                    implicitWidth: openRow.implicitWidth + 16
                    implicitHeight: 30
                    radius: 10
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, openMouse.containsMouse ? 0.92 : 1)
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

    // A squircle control straight on the well: a soft card when pointed at, `active` ones (shuffle, repeat on) in
    // the accent
    component ControlButton: Rectangle {
        id: ctl
        property string iconName
        property real size: 40
        property bool active: false
        property color iconColor: Appearance.colors.colOnLayer0
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 3 // Squircles, like the quick toggles' icons
        opacity: enabled ? 1 : 0.4
        color: active ? ColorUtils.transparentize(root.accent, 0.8)
            : ColorUtils.transparentize(Appearance.colors.colOnLayer0, ctlMouse.containsMouse ? 0.92 : 1)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: ctlMouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ctl.iconName
            fill: 1
            iconSize: Math.round(ctl.size * 0.5)
            color: ctl.active ? root.accent : ctl.iconColor
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
