pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The in-game overlay (Super+Shift+G): one panel down the left, as tall as it needs, the game still in view
 * beside it. In the panel, joined cards like the sidebar's:
 *  - the game (GameBanner: its art, the frame rate when MangoHud gives one, and the clock and battery in its
 *    corner when the game is fullscreen: the bar is hidden then, in a window it stays above the overlay), and
 *    the quick actions in a strip under it: save a clip, screenshot, crosshair, do not disturb, game mode
 *    (accent when on, a key each)
 *  - CPU and GPU (PerformancePanel), and the sound (SoundPanel): the game's own first, matched by process
 *    (game_perf.py, with game_pids.py: Steam, Lutris, Flatpak or its program) or, for a Flatpak, its app id, then
 *    voice chat, then the mic
 *  - at its foot, what's playing (NowPlaying) and how to leave
 * The cards scroll when the screen is short. What happened this session is apart, in a column down the right,
 * as it can add up fast: the clips and screenshots (CapturesPanel: one opens in CaptureViewer, over everything),
 * and under them what came in while playing (MissedNotifications), only when something did.
 * On the overlay layer of the game's screen, with the keyboard: Esc or the key again closes it, as does a
 * click on the backdrop or opening a notification. It fades out with the keyboard and clicks already back with
 * the game. Clip and screenshot close it at once, then capture, so they show the game.
 * Only exists while open. The CPU and GPU are sampled the whole time a game runs, so the graphs and their
 * average and peak cover the session (ResourceUsage reads files, or an nvidia-smi that's already running, and
 * leaves a sleeping NVIDIA GPU asleep). So is scripts/clips/game_perf.py, for the GPU the game draws on (on a
 * laptop's integrated one, that one's graph, and a warning when there's a faster one) and its frame rate, from
 * MangoHud's log when it runs with MangoHud.
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
    readonly property var game: GameClips.gameId ? GameLauncherService.gamesById[GameClips.gameId] ?? null : null
    readonly property string bannerArt: {
        const custom = GameLauncherService.customArt[GameClips.gameId]?.heroArt ?? "";
        for (const p of [custom, game?.heroArt, game?.derivedHeroArt, GameClips.gameArt])
            if (p && p.startsWith("/")) return p;
        return "";
    }

    // ── Capture: the overlay goes at once (no fade), then a frame later the capture, so it shows the game ──
    property string _pendingCapture: ""
    property var _captureGame: null // The game as it was on the click: it may have quit by the time the capture's taken
    function capture(kind) {
        root._pendingCapture = kind;
        root._captureGame = { name: GameClips.game, appid: GameClips.gameAppId, dir: root.game?.gameDir ?? "", flatpak: root.game?.flatpakId ?? "" };
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
                root.screenName || (Hyprland.focusedMonitor?.name ?? ""), root._captureGame.name || "Game",
                root._captureGame.appid, root._captureGame.dir, root._captureGame.flatpak]);
            root._pendingCapture = "";
        }
    }
    function openFolder(folder) {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "open-folder", folder]);
        root.close();
    }

    // ── Watched the whole session: the CPU, GPU and frame rate, the last 5 minutes for the graphs, average and
    // peak over all of it ──
    readonly property bool sampling: enabled && GameClips.gameStarted > 0
    // How to find the game's processes. Without a launcher entry: a Steam game by its id
    readonly property var gameMatchers: game ? GameLauncherService.processMatchers(game)
        : GameClips.gameAppId !== "" ? ["steam:" + GameClips.gameAppId] : []
    // The game's processes, the GPU it draws on and its frame rate (game_perf.py):
    // { pids, icon, gpu, integrated, busy, fps, fpsAvg, fpsLow }
    // Where MangoHud.conf (matugen's template) and the launcher's MangoHud presets write the frame-rate log
    readonly property string mangohudLogs: FileUtils.trimFileProtocol(`${Directories.cache}/mangohud`)
    property var perf: ({})
    property var gamePids: [] // Kept apart, and only replaced when they change, so Sound doesn't regroup every 2 s
    readonly property bool onIntegrated: (perf.gpu ?? "") !== "" && (perf.integrated ?? false)
    Process {
        running: root.sampling
        command: ["python3", "-I", Quickshell.shellPath("scripts/clips/game_perf.py"), root.mangohudLogs,
                  String(GameClips.gameStarted / 1000), ...root.gameMatchers]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.perf = JSON.parse(line);
                    if (JSON.stringify(root.perf.pids) !== JSON.stringify(root.gamePids)) root.gamePids = root.perf.pids;
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) { root.perf = {}; root.gamePids = []; }
    }
    onSamplingChanged: ResourceUsage.watchers += sampling ? 1 : -1
    Component.onCompleted: {
        if (sampling) ResourceUsage.watchers++;
        Quickshell.execDetached(["mkdir", "-p", mangohudLogs]); // MangoHud doesn't make its log folder
    }
    Component.onDestruction: if (sampling) ResourceUsage.watchers--
    readonly property int historyLength: 100
    property var cpuHistory: []
    property var gpuHistory: []
    property var fpsHistory: []
    property var cpuStats: ({ sum: 0, count: 0, peak: 0 })
    property var gpuStats: ({ sum: 0, count: 0, peak: 0 })
    Connections {
        target: GameClips
        function onGameChanged() {
            root.cpuHistory = []; root.gpuHistory = []; root.fpsHistory = [];
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
            if (root.onIntegrated || ResourceUsage.gpuDetected) {
                // On an integrated GPU, the game's share of it; else the GPU ResourceUsage reads
                const gpu = root.onIntegrated ? Math.max(0, root.perf.busy) : ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuUsage;
                root.gpuHistory = root.pushSample(root.gpuHistory, gpu);
                root.gpuStats = root.addStat(root.gpuStats, gpu);
            }
            if ((root.perf.fps ?? -1) > 0) root.fpsHistory = root.pushSample(root.fpsHistory, root.perf.fps, Infinity);
        }
    }
    function pushSample(list, value, max = 1) {
        const next = list.concat([Math.min(max, Math.max(0, value))]);
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
            // Screenshots taken since then: the shell's (F12, the overlay's) and the game's own (find_screenshots.py,
            // as the launcher's gallery). Its first line says where they go
            property var sessionShots: []
            property string shotsFolder: ""
            Process {
                running: GameClips.gameStarted > 0
                command: ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/find_screenshots.py"),
                          GameClips.gameAppId, root.game?.gameDir ?? "", root.game?.flatpakId ?? "", GameClips.game]
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

            Rectangle { // Dims the game, more behind the panels at its sides than in the middle; a click here closes
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.7) }
                    GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
                }
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
                anchors.margins: 16
                focus: true
                readonly property real panelOpacity: window.shown && !window.viewing ? 1 : 0
                Keys.onPressed: event => {
                    if (window.viewing) {
                        if (viewer.handleKey(event)) event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape && soundPanel.outputMenuOpen) { // The menu first
                        soundPanel.outputMenuOpen = false;
                        event.accepted = true;
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

                // ── The panel, down the left: the game, the quick actions, then Performance and Sound
                // (scrolling when the screen is short), what's playing and how to leave at its foot ──
                OverlayPanel {
                    id: panel
                    anchors { left: parent.left; top: parent.top }
                    height: Math.min(layout.height, sections.implicitHeight + foot.implicitHeight + 46) // As tall as it needs
                    anchors.leftMargin: window.shown ? 0 : -48
                    Behavior on anchors.leftMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    width: Math.round(Math.max(380, Math.min(520, layout.width * 0.28)))
                    opacity: layout.panelOpacity
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                    StyledFlickable {
                        id: body
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: foot.top; margins: 16; bottomMargin: 14 }
                        clip: true
                        contentHeight: sections.implicitHeight
                        ColumnLayout {
                            id: sections
                            width: body.width
                            spacing: 10
                            ColumnLayout { // The game and what to do, joined
                                Layout.fillWidth: true
                                spacing: 4
                                GameBanner {
                                    readonly property bool hasFps: (root.perf.fps ?? -1) > 0
                                    Layout.fillWidth: true
                                    art: root.bannerArt
                                    gameName: GameClips.game
                                    showStatus: root.gameFullscreen
                                    sessionText: window.sessionMinutes < 0 ? ""
                                        : Translation.tr("This session %1").arg(root.duration(window.sessionMinutes))
                                          // Steam adds this session to its hours when it ends
                                          + (root.game?.playtime ? "  ·  " + Translation.tr("%1 h in all").arg(Math.floor((root.game.playtime + window.sessionMinutes) / 60)) : "")
                                    fpsText: hasFps ? Math.round(root.perf.fps) : ""
                                    fpsDetail: hasFps ? Translation.tr("FPS  ·  avg %1  ·  low %2").arg(Math.round(root.perf.fpsAvg ?? 0)).arg(Math.round(root.perf.fpsLow ?? 0)) : ""
                                    fpsPoints: { // The highest near the top
                                        const h = root.fpsHistory;
                                        if (!hasFps || h.length < 2) return [];
                                        const ceiling = Math.max(60, ...h) * 1.1;
                                        return h.map((v, i) => Qt.point(i / (h.length - 1), Math.min(1, v / ceiling)));
                                    }
                                }
                                Rectangle { // The quick actions, one strip, hairlines between them
                                    Layout.fillWidth: true
                                    implicitHeight: actionRow.implicitHeight
                                    topLeftRadius: Appearance.rounding.joined
                                    topRightRadius: Appearance.rounding.joined
                                    bottomLeftRadius: Appearance.rounding.normal
                                    bottomRightRadius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer3
                                    Repeater {
                                        model: 4
                                        Rectangle {
                                            required property int index
                                            x: Math.round(parent.width * (index + 1) / 5)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 1
                                            height: parent.height - 24
                                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.93)
                                        }
                                    }
                                    RowLayout {
                                        id: actionRow
                                        anchors { left: parent.left; right: parent.right }
                                        spacing: 0
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
                                            text: Translation.tr("Silence")
                                            tip: Translation.tr("Do not disturb: no pop-ups. They still wait in the sidebar")
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
                            ColumnLayout { // How it's running, and the sound, joined
                                Layout.fillWidth: true
                                spacing: 4
                                PerformancePanel {
                                    Layout.fillWidth: true
                                    cpuHistory: root.cpuHistory
                                    gpuHistory: root.gpuHistory
                                    cpuStats: root.cpuStats
                                    gpuStats: root.gpuStats
                                    perf: root.perf
                                    onIntegrated: root.onIntegrated
                                }
                                SoundPanel {
                                    id: soundPanel
                                    Layout.fillWidth: true
                                    gamePids: root.gamePids
                                    gameFlatpak: root.game?.flatpakId ?? ""
                                    gameName: GameClips.game
                                    gameArt: root.perf.icon || GameClips.gameArt // Its square icon, else its cover (a Steam game's icon is its wide logo)
                                }
                            }
                        }
                    }

                    ColumnLayout { // What's playing, and how to leave
                        id: foot
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                        spacing: 12
                        NowPlaying { Layout.fillWidth: true }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6
                            OverlayKey { text: "Esc" }
                            StyledText {
                                text: Translation.tr("or")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            OverlayKey { text: "Super+Shift+G" }
                            StyledText {
                                text: Translation.tr("back to the game")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                // ── The outputs, out of the panel's right edge beside their button; a click anywhere else closes them ──
                MouseArea {
                    anchors.fill: parent
                    visible: soundPanel.outputMenuOpen
                    onClicked: soundPanel.outputMenuOpen = false
                }
                PanelSideDrawer {
                    anchors { left: panel.right; top: panel.top; bottom: panel.bottom; leftMargin: -1 } // Over its border
                    open: soundPanel.outputMenuOpen && layout.panelOpacity > 0
                    onOpenChanged: if (open) anchorY = soundPanel.outputButton.mapToItem(panel, 0, soundPanel.outputButton.height / 2).y
                    paneH: outputList.implicitHeight + 16
                    OutputList {
                        id: outputList
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        outputs: soundPanel.outputs
                        iconFor: soundPanel.outputIcon
                        onPicked: soundPanel.outputMenuOpen = false
                    }
                }

                // ── Down the right, what happened this session, as it adds up: the captures, and under them what
                // came in (only when something did). Each card is as tall as it needs; together they fit the screen,
                // the captures keeping at least half of it, and scroll inside ──
                Item {
                    id: rightColumn
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    anchors.rightMargin: window.shown ? 0 : -48
                    Behavior on anchors.rightMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    width: Math.round(Math.max(320, Math.min(420, layout.width * 0.22)))
                    opacity: layout.panelOpacity
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    readonly property int gap: 16
                    CapturesPanel {
                        id: capturesPanel
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        maxHeight: missedCard.visible
                            ? Math.max(rightColumn.height / 2, rightColumn.height - missedCard.implicitHeight - rightColumn.gap)
                            : rightColumn.height
                        captures: window.captures
                        clipsFolder: GameClips.folderFor(GameClips.game)
                        shotsFolder: window.shotsFolder
                        onOpenCapture: index => window.viewerIndex = index
                        onOpenFolder: folder => root.openFolder(folder)
                        onTrashed: path => window.forget(path)
                    }
                    OverlayPanel {
                        id: missedCard
                        anchors { left: parent.left; right: parent.right; top: capturesPanel.bottom; topMargin: rightColumn.gap }
                        visible: missed.visible
                        implicitHeight: missed.implicitHeight + 28
                        height: Math.min(implicitHeight, rightColumn.height - capturesPanel.height - rightColumn.gap)
                        StyledFlickable {
                            anchors { fill: parent; margins: 14 }
                            clip: true
                            contentHeight: missed.implicitHeight
                            MissedNotifications {
                                id: missed
                                width: parent.width
                                since: GameClips.gameStarted
                                onActivated: root.close()
                            }
                        }
                    }
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

                StyledText { // How to use the viewer
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    visible: window.viewing
                    text: Translation.tr("←/→ to step through · Delete to trash · Esc to go back")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                }
            }
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
