pragma Singleton
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * When the crosshair overlay (modules/crosshair) shows. On its own: while a game it's turned on for (the
 * crosshair button under Play on a game's page in the launcher) is running and its own window has the
 * focus, as GameClips' game watcher reports (windowed or fullscreen), so it's gone on alt-tab and never
 * over another fullscreen app.
 * Never over the launcher, overview, session or region screens, or the in-game overlay. Super+G
 * (crosshairToggle) shows or hides it by hand, in any game or none, until the game changes. `qs -c Ninomae ipc call crosshair test` shows
 * it for 3 s (Settings' Test button).
 */
Singleton {
    id: root
    function load() {} // Referenced from shell.qml so the singleton starts with the shell

    readonly property var games: Config.options.crosshair?.games ?? []
    readonly property string gameId: GameClips.gameId
    readonly property bool onForGame: gameId !== "" && games.indexOf(gameId) >= 0

    readonly property Toplevel focused: ToplevelManager.activeToplevel
    // The game's own window has the focus (the watcher matches it to the game's processes, windowed or not).
    // Without Hyprland's events: a fullscreen or Steam game window, as a fallback
    readonly property bool gameFocused: GameClips.focusKnown ? GameClips.gameFocused
        : !!focused && (focused.fullscreen || /^steam_app_\d+$/.test(focused.appId ?? "") || focused.appId === "gamescope")
    readonly property bool blocked: GlobalStates.overviewOpen || GlobalStates.gameLauncherOpen || GlobalStates.sessionOpen
        || GlobalStates.regionSelectorOpen || GlobalStates.screenLocked || GlobalStates.gameOverlayOpen

    property var manual: null // null: automatic; true/false: Super+G's choice, until the game changes
    onGameIdChanged: manual = null
    property bool testing: false

    readonly property bool automatic: onForGame && gameFocused
    readonly property bool shown: Config.ready && (testing || (!blocked && (manual ?? automatic)))
    // The game's screen: the focused window's, else the focused monitor
    readonly property ShellScreen screen: focused?.screens?.[0]
        ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    // Back to what it would do on its own hands control back (so it hides on alt-tab again), rather than
    // pinning it on until the game changes
    function toggle() {
        root._choose(!root.shown);
    }
    // From the in-game overlay, which hides it while open: flips what it'll do once the overlay closes
    function toggleOutsideOverlay() {
        root._choose(!(root.manual ?? root.automatic));
    }
    function _choose(want) {
        root.testing = false;
        root.manual = want === root.automatic ? null : want;
    }
    function test() {
        root.testing = true;
        testTimer.restart();
    }
    Timer { id: testTimer; interval: 3000; onTriggered: root.testing = false }

    IpcHandler {
        target: "crosshair"
        function toggle(): void { root.toggle(); }
        function test(): void { root.test(); }
    }
    GlobalShortcut {
        name: "crosshairToggle"
        description: "Shows or hides the crosshair"
        onPressed: root.toggle()
    }
}
