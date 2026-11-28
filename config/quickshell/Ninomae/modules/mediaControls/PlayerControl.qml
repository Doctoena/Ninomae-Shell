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
 * One player in the media drawer (E4c), a card filled with its cover's own colours (the cover decoded tiny and
 * stretched, as the game page's frost: no blur shader), dimmed and fading down into the drawer. Centred on it: the
 * cover, a 212 px rounded square with a soft shadow and a fine rim; the title, bold, and the artist in the cover's colour
 * (CoverTint); the seek bar with the time gone and the time left under its ends; the controls in a lit capsule (the
 * bar's), ranked: shuffle and repeat small and quiet, previous and next bigger, play / pause the big lit squircle; the
 * app's own volume (its PipeWire streams, matched by app name); the app and Open, which brings its window up, along
 * the foot.
 */
Item {
    id: root
    required property MprisPlayer player
    property real radius: Appearance.rounding.large // The drawer's bottom corners

    readonly property real padding: 10
    readonly property real outer: Math.max(Appearance.rounding.normal, radius - padding) // The card's corners
    readonly property real coverSize: 212
    // The card's colour under the sliders' knobs (they sit on a ring of it)
    readonly property color cardColor: ColorUtils.mix(Appearance.m3colors.m3background, Appearance.colors.colLayer0, 0.6)

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
    readonly property bool hasArt: cover.status === Image.Ready || oldCover.status === Image.Ready
    CoverTint { id: tint; cover: root.displayedArtFilePath }
    // The colours glide to the next cover's. Each through a hidden Rectangle's own colour: a Behavior on a custom
    // property at this delegate's root crashed quickshell (QQmlData::deferData) whenever the drawer opened
    readonly property color pieceColor: pieceFade.color // The card while there's no picture
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

    implicitHeight: card.height + 4 + padding

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

    // ── The card: the cover's own colours, dimmed, fading down into the drawer ──
    ClippingRectangle {
        id: card
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.padding; rightMargin: root.padding; topMargin: 4 }
        height: column.implicitHeight + 32
        radius: root.outer
        color: root.pieceColor
        Image { // The cover decoded tiny and stretched: its colours, softly blurred
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize: Qt.size(16, 16)
            fillMode: Image.Stretch
            smooth: true
            opacity: status === Image.Ready ? 0.85 : 0
            Behavior on opacity { NumberAnimation { duration: 450 } }
        }
        Rectangle { // Dimmed, so white text reads on any cover
            anchors.fill: parent
            color: Qt.rgba(0.04, 0.03, 0.08, 0.45)
        }
        Rectangle { // Fading down into the drawer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height - 160
            gradient: Gradient {
                GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 1) }
                GradientStop { position: 1; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4) }
            }
        }
    }
    Rectangle { // The card's fine rim
        anchors.fill: card
        radius: card.radius
        color: "transparent"
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.1) }
    }

    ColumnLayout {
        id: column
        anchors { left: card.left; right: card.right; top: card.top; topMargin: 18 }
        spacing: 0

        // ── The cover: a rounded square, a soft shadow under it, a fine rim; dimmed while paused ──
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.coverSize
            implicitHeight: root.coverSize
            Repeater { // The shadow
                model: [[12, 0.05], [8, 0.08], [4, 0.12]]
                Rectangle {
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6 - modelData[0] / 2
                    width: root.coverSize + modelData[0]
                    height: root.coverSize + modelData[0]
                    radius: 20 + modelData[0] / 2
                    color: Qt.rgba(0, 0, 0, modelData[1])
                }
            }
            ClippingRectangle {
                anchors.fill: parent
                radius: 20
                color: root.pieceColor
                MaterialSymbol { // No art (yet)
                    anchors.centerIn: parent
                    visible: !root.hasArt
                    text: "music_note"; fill: 1; iconSize: 56
                    color: root.accent
                }
                // Two covers crossfade on a new track: the new one fades in over the old, which then lets its
                // picture go
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
                    sourceSize: Qt.size(root.coverSize * 2, root.coverSize * 2) // Fixed: never re-decoded
                    property string lastSource: ""
                    onSourceChanged: {
                        oldCover.source = lastSource;
                        lastSource = source;
                    }
                    onStatusChanged: if (status === Image.Ready) oldCoverRelease.restart()
                    Timer { id: oldCoverRelease; interval: 700; onTriggered: oldCover.source = "" }
                }
                Rectangle { // Paused: dimmed
                    anchors.fill: parent
                    color: "black"
                    opacity: root.isPlaying ? 0 : 0.35
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }
            }
            Rectangle { // The rim
                anchors.fill: parent
                radius: 20
                color: "transparent"
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
            }
        }

        // ── The title, bold, and the artist in the cover's colour ──
        ColumnLayout {
            id: titleBlock
            Layout.fillWidth: true
            Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.topMargin: 14
            spacing: 1
            transform: Translate { id: titleShift }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 23
                font.weight: Font.Bold
                font.variableAxes: ({}) // Not the main font's weight axis: it won over font.weight
                color: "white"
                elide: Text.ElideRight
                text: root.shownTitle
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                font.variableAxes: ({})
                color: root.accent
                elide: Text.ElideRight
                visible: text.length > 0
                text: root.shownArtist
            }
        }

        // ── The seek bar, the time gone and the time left under its ends ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.topMargin: 8
            spacing: -5
            SlimSlider {
                Layout.fillWidth: true
                ringColor: root.cardColor
                accentColor: root.accent
                enabled: root.canSeek
                wheelEnabled: false // A stray scroll shouldn't jump the track
                opacity: root.hasLength ? 1 : 0.4
                level: root.progress
                onMoved: if (root.canSeek) root.player.position = value * timing.length
            }
            RowLayout { // Keep their place with no length, so nothing moves
                Layout.fillWidth: true
                Layout.leftMargin: 4; Layout.rightMargin: 4
                opacity: root.hasLength ? 1 : 0
                TimeText { text: StringUtils.friendlyTimeForSeconds(timing.position) }
                Item { Layout.fillWidth: true }
                TimeText { text: "-" + StringUtils.friendlyTimeForSeconds(Math.max(0, timing.length - timing.position)) }
            }
        }

        // ── The controls, ranked, in a lit capsule ──
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            implicitWidth: controls.implicitWidth + 22
            implicitHeight: controls.implicitHeight + 12
            Rectangle { // The capsule: the cover's colour, strongest in its middle, a fine rim of it
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border { width: 1; color: ColorUtils.transparentize(root.accent, 0.78) }
                Rectangle {
                    anchors { fill: parent; margins: 1 }
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: ColorUtils.transparentize(root.accent, 0.93) }
                        GradientStop { position: 0.5; color: ColorUtils.transparentize(root.accent, 0.84) }
                        GradientStop { position: 1; color: ColorUtils.transparentize(root.accent, 0.93) }
                    }
                }
            }
            RowLayout {
                id: controls
                anchors.centerIn: parent
                spacing: 10
                ControlButton { // Shuffle: always there, dimmed for players that can't (browsers)
                    quiet: true
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
                Item { // Play / pause: the lit squircle with a soft glow, rounder while paused
                    implicitWidth: 52
                    implicitHeight: 52
                    Rectangle { // The glow, two steps out
                        anchors { fill: playButton; margins: -7 }
                        radius: playButton.radius + 5
                        color: ColorUtils.transparentize(root.accent, 0.88)
                    }
                    Rectangle {
                        anchors { fill: playButton; margins: -4 }
                        radius: playButton.radius + 2
                        color: ColorUtils.transparentize(root.accent, 0.8)
                    }
                    Rectangle {
                        id: playButton
                        anchors.fill: parent
                        radius: playMouse.pressed ? 12 : root.isPlaying ? 17 : 22
                        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial } }
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(root.accent, playMouse.containsMouse ? 1.1 : 1.06) }
                            GradientStop { position: 1; color: Qt.darker(root.accent, 1.08) }
                        }
                        Rectangle { // A light along its top
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.width * 0.26; rightMargin: parent.width * 0.26; topMargin: 1 }
                            height: 1
                            color: ColorUtils.transparentize("white", 0.3)
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.isPlaying ? "pause" : "play_arrow"
                            fill: 1
                            iconSize: 27
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
                    quiet: true
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

        // ── The app's volume (the speaker mutes it) ──
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            visible: root.hasVolume
            spacing: 6
            ControlButton {
                quiet: true
                size: 30
                iconName: root.muted || root.volume === 0 ? "volume_off" : "volume_down"
                onClicked: {
                    const mute = !root.muted;
                    root.streams.forEach(n => { if (n.audio) n.audio.muted = mute; });
                }
            }
            SlimSlider {
                Layout.preferredWidth: 220
                ringColor: root.cardColor
                accentColor: ColorUtils.transparentize("white", 0.2)
                opacity: root.muted ? 0.5 : 1
                level: root.volume
                onMoved: root.streams.forEach(n => { if (n.audio) n.audio.volume = value; })
            }
            MaterialSymbol {
                text: "volume_up"
                iconSize: 16
                color: root.subtext
            }
        }

        // ── Along the foot, on a hairline: the app (its squircle saying whether it's playing) and Open ──
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 12
            implicitHeight: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10; Layout.rightMargin: 6; Layout.topMargin: 6
            spacing: 7
            Rectangle {
                implicitWidth: 20; implicitHeight: 20; radius: 7
                color: ColorUtils.transparentize(root.accent, 0.8)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "graphic_eq" : "pause"
                    fill: 1; iconSize: 13; color: root.accent
                    // A new symbol (play ↔ pause) springs in from half size
                    onTextChanged: sourceSymbolPop.restart()
                    NumberAnimation on scale { id: sourceSymbolPop; running: false; from: 0.5; to: 1; duration: 280; easing.type: Easing.OutBack }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: [root.appName || Translation.tr("Player"), root.site].filter(s => s).join(" · ")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.subtext
                elide: Text.ElideRight
            }
            Rectangle { // Open: the app's window. A glass chip, a shade more when pointed at
                visible: root.canOpen
                implicitWidth: openRow.implicitWidth + 18
                implicitHeight: 30
                radius: 15
                color: Qt.rgba(1, 1, 1, openMouse.containsMouse ? 0.12 : 0.07)
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                Behavior on color { ColorAnimation { duration: 150 } }
                Row {
                    id: openRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "open_in_new"; iconSize: 14; color: root.accent }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Open")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "white"
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

    // A control in the capsule: previous / next big and white, `quiet` ones (shuffle, repeat, mute) small and dim
    // until they're on (`active`, in the accent). A soft circle when pointed at
    component ControlButton: Rectangle {
        id: ctl
        property string iconName
        property bool quiet: false
        property real size: quiet ? 30 : 38
        property bool active: false
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        opacity: enabled ? 1 : 0.35
        color: active ? ColorUtils.transparentize(root.accent, 0.8)
            : ColorUtils.transparentize("white", ctlMouse.containsMouse ? 0.9 : 1)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: ctlMouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ctl.iconName
            fill: 1
            iconSize: Math.round(ctl.size * (ctl.quiet ? 0.56 : 0.66))
            color: ctl.active ? root.accent : "white"
            opacity: ctl.active || !ctl.quiet || ctlMouse.containsMouse ? 1 : 0.55
            Behavior on opacity { NumberAnimation { duration: 150 } }
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
