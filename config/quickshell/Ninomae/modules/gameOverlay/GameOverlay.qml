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
 *  - at the top, what the bar would say in fullscreen (the game, play time, clock, battery), and quick actions
 *    under it: save a clip, screenshot, crosshair, do not disturb, game mode (accent when on; a letter each)
 *  - on the left, the game (GameBanner), this session's clips and screenshots (CapturesPanel: one opens in
 *    CaptureViewer, over everything), and what came in while playing (MissedNotifications)
 *  - on the right, live CPU and GPU graphs (PerformancePanel), and the sound (SoundPanel): the game's own
 *    first, matched by process (scripts/clips/game_pids.py: Steam, Lutris, Flatpak or its program) or, for
 *    a Flatpak, its app id, then voice chat
 *  - between them at the bottom, what's playing (NowPlaying)
 * Both columns are the same width (narrower on a small screen) and run from under the actions to the bottom.
 * On the overlay layer of the focused screen, with the keyboard: Esc or the key again closes it, as does a
 * click on the backdrop. Clip and screenshot close it first, so they show the game. Only exists while open,
 * apart from the graphs' history, kept for the next time it opens during the same game. It only opens while
 * a game runs (GameClips' watcher), and closes if the game does. Settings → Games turns it off
 * (gameLauncher.overlayEnabled): the key then does nothing.
 */
Scope {
    id: root
    readonly property bool enabled: Config.options.gameLauncher.overlayEnabled ?? true
    readonly property bool available: enabled && GameClips.game !== "" // Over a game only
    readonly property bool open: available && GlobalStates.gameOverlayOpen
    onAvailableChanged: if (!available) close() // Turned off, or the game closed
    function toggle() { GlobalStates.gameOverlayOpen = root.available && !GlobalStates.gameOverlayOpen; }
    function close() { GlobalStates.gameOverlayOpen = false; }

    // The launcher's entry for the running game (art, hours, folders), when it has one
    readonly property var game: GameClips.gameId ? GameLauncherService.games.find(g => g.id === GameClips.gameId) ?? null : null
    readonly property string bannerArt: {
        const custom = GameLauncherService.customArt[GameClips.gameId]?.heroArt ?? "";
        for (const p of [custom, game?.heroArt, game?.derivedHeroArt, GameClips.gameArt])
            if (p && p.startsWith("/")) return p;
        return "";
    }

    // ── Capture: done once the overlay has gone, so they show the game ──
    property string _pendingCapture: ""
    function capture(kind) {
        root._pendingCapture = kind;
        root.close();
        captureTimer.restart();
    }
    Timer {
        id: captureTimer
        interval: 350
        onTriggered: {
            if (root._pendingCapture === "clip") GameClips.save();
            else if (root._pendingCapture === "screenshot") Quickshell.execDetached([
                Quickshell.shellPath("scripts/game-launcher/game_screenshot.sh"),
                Hyprland.focusedMonitor?.name ?? "", GameClips.game || "Game",
                GameClips.gameAppId, root.game?.gameDir ?? "", root.game?.flatpakId ?? ""]);
            root._pendingCapture = "";
        }
    }
    function openFolder(folder) {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "open-folder", folder]);
        root.close();
    }

    // ── Graph history: sampled while open, kept between openings during one game ──
    readonly property int historyLength: 40
    property var cpuHistory: []
    property var gpuHistory: []
    Connections {
        target: GameClips
        function onGameChanged() { root.cpuHistory = []; root.gpuHistory = []; }
    }
    function pushSample(list, value) {
        const next = list.concat([Math.min(1, Math.max(0, value))]);
        return next.length > historyLength ? next.slice(next.length - historyLength) : next;
    }
    function duration(minutes) {
        return minutes < 60 ? Translation.tr("%1 min").arg(minutes)
            : Translation.tr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60);
    }

    LazyLoader {
        active: root.open
        component: PanelWindow {
            id: window
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:gameOverlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            // The numbers only update while something shows them
            Component.onCompleted: { ResourceUsage.watchers++; shown = true; }
            Component.onDestruction: ResourceUsage.watchers--
            property bool shown: false
            property real now: Date.now()
            Timer { running: true; repeat: true; interval: 15000; onTriggered: window.now = Date.now() }
            Timer {
                running: true
                repeat: true
                interval: Config.options?.resources?.updateInterval ?? 3000
                // Not on start: CPU use is a difference between two polls, so right after opening it's stale
                onTriggered: {
                    root.cpuHistory = root.pushSample(root.cpuHistory, ResourceUsage.cpuUsage);
                    if (ResourceUsage.gpuDetected) root.gpuHistory = root.pushSample(root.gpuHistory, ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuUsage);
                }
            }
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
                running: GameClips.game !== "" && GameClips.gameStarted > 0
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
                running: GameClips.game !== "" && GameClips.gameStarted > 0
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

                // ── Top: what the bar would say, then the quick actions ──
                ColumnLayout {
                    id: top
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                    anchors.topMargin: window.shown ? 0 : -24
                    opacity: layout.panelsOpacity
                    Behavior on anchors.topMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    spacing: 12

                    OverlayPanel {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: statusRow.implicitWidth + 32
                        implicitHeight: 48
                        radius: Appearance.rounding.normal // A rounded rectangle, not a pill
                        RowLayout {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 14
                            MaterialSymbol { text: "sports_esports"; iconSize: 20; color: Appearance.colors.colPrimary }
                            StyledText {
                                text: GameClips.game
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                            Dot { visible: window.sessionMinutes >= 0 }
                            StyledText {
                                visible: window.sessionMinutes >= 0
                                text: root.duration(window.sessionMinutes)
                                color: Appearance.colors.colSubtext
                            }
                            Dot {}
                            StyledText {
                                text: DateTime.time
                                font.family: Appearance.font.family.numbers
                                color: Appearance.colors.colOnLayer0
                            }
                            Dot { visible: Battery.available }
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
                                    color: Appearance.colors.colOnLayer0
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
                                    : GameClips.enabled ? Translation.tr("Records once a game is running") : Translation.tr("Clips are off in Settings → Games")
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
                ColumnLayout {
                    anchors { left: parent.left; top: top.bottom; topMargin: 24; bottom: hint.top; bottomMargin: 16 }
                    anchors.leftMargin: window.shown ? 0 : -40
                    Behavior on anchors.leftMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    opacity: layout.panelsOpacity
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    width: layout.columnWidth
                    spacing: 12
                    GameBanner {
                        Layout.fillWidth: true
                        art: root.bannerArt
                        gameName: GameClips.game
                        sessionText: window.sessionMinutes < 0 ? ""
                            : Translation.tr("This session %1").arg(root.duration(window.sessionMinutes))
                              // Steam adds this session to its hours when it ends
                              + (root.game?.playtime ? "  ·  " + Translation.tr("%1 h in all").arg(Math.floor((root.game.playtime + window.sessionMinutes) / 60)) : "")
                    }
                    CapturesPanel {
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
                        Layout.fillHeight: true
                        since: GameClips.gameStarted
                    }
                }

                // ── Right: how hard the computer is working, and the sound ──
                ColumnLayout {
                    anchors { right: parent.right; top: top.bottom; topMargin: 24; bottom: hint.top; bottomMargin: 16 }
                    anchors.rightMargin: window.shown ? 0 : -40
                    Behavior on anchors.rightMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    opacity: layout.panelsOpacity
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    width: layout.columnWidth
                    spacing: 12
                    PerformancePanel {
                        Layout.fillWidth: true
                        cpuHistory: root.cpuHistory
                        gpuHistory: root.gpuHistory
                    }
                    SoundPanel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
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

    component Dot: Rectangle { // Between the status strip's parts
        implicitWidth: 4; implicitHeight: 4; radius: 2
        color: Appearance.colors.colSubtext
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
