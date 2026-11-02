pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The in-game overlay (Super+Shift+G), like Xbox Game Bar: the game stays in view in the middle, with
 *  - at the top, the clock and battery when the game is fullscreen (the bar is hidden then; in a window it
 *    stays above the overlay), and the quick actions: save a clip, screenshot, crosshair, do not disturb,
 *    game mode (accent when on; a letter each)
 *  - on the left, the game (GameBanner), this session's clips and screenshots (CapturesPanel: one opens in
 *    CaptureViewer, over everything), and what came in while playing (MissedNotifications)
 *  - on the right, live CPU and GPU graphs (PerformancePanel), and the sound (SoundPanel): the game's own
 *    first, matched by process (scripts/clips/game_pids.py: Steam, Lutris, Flatpak or its program) or, for
 *    a Flatpak, its app id, then voice chat
 *  - between them at the bottom, what's playing (NowPlaying)
 * Both columns are the same width (narrower on a small screen). Cards are as tall as what they hold, and the
 * last of each column scrolls when the screen is short.
 * On the overlay layer of the game's screen, with the keyboard: Esc or the key again closes it, as does a
 * click on the backdrop or opening a notification. It fades out with the keyboard and clicks already back with
 * the game. Clip and screenshot close it at once, then capture, so they show the game.
 * Only exists while open. The CPU and GPU are sampled the whole time a game runs, so the graphs and their
 * average and peak cover the session (ResourceUsage reads files, or an nvidia-smi that's already running, and
 * leaves a sleeping NVIDIA GPU asleep).
 * It only opens while a game runs (GameClips' watcher), and closes if the game does. Settings → In game turns it
 * off (gameLauncher.overlayEnabled): the key then does nothing.
 */
Scope {
    id: root
    readonly property bool enabled: Config.options.gameLauncher.overlayEnabled ?? true
    readonly property bool available: enabled && GameClips.game !== "" // Over a game only
    readonly property bool open: available && GlobalStates.gameOverlayOpen
    onAvailableChanged: if (!available) close() // Turned off, or the game closed
    function toggle() { GlobalStates.gameOverlayOpen = root.available && !GlobalStates.gameOverlayOpen; }
    function close() { GlobalStates.gameOverlayOpen = false; }

    // The window exists while open and while it fades out. Its screen is chosen on opening (the game's
    // window's, else the focused one), so it doesn't jump when the pointer crosses to another screen
    property bool loaded: false
    property string screenName: ""
    property bool gameFullscreen: true
    onOpenChanged: {
        if (open) {
            unloadTimer.stop();
            const focused = ToplevelManager.activeToplevel;
            screenName = focused?.screens?.[0]?.name ?? Hyprland.focusedMonitor?.name ?? "";
            gameFullscreen = focused?.fullscreen ?? true;
            loaded = true;
        } else if (loaded) {
            unloadTimer.restart();
        }
    }
    Timer {
        id: unloadTimer
        interval: Appearance.animation.elementMoveFast.duration + 50
        onTriggered: root.loaded = false
    }

    // The launcher's entry for the running game (art, hours, folders), when it has one
    readonly property var game: GameClips.gameId ? GameLauncherService.games.find(g => g.id === GameClips.gameId) ?? null : null
    readonly property string bannerArt: {
        const custom = GameLauncherService.customArt[GameClips.gameId]?.heroArt ?? "";
        for (const p of [custom, game?.heroArt, game?.derivedHeroArt, GameClips.gameArt])
            if (p && p.startsWith("/")) return p;
        return "";
    }

    // ── Capture: the overlay goes at once (no fade), then a frame later the capture, so it shows the game ──
    property string _pendingCapture: ""
    function capture(kind) {
        root._pendingCapture = kind;
        root.close();
        unloadTimer.stop();
        root.loaded = false;
        captureTimer.restart();
    }
    Timer {
        id: captureTimer
        interval: 150
        onTriggered: {
            if (root._pendingCapture === "clip") GameClips.save();
            else if (root._pendingCapture === "screenshot") Quickshell.execDetached([
                Quickshell.shellPath("scripts/game-launcher/game_screenshot.sh"),
                root.screenName || (Hyprland.focusedMonitor?.name ?? ""), GameClips.game || "Game",
                GameClips.gameAppId, root.game?.gameDir ?? "", root.game?.flatpakId ?? ""]);
            root._pendingCapture = "";
        }
    }
    function openFolder(folder) {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "open-folder", folder]);
        root.close();
    }

    // ── CPU and GPU, sampled the whole session: the last 5 minutes for the graphs, average and peak over all of it ──
    readonly property bool sampling: enabled && GameClips.gameStarted > 0
    onSamplingChanged: ResourceUsage.watchers += sampling ? 1 : -1
    Component.onCompleted: if (sampling) ResourceUsage.watchers++
    Component.onDestruction: if (sampling) ResourceUsage.watchers--
    readonly property int historyLength: 100
    property var cpuHistory: []
    property var gpuHistory: []
    property var cpuStats: ({ sum: 0, count: 0, peak: 0 })
    property var gpuStats: ({ sum: 0, count: 0, peak: 0 })
    Connections {
        target: GameClips
        function onGameChanged() {
            root.cpuHistory = []; root.gpuHistory = [];
            root.cpuStats = { sum: 0, count: 0, peak: 0 }; root.gpuStats = { sum: 0, count: 0, peak: 0 };
        }
    }
    Timer {
        // ResourceUsage's first CPU number comes half a second after it starts polling (it's a difference
        // between two reads): the first sample just after that, then at its pace
        running: root.sampling
        repeat: true
        interval: 800
        onRunningChanged: if (running) interval = 800
        onTriggered: {
            interval = Config.options?.resources?.updateInterval ?? 3000;
            root.cpuHistory = root.pushSample(root.cpuHistory, ResourceUsage.cpuUsage);
            root.cpuStats = root.addStat(root.cpuStats, ResourceUsage.cpuUsage);
            if (ResourceUsage.gpuDetected) {
                const gpu = ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuUsage;
                root.gpuHistory = root.pushSample(root.gpuHistory, gpu);
                root.gpuStats = root.addStat(root.gpuStats, gpu);
            }
        }
    }
    function pushSample(list, value) {
        const next = list.concat([Math.min(1, Math.max(0, value))]);
        return next.length > historyLength ? next.slice(next.length - historyLength) : next;
    }
    function addStat(stats, value) {
        return { sum: stats.sum + value, count: stats.count + 1, peak: Math.max(stats.peak, value) };
    }
    function duration(minutes) {
        return minutes < 1 ? Translation.tr("just started")
            : minutes < 60 ? Translation.tr("%1 min").arg(minutes)
            : Translation.tr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60);
    }

    LazyLoader {
        active: root.loaded
        component: PanelWindow {
            id: window
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            // Over a fullscreen game, the whole screen; over a window, below the bar
            exclusionMode: root.gameFullscreen ? ExclusionMode.Ignore : ExclusionMode.Normal
            WlrLayershell.namespace: "quickshell:gameOverlay"
            WlrLayershell.layer: WlrLayer.Overlay
            // Fading out: the keyboard and clicks are the game's again
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: root.open ? null : clickThrough
            Region { id: clickThrough }
            color: "transparent"

            Component.onCompleted: ready = true // Then animates in
            property bool ready: false
            readonly property bool shown: ready && root.open
            property real now: Date.now()
            Timer { running: true; repeat: true; interval: 15000; onTriggered: window.now = Date.now() }
            readonly property int sessionMinutes: GameClips.gameStarted > 0 ? Math.max(0, Math.floor((now - GameClips.gameStarted) / 60000)) : -1

            // ── Loaded on opening ──
            // The game's processes, to tell its sound from other apps'. Without a launcher entry: a Steam game by its id
            readonly property var gameMatchers: root.game ? GameLauncherService.processMatchers(root.game)
                : GameClips.gameAppId !== "" ? ["steam:" + GameClips.gameAppId] : []
            property var gamePids: []
            Process {
                running: window.gameMatchers.length > 0
                command: ["python3", "-I", Quickshell.shellPath("scripts/clips/game_pids.py"), ...window.gameMatchers]
                stdout: StdioCollector {
                    onStreamFinished: { try { window.gamePids = JSON.parse(text); } catch (e) {} }
                }
            }
            // Clips saved since the game started, with thumbnails (made and cached by list_clips.py)
            property var sessionClips: []
            Process {
                running: GameClips.gameStarted > 0
                command: ["python3", "-I", Quickshell.shellPath("scripts/clips/list_clips.py"), GameClips.folderFor(GameClips.game),
                          `${GameLauncherService.cacheDir}/clip-thumbs`]
                stdout: StdioCollector {
                    onStreamFinished: {
                        window.sessionClips = text.split("\n").filter(l => l).map(l => {
                            const f = l.split("\t");
                            return { kind: "clip", time: parseFloat(f[0]) * 1000, duration: parseFloat(f[1]), width: parseInt(f[2]),
                                     height: parseInt(f[3]), thumb: f[5], path: f.slice(6).join("\t") };
                        }).filter(c => c.time >= GameClips.gameStarted);
                    }
                }
            }
            // Screenshots taken since then: Steam's F12 folder and the game's own (find_screenshots.py, as the
            // launcher's gallery), the overlay's among them. Its first line says where they go
            property var sessionShots: []
            property string shotsFolder: ""
            Process {
                running: GameClips.gameStarted > 0
                command: ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/find_screenshots.py"),
                          GameClips.gameAppId, root.game?.gameDir ?? "", root.game?.flatpakId ?? ""]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = text.split("\n").filter(l => l);
                        window.shotsFolder = lines[0]?.startsWith("folder\t") ? lines.shift().slice(7) : "";
                        window.sessionShots = lines.map(l => {
                            const f = l.split("\t");
                            return { kind: "shot", time: parseFloat(f[0]) * 1000, width: parseInt(f[1]), height: parseInt(f[2]),
                                     path: f.slice(3).join("\t") };
                        }).filter(c => c.time >= GameClips.gameStarted);
                    }
                }
            }
            // Both, newest first; the one open in the viewer (-1 for none)
            readonly property var captures: sessionClips.concat(sessionShots).sort((a, b) => b.time - a.time)
            property int viewerIndex: -1
            readonly property bool viewing: viewerIndex >= 0 && viewerIndex < captures.length
            function forget(path) { // Trashed in the viewer: gone from here, the viewer on the next one
                sessionClips = sessionClips.filter(c => c.path !== path);
                sessionShots = sessionShots.filter(c => c.path !== path);
                viewerIndex = captures.length === 0 ? -1 : Math.min(viewerIndex, captures.length - 1);
            }

            Rectangle { // Dims the game; a click here closes
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: window.shown ? 1 : 0
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Item {
                id: layout
                anchors.fill: parent
                anchors.margins: 32
                focus: true
                // Both columns the same width: 400, narrower on a small screen, leaving the middle for the game
                readonly property int columnWidth: Math.round(Math.max(300, Math.min(400, (width - 560) / 2)))
                readonly property real panelsOpacity: window.shown && !window.viewing ? 1 : 0
                Keys.onPressed: event => {
                    if (window.viewing) {
                        if (viewer.handleKey(event)) event.accepted = true;
                        return;
                    }
                    const actions = { [Qt.Key_Escape]: () => root.close(), [Qt.Key_C]: () => clipAction.trigger(),
                        [Qt.Key_S]: () => shotAction.trigger(), [Qt.Key_X]: () => crosshairAction.trigger(),
                        [Qt.Key_D]: () => dndAction.trigger(), [Qt.Key_G]: () => gameModeAction.trigger() };
                    if (actions[event.key] && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                        actions[event.key]();
                        event.accepted = true;
                    }
                }

                // ── Top: the clock and battery (fullscreen only), then the quick actions ──
                ColumnLayout {
                    id: top
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                    anchors.topMargin: window.shown ? 0 : -24
                    opacity: layout.panelsOpacity
                    Behavior on anchors.topMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    spacing: 12

                    OverlayPanel { // What the hidden bar would say
                        visible: root.gameFullscreen
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: statusRow.implicitWidth + 32
                        implicitHeight: 40
                        radius: Appearance.rounding.normal // A rounded rectangle, not a pill
                        RowLayout {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 14
                            StyledText {
                                text: DateTime.time
                                font.family: Appearance.font.family.numbers
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                            Rectangle { // Between the clock and the battery
                                visible: Battery.available
                                implicitWidth: 4; implicitHeight: 4; radius: 2
                                color: Appearance.colors.colSubtext
                            }
                            Row {
                                visible: Battery.available
                                spacing: 4
                                readonly property bool low: !Battery.isPluggedIn && Battery.percent <= 20
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Battery.isPluggedIn ? "battery_charging_full" : parent.low ? "battery_alert" : "battery_full"
                                    iconSize: 18
                                    color: parent.low ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Battery.percent + "%"
                                    font.family: Appearance.font.family.numbers
                                    color: parent.low ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }

                    OverlayPanel {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: actionRow.implicitWidth + 16
                        implicitHeight: actionRow.implicitHeight + 16
                        RowLayout {
                            id: actionRow
                            anchors.centerIn: parent
                            spacing: 8
                            OverlayQuickAction {
                                id: clipAction
                                icon: "movie"; key: "C"
                                text: Translation.tr("Save clip")
                                tip: GameClips.recording ? Translation.tr("The last %1 s").arg(GameClips.seconds)
                                    : GameClips.enabled ? Translation.tr("Records once a game is running") : Translation.tr("Clips are off in Settings → In game")
                                available: GameClips.recording
                                onTriggered: root.capture("clip")
                            }
                            OverlayQuickAction {
                                id: shotAction
                                icon: "screenshot_monitor"; key: "S"
                                text: Translation.tr("Screenshot")
                                tip: Translation.tr("Saved with the game's screenshots")
                                onTriggered: root.capture("screenshot")
                            }
                            OverlayQuickAction {
                                id: crosshairAction
                                icon: "my_location"; key: "X"
                                text: Translation.tr("Crosshair")
                                tip: Translation.tr("Its look is in Settings → Crosshair")
                                active: Crosshair.manual ?? Crosshair.automatic // What it does once the overlay closes
                                onTriggered: Crosshair.toggleOutsideOverlay()
                            }
                            OverlayQuickAction {
                                id: dndAction
                                icon: "notifications_paused"; key: "D"
                                text: Translation.tr("Do not disturb")
                                tip: Translation.tr("No pop-ups. They still wait in the sidebar")
                                active: Notifications.silent
                                onTriggered: Notifications.silent = !Notifications.silent
                            }
                            OverlayQuickAction {
                                id: gameModeAction
                                icon: "speed"; key: "G"
                                text: Translation.tr("Game mode")
                                tip: Translation.tr("No animations, blur or gaps")
                                active: GameModeService.active
                                onTriggered: GameModeService.toggle()
                            }
                        }
                    }
                }

                // ── Left: the game, this session's captures, what came in ──
                SideColumn {
                    id: leftColumn
                    anchors { left: parent.left; top: top.bottom; topMargin: 24; bottom: hint.top; bottomMargin: 16 }
                    anchors.leftMargin: window.shown ? 0 : -40
                    Behavior on anchors.leftMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    width: layout.columnWidth
                    opacity: layout.panelsOpacity
                    GameBanner {
                        id: banner
                        Layout.fillWidth: true
                        art: root.bannerArt
                        gameName: GameClips.game
                        sessionText: window.sessionMinutes < 0 ? ""
                            : Translation.tr("This session: %1").arg(root.duration(window.sessionMinutes))
                              // Steam adds this session to its hours when it ends
                              + (root.game?.playtime ? "  ·  " + Translation.tr("%1 h in all").arg(Math.floor((root.game.playtime + window.sessionMinutes) / 60)) : "")
                    }
                    CapturesPanel {
                        id: capturesPanel
                        Layout.fillWidth: true
                        captures: window.captures
                        clipsFolder: GameClips.folderFor(GameClips.game)
                        shotsFolder: window.shotsFolder
                        recording: GameClips.recording
                        onOpenCapture: index => window.viewerIndex = index
                        onOpenFolder: folder => root.openFolder(folder)
                    }
                    MissedNotifications {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(implicitHeight, leftColumn.height - banner.height - capturesPanel.height - 2 * leftColumn.spacing)
                        since: GameClips.gameStarted
                        onActivated: root.close()
                    }
                }

                // ── Right: how hard the computer is working, and the sound ──
                SideColumn {
                    id: rightColumn
                    anchors { right: parent.right; top: top.bottom; topMargin: 24; bottom: hint.top; bottomMargin: 16 }
                    anchors.rightMargin: window.shown ? 0 : -40
                    Behavior on anchors.rightMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    width: layout.columnWidth
                    opacity: layout.panelsOpacity
                    PerformancePanel {
                        id: performancePanel
                        Layout.fillWidth: true
                        cpuHistory: root.cpuHistory
                        gpuHistory: root.gpuHistory
                        cpuStats: root.cpuStats
                        gpuStats: root.gpuStats
                    }
                    SoundPanel {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(implicitHeight, rightColumn.height - performancePanel.height - rightColumn.spacing)
                        gamePids: window.gamePids
                        gameFlatpak: root.game?.flatpakId ?? ""
                        gameName: GameClips.game
                        gameArt: root.game?.icon || GameClips.gameArt || ""
                    }
                }

                // ── Between them at the bottom: what's playing ──
                NowPlaying {
                    anchors { bottom: hint.top; bottomMargin: 16; horizontalCenter: parent.horizontalCenter }
                    width: Math.min(520, parent.width - 2 * (layout.columnWidth + 24))
                    opacity: layout.panelsOpacity
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }

                CaptureViewer {
                    id: viewer
                    anchors { fill: parent; bottomMargin: 28 }
                    visible: window.viewing
                    captures: window.captures
                    index: window.viewerIndex
                    onGoTo: i => window.viewerIndex = i
                    onBackRequested: window.viewerIndex = -1
                    onTrashed: path => window.forget(path)
                }

                StyledText { // How to leave
                    id: hint
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    opacity: window.shown ? 1 : 0
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    text: window.viewing ? Translation.tr("←/→ to step through · Delete to trash · Esc to go back")
                        : Translation.tr("Esc or Super+Shift+G to go back to the game")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                }
            }
        }
    }

    // A side column: its cards stack from the top, each as tall as what it holds (the last one is given a
    // height that fits what's left)
    component SideColumn: Item {
        default property alias cards: cards.data
        readonly property int spacing: 12
        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        ColumnLayout {
            id: cards
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: parent.spacing
        }
    }

    IpcHandler {
        target: "gameOverlay"
        function toggle(): void { root.toggle(); }
        function open(): void { GlobalStates.gameOverlayOpen = root.available; }
        function close(): void { root.close(); }
    }
    GlobalShortcut {
        name: "gameOverlayToggle"
        description: "Opens or closes the in-game overlay"
        onPressed: root.toggle()
    }
}
