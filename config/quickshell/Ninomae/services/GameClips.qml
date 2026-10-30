pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Gameplay clips: while a game runs, gpu-screen-recorder keeps the last N seconds in RAM (encoded on
 * the GPU, a few % of it), and the clip key (` by default, set in Settings → Games; bound below) saves them to
 * ~/Videos/Clips/<game>/. Nothing runs outside games. scripts/clips/game_watch.py says which game is
 * running (however it was started: Steam, Lutris, or one added in the launcher); scripts/clips/on_save.sh
 * names the file and notifies.
 */
Singleton {
    id: root
    function load() {} // Referenced from shell.qml so the singleton starts with the shell

    readonly property var options: Config.options.gameLauncher
    readonly property bool enabled: Config.ready && (options?.clipsEnabled ?? false) && available
    readonly property int seconds: options?.clipSeconds ?? 60
    readonly property bool withMic: options?.clipMic ?? true
    readonly property string clipsDir: Config.expandHome(options?.clipsFolder || "~/Videos/Clips")

    readonly property string keyCombo: options?.clipKey || "grave"
    readonly property string keyLabel: options?.clipKeyLabel || "`"

    property bool available: false // gpu-screen-recorder installed
    property string game: ""       // Name of the running game, "" when none
    property string gameId: ""     // Its launcher id (steam_<appid>, lutris_…, a custom one), "" when none or unknown
    // Whether the focused window is the game's own (the watcher's "focus" lines; for the crosshair).
    // focusKnown stays false if the watcher can't read Hyprland's events
    property bool gameFocused: false
    property bool focusKnown: false
    // For the "Clip saved" notification's picture (on_save.sh picks): its Steam app id (Steam's square icon)
    // and its cover art, else the film icon
    property string gameAppId: ""
    property string gameArt: ""
    readonly property bool recording: recorder.running

    Process {
        running: true
        command: ["sh", "-c", "command -v gpu-screen-recorder"]
        onExited: exitCode => root.available = exitCode === 0
    }

    // ── Which game is running ──
    Process {
        id: watcher
        // For the clips, and for the crosshair while any game has it on (services/Crosshair.qml)
        running: root.enabled || (Config.options.crosshair?.games?.length ?? 0) > 0
        // With the launcher's hand-added games, so their clips record too
        command: ["python3", "-I", Quickshell.shellPath("scripts/clips/game_watch.py"), `${GameLauncherService.cacheDir}/custom_games.json`]
        stdout: SplitParser {
            onRead: line => {
                const [kind, ...rest] = line.trim().split(" ");
                const key = rest.join(" ");
                if (kind === "focus") { root.gameFocused = key === "1"; root.focusKnown = true; return; }
                // Art first: a new game restarts the recorder on the name change, and it should start with both
                if (kind === "steam") {
                    const g = GameLauncherService.games.find(x => x.id === `steam_${key}`);
                    root.gameAppId = key;
                    root.gameArt = g?.boxArt ?? "";
                    root.game = g?.name || `Steam game ${key}`;
                    root.gameId = `steam_${key}`;
                } else if (kind === "custom") {
                    const g = GameLauncherService.customGames.find(x => x.id === key);
                    const lib = GameLauncherService.games.find(x => x.id === key);
                    root.gameAppId = "";
                    root.gameArt = GameLauncherService.customArt[key]?.boxArt ?? lib?.icon ?? "";
                    root.game = g?.name || "Game";
                    root.gameId = key;
                } else if (kind === "lutris") {
                    const g = GameLauncherService.games.find(x => x.name === key);
                    root.gameAppId = "";
                    root.gameArt = g?.boxArt ?? "";
                    root.game = key || "Game";
                    root.gameId = g?.id ?? "";
                } else {
                    root.game = "";
                    root.gameId = "";
                }
            }
        }
        onRunningChanged: if (!running) { root.game = ""; root.gameId = ""; root.gameFocused = false; root.focusKnown = false; }
    }

    // ── The replay buffer ──
    // Settings are read when it starts, so a change applies from the next game
    // Another game straight after one (the watcher saw no gap): a fresh recorder, so its clips get the new
    // name and folder, and the last game's moments aren't saved as this one's
    property bool _restarting: false
    onGameChanged: if (recorder.running) { _restarting = true; Qt.callLater(() => root._restarting = false); }
    Process {
        id: recorder
        running: root.enabled && root.game !== "" && !root._restarting
        command: [
            // The folder first; exec, so the save signal reaches the recorder itself
            "sh", "-c", 'mkdir -p -- "$1" && shift && exec gpu-screen-recorder "$@"', "clip-recorder", root.clipsDir,
            "-w", Hyprland.focusedMonitor?.name || "screen", // The monitor in focus when the game started
            "-f", "60",
            "-c", "mp4", "-k", "h264", "-ac", "aac", // Plays everywhere, Discord included
            "-bm", "cbr", "-q", "12000",             // 12 Mbps: steady quality, ~90 MB a minute
            "-a", root.withMic ? "default_output|default_input" : "default_output", // One mixed track
            "-r", String(root.seconds),
            "-o", root.clipsDir,
            "-sc", Quickshell.shellPath("scripts/clips/on_save.sh"),
        ]
        environment: ({ CLIP_GAME: root.game, CLIPS_DIR: root.clipsDir, CLIP_SECONDS: String(root.seconds),
                        CLIP_APPID: root.gameAppId, CLIP_ART: root.gameArt })
        stderr: StdioCollector { id: recorderErrors }
        onExited: (exitCode, exitStatus) => {
            // Stopped on purpose, the game having quit, leaves no game; still one means it failed
            if (exitCode === 0 || !root.enabled || root.game === "") return;
            console.warn("[GameClips] gpu-screen-recorder exited", exitCode, ":", recorderErrors.text.trim().split("\n").slice(-3).join(" | "));
            Quickshell.execDetached(["notify-send", "-a", "Clips", "-i", "dialog-warning",
                "Clip recorder stopped", `It couldn't keep recording ${root.game}, so clips won't save until the next game.`]);
        }
    }

    // ── Trim (the Clips page asks; scripts/clips/export_clip.py makes it) ──
    // Here rather than in the page, so closing the launcher doesn't stop one halfway
    property string exportKind: "" // "trim" while one is being made
    property real exportProgress: 0
    property bool pageOpen: false // A Clips page is showing (it says how it went; otherwise a notification does)
    signal exportFinished(string kind, bool ok, string message, string path, real bytes)
    function exportClip(kind, path, start, end) {
        if (exporter.running) return;
        root.exportKind = kind;
        root.exportProgress = 0;
        exporter._result = null;
        exporter.command = ["python3", "-I", Quickshell.shellPath("scripts/clips/export_clip.py"), kind, path,
                            start.toFixed(3), end.toFixed(3)];
        exporter.running = true;
    }
    Process {
        id: exporter
        property var _result: null
        stdout: SplitParser {
            onRead: line => {
                const [word, ...rest] = line.split(" ");
                if (word === "progress") root.exportProgress = parseFloat(rest[0]) || 0;
                else if (word === "done") exporter._result = { ok: true, message: "", bytes: parseInt(rest[0]), path: rest.slice(1).join(" ") };
                else if (word === "error") exporter._result = { ok: false, message: rest.join(" "), bytes: 0, path: "" };
            }
        }
        onExited: (exitCode, exitStatus) => {
            const kind = root.exportKind, r = exporter._result ?? { ok: false, message: Translation.tr("It stopped before finishing"), bytes: 0, path: "" };
            root.exportKind = "";
            root.exportFinished(kind, r.ok, r.message, r.path, r.bytes);
            if (root.pageOpen) return;
            Quickshell.execDetached(["notify-send", "-a", "Clips", "-i", r.ok ? "video-x-generic" : "dialog-warning",
                r.ok ? "Trim saved" : "Couldn't save the trim", r.ok ? "Saved as a new clip" : r.message]);
        }
    }

    // The folder a game's clips go in: its name made safe as a folder name, the same way
    // scripts/clips/on_save.sh does it (no control characters or slashes, no dots or spaces at the ends)
    function folderFor(name) {
        const safe = (name ?? "").replace(/[\x00-\x1f]/g, "").replace(/\//g, "-").replace(/^[. ]*/, "").replace(/[. ]*$/, "");
        return `${root.clipsDir}/${safe || "Game"}`;
    }
    function save() {
        if (!recorder.running) return;
        recorder.signal(10); // SIGUSR1: save the replay (on_save.sh moves it and notifies)
    }

    // ── The save key ──
    // Bound by hypr/hyprland/keybinds.lua from a file written here (a Lua chunk returning the key, "" with
    // clips off); when it changes, Hyprland reloads its config, which builds every bind afresh. Never bound
    // or unbound at runtime with hyprctl eval: removing a bind that way crashed Hyprland (0.56.2)
    readonly property string keyFile: `${Directories.state}/user/clip_key.lua`.replace(/^file:\/\//, "")
    readonly property string _keyLua: `return ${JSON.stringify(Config.ready && (options?.clipsEnabled ?? false) ? root.keyCombo : "")}\n`
    function applyKey() {
        if (!Config.ready) return;
        // Only when it differs (the shell starting writes nothing new, so Hyprland isn't reloaded for nothing)
        Quickshell.execDetached(["sh", "-c", '[ "$(cat -- "$1" 2>/dev/null)" = "$(printf "%s" "$2" | head -c -1)" ] && exit 0; '
            + 'mkdir -p -- "$(dirname -- "$1")" && printf "%s" "$2" > "$1" && hyprctl reload >/dev/null', "clip-key", root.keyFile, root._keyLua]);
    }
    on_KeyLuaChanged: keyDebounce.restart()
    Timer { id: keyDebounce; interval: 300; onTriggered: root.applyKey() }
    Component.onCompleted: keyDebounce.restart()

    GlobalShortcut {
        name: "clipSave"
        description: "Saves the last seconds of gameplay while a game runs"
        onPressed: root.save()
    }
    IpcHandler {
        target: "clips"
        function save(): void { root.save(); }
        function status(): string { return root.recording ? `recording ${root.game} (${root.seconds}s)` : root.enabled ? "waiting for a game" : "off"; }
    }
}
