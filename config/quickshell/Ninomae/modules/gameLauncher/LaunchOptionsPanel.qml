import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * A Steam game's launch options, in a panel growing up out of the launcher (LauncherTopPanel). Written into
 * Steam's own settings by scripts/game-launcher/launch_options.py, so Steam's Launch Options box shows the same.
 * On top, an art banner (ArtBanner, the game's logo) with how saving works, close, and on its foot the whole line as
 * Steam will run it with Undo and Save. Joined under it, three wells of one-line rows: the tools (GameMode, MangoHud,
 * gamescope), each switching its word in front of %command%; Proton's switches (Wayland, HDR, NTSYNC, a variable
 * each); and Steam's: the Proton version and Updates (once it's installed: the mode lives in the game's appmanifest).
 * Under them, a well with the settings of the tools that are on (MangoHud's layout, as MANGOHUD_CONFIG=preset=N;
 * gamescope's screen, refresh rate and mode; the picture (the whole screen, or 16:9 in the middle of an ultrawide)
 * and whether the mouse is locked to the game; FSR upscaling; any other flags).
 * With the shell's Millennium plugin in Steam (themes/steam/ninomae-plugin) every change goes straight to
 * Steam as it's made (typing, after a pause), and Undo puts back what it was on opening. Without it Steam
 * rewrites its settings when it quits, so there's a Save, which closes and restarts Steam while it's open.
 * Keys: Enter in a box saves, Esc closes.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1160
    // As tall as what's in it (the banner, the wells, the tools' settings), up to gamescope's settings without scrolling
    panelHeight: loaded ? Math.min(640, body.y + bodyColumn.implicitHeight + body.anchors.bottomMargin) : 300
    readonly property string appid: game?.id?.startsWith("steam_") ? game.id.substring(6) : ""
    readonly property string helper: Quickshell.shellPath("scripts/game-launcher/launch_options.py")

    // What the helper reported, the edited copy, and what it was on opening (Undo)
    property var info: null
    property string options: ""
    property string proton: ""
    property int autoUpdate: -1 // -1: no manifest (not installed)
    property var openedWith: null
    property string status: "" // "", "loading", "saving", "saved", "error:<text>"
    readonly property bool loaded: info !== null
    readonly property bool live: info?.live ?? false // Saving goes straight to Steam, so it's done as you go
    readonly property bool steamRunning: info?.steamRunning ?? false
    readonly property bool restartNeeded: steamRunning && !live
    readonly property bool unreachable: info?.unreachable ?? false // The plugin should answer but doesn't
    function differs(a) {
        return !!a && (options.trim() !== (a.options ?? "").trim() || proton !== (a.proton ?? "") || autoUpdate !== (a.autoUpdate ?? -1));
    }
    readonly property bool changed: loaded && differs({ options: info.launchOptions, proton: info.proton, autoUpdate: info.autoUpdate })
    readonly property bool canUndo: loaded && differs(openedWith)
    readonly property bool busy: status === "saving"
    readonly property bool hasProton: (info?.protonVersions?.length ?? 0) > 0
    readonly property var protonOptions: [{ displayName: Translation.tr("Steam default"), value: "" },
        ...(info?.protonVersions ?? []).map(v => ({ displayName: v.label, value: v.name }))]
    readonly property var updateOptions: [
        { displayName: Translation.tr("Keep updated"), value: 0 },
        { displayName: Translation.tr("Only when I launch it"), value: 1 },
        { displayName: Translation.tr("High priority"), value: 2 }
    ]

    // ── The options string ↔ the tools ──
    // Words before %command% wrap the game; gamescope takes everything up to its "--"
    function parse(s) {
        s = (s ?? "").trim();
        const i = s.indexOf("%command%");
        if (i < 0) return { pre: [], gamescope: null, game: s };
        const tokens = s.substring(0, i).trim().split(/\s+/).filter(t => t);
        const pre = [];
        let gamescope = null;
        for (let k = 0; k < tokens.length; k++) {
            if (tokens[k] === "gamescope") {
                const end = tokens.indexOf("--", k);
                const stop = end < 0 ? tokens.length : end;
                gamescope = tokens.slice(k + 1, stop).join(" ");
                k = stop;
            } else pre.push(tokens[k]);
        }
        return { pre: pre, gamescope: gamescope, game: s.substring(i + 9).trim() };
    }
    function build(p) {
        const wrap = [...p.pre];
        if (p.gamescope !== null) wrap.push(`gamescope ${p.gamescope} --`.replace(/\s+/g, " "));
        return wrap.length ? `${wrap.join(" ")} %command% ${p.game}`.trim() : p.game;
    }
    readonly property var parsed: parse(options)
    // Proton's switches: a variable each, in front of the rest (HDR needs Wayland, so it brings it)
    readonly property var envs: ({ wayland: "PROTON_ENABLE_WAYLAND=1", hdr: "PROTON_ENABLE_HDR=1", ntsync: "PROTON_USE_NTSYNC=1" })
    readonly property var toolsOn: ({ gamemode: parsed.pre.includes("gamemoderun"), mangohud: parsed.pre.includes("mangohud"),
                                      gamescope: parsed.gamescope !== null, wayland: parsed.pre.includes(envs.wayland),
                                      hdr: parsed.pre.includes(envs.hdr), ntsync: parsed.pre.includes(envs.ntsync) })
    function toggle(tool) {
        const p = parse(options);
        if (tool === "gamescope") {
            // Back on: the options it had (this opening), else ones for this screen
            if (p.gamescope !== null) _gamescopeArgs = p.gamescope;
            p.gamescope = p.gamescope === null ? (_gamescopeArgs || (info?.defaultGamescopeArgs ?? "")) : null;
        } else if (envs[tool]) {
            const on = !p.pre.includes(envs[tool]);
            const words = on && tool === "hdr" ? [envs.wayland, envs.hdr] : [envs[tool]];
            const drop = !on && tool === "wayland" ? [envs.wayland, envs.hdr] : on ? [] : [envs[tool]];
            p.pre = p.pre.filter(t => !drop.includes(t));
            if (on) p.pre = words.filter(w => !p.pre.includes(w)).concat(p.pre);
        } else {
            const word = tool === "gamemode" ? "gamemoderun" : "mangohud";
            // Off: its word, and MangoHud's layout with it
            if (p.pre.includes(word)) p.pre = p.pre.filter(t => t !== word && !(word === "mangohud" && presetOf(t) !== ""));
            else {
                // Env vars stay first, then gamemoderun, then mangohud
                const envEnd = p.pre.filter(t => t.includes("=")).length;
                const at = word === "mangohud" ? Math.max(envEnd, p.pre.indexOf("gamemoderun") + 1) : envEnd;
                p.pre.splice(at, 0, word);
            }
        }
        options = build(p);
    }
    // MangoHud's layout: one of its presets (README: preset=), "" for its own config, "custom" for other settings.
    // A preset leaves MangoHud.conf unread, so it carries the frame-rate log the in-game overlay's FPS reads
    // (as MangoHud.conf's, into the folder GameOverlay reads); one written before that, without it, still counts
    // as the preset
    readonly property string mangohudLog: "output_folder=~/.cache/quickshell/mangohud,autostart_log=1,log_interval=250"
    function presetOf(token) {
        const m = /^MANGOHUD_CONFIG=preset=(\d)(,.*)?$/.exec(token);
        return m && (!m[2] || m[2] === "," + mangohudLog) ? m[1] : "";
    }
    readonly property string mangohudPreset: {
        const v = parsed.pre.find(t => t.startsWith("MANGOHUD_CONFIG="));
        if (!v) return "";
        return presetOf(v) || "custom";
    }
    function setMangohudPreset(preset) {
        const p = parse(options);
        p.pre = p.pre.filter(t => !t.startsWith("MANGOHUD_CONFIG="));
        if (preset !== "") p.pre.unshift(`MANGOHUD_CONFIG=preset=${preset},${mangohudLog}`); // Env vars first
        options = build(p);
    }

    // ── gamescope's flags ↔ its controls: output size and refresh, mode, FSR (the game drawn smaller, scaled
    //    up), and the rest kept as they were ──
    property string _gamescopeArgs: ""
    readonly property var scope: parseGamescope(parsed.gamescope)
    function parseGamescope(args) {
        const t = (args ?? "").trim().split(/\s+/).filter(x => x);
        const g = { W: 0, H: 0, w: 0, h: 0, r: 0, mode: "", filter: "", scaler: "", grab: false, rest: [] };
        const num = i => parseInt(t[i + 1]) || 0;
        for (let i = 0; i < t.length; i++) {
            const a = t[i];
            if (a === "-W" || a === "--output-width") g.W = num(i++);
            else if (a === "-H" || a === "--output-height") g.H = num(i++);
            else if (a === "-w" || a === "--nested-width") g.w = num(i++);
            else if (a === "-h" || a === "--nested-height") g.h = num(i++);
            else if (a === "-r" || a === "--nested-refresh") g.r = num(i++);
            else if (a === "-f" || a === "--fullscreen") g.mode = "fullscreen";
            else if (a === "-b" || a === "--borderless") g.mode = "borderless";
            else if (a === "-F" || a === "--filter") g.filter = t[++i] ?? "";
            else if (a === "-S" || a === "--scaler") g.scaler = t[++i] ?? "";
            else if (a === "--force-grab-cursor") g.grab = true;
            else g.rest.push(a);
        }
        return g;
    }
    function setScope(change) {
        const g = Object.assign({}, scope, change); // scope is parsed already (rest is only read)
        // The picture keeps its shape and FSR level as the output changes (a new picture brings its own size)
        if (change.W && change.w === undefined && (gameAspect || fsrLevel)) Object.assign(g, pictureSize(g.W, g.H, gameAspect, fsrLevel));
        const out = [];
        if (g.mode === "fullscreen") out.push("-f"); else if (g.mode === "borderless") out.push("-b");
        if (g.W && g.H) out.push("-W", g.W, "-H", g.H);
        if (g.w && g.h) out.push("-w", g.w, "-h", g.h);
        if (g.r) out.push("-r", g.r);
        if (g.filter) out.push("-F", g.filter);
        if (g.scaler) out.push("-S", g.scaler);
        if (g.grab) out.push("--force-grab-cursor");
        const p = parse(options);
        p.gamescope = out.concat(g.rest).join(" ");
        options = build(p);
    }
    // FSR's levels: the share of the output the game is drawn at
    readonly property var fsrLevels: [
        { value: "", label: Translation.tr("No FSR") }, { value: "0.77", label: Translation.tr("Ultra") },
        { value: "0.67", label: Translation.tr("Quality") }, { value: "0.59", label: Translation.tr("Balanced") },
        { value: "0.5", label: Translation.tr("Performance") }
    ]
    // Its share of the output's height, which holds whatever the picture's shape
    readonly property string fsrLevel: {
        if (scope.filter !== "fsr" || !scope.h || !scope.H) return "";
        const k = scope.h / scope.H;
        return fsrLevels.slice(1).reduce((best, l) => Math.abs(l.value - k) < Math.abs(best.value - k) ? l : best).value;
    }
    // ── The game's picture: the whole output, or 16:9 in the middle of a wider one ("16:9"), as a 16:9 monitor
    //    would show it (2560 × 1440 on a 5120 × 1440 ultrawide), black at the sides. gamescope stays fullscreen
    //    and fits the game's smaller picture into it (-S fit keeps its shape); FSR draws it smaller still ──
    readonly property real wideAspect: 16 / 9
    readonly property int outW: scope.W || (info?.monitors?.[0]?.width ?? 0)
    readonly property int outH: scope.H || (info?.monitors?.[0]?.height ?? 0)
    readonly property bool canNarrow: outH > 0 && outW / outH > wideAspect + 0.05 // Wider than 16:9
    readonly property string gameAspect: scope.w && scope.h && canNarrow
        && Math.abs(scope.w / scope.h - wideAspect) < 0.02 ? "16:9" : ""
    // The game's size (-w/-h) for an output, a shape and an FSR level; 0 × 0 is the output's own
    function pictureSize(W, H, aspect, level) {
        if (aspect === "" && level === "") return { w: 0, h: 0 };
        const k = level === "" ? 1 : Number(level);
        return { w: Math.round((aspect === "16:9" ? H * wideAspect : W) * k), h: Math.round(H * k) };
    }
    function setPicture(aspect, level) {
        const change = Object.assign({ filter: level === "" ? "" : "fsr" }, pictureSize(outW, outH, aspect, level));
        if (change.w) { change.W = outW; change.H = outH; } // A picture needs the output's size written out
        if (aspect === "16:9") {
            change.scaler = "fit";
            if (scope.mode === "") change.mode = "fullscreen"; // The black sides need the whole screen
        } else if (scope.scaler === "fit") change.scaler = "";
        setScope(change);
    }
    readonly property int narrowW: Math.round(outH * wideAspect)
    readonly property var aspectOptions: [
        { value: "", label: Translation.tr("Whole screen") },
        // A game keeps the resolution it saved, and draws that squeezed into the 16:9 picture
        { value: "16:9", label: Translation.tr("16:9 · %1 × %2").arg(narrowW).arg(outH),
          tip: Translation.tr("Set the game's own resolution to %1 × %2 too, or it draws squeezed").arg(narrowW).arg(outH) }
    ]
    readonly property var mouseOptions: [
        { value: "grab", label: Translation.tr("Mouse locked"), tip: Translation.tr("Always the game's, so aiming doesn't catch") },
        { value: "", label: Translation.tr("Mouse free"), tip: Translation.tr("gamescope switches it as the game hides and shows its cursor") }
    ]
    // The screens' sizes, and the one in use if it's another
    readonly property var sizeOptions: {
        const seen = new Set(), out = [];
        for (const m of info?.monitors ?? []) {
            const v = `${m.width}x${m.height}`;
            if (!seen.has(v)) { seen.add(v); out.push({ displayName: `${m.width} × ${m.height}`, value: v }); }
        }
        if (scope.W && !seen.has(`${scope.W}x${scope.H}`)) out.push({ displayName: `${scope.W} × ${scope.H}`, value: `${scope.W}x${scope.H}` });
        return out;
    }
    // The fastest screen's rate and the usual ones under it, and the one in use if it's another
    readonly property var refreshOptions: {
        const top = Math.max(60, ...(info?.monitors ?? []).map(m => m.refresh));
        const rates = [top, ...[240, 165, 144, 120, 90, 60, 30].filter(r => r < top)];
        if (scope.r && !rates.includes(scope.r)) rates.push(scope.r);
        return rates.sort((a, b) => b - a).map(r => ({ displayName: `${r} Hz`, value: r }));
    }
    readonly property var modeOptions: [
        { displayName: Translation.tr("Fullscreen"), value: "fullscreen" },
        { displayName: Translation.tr("Borderless"), value: "borderless" },
        { displayName: Translation.tr("Window"), value: "" }
    ]

    // ── Steam's settings, read and written by the helper ──
    onShownChanged: if (shown && appid) { openedWith = null; load(); }
    function load() {
        if (info?.appid !== appid) info = null; // Don't show the last game's options while this one loads
        status = "loading";
        getProc.command = ["python3", "-I", helper, "get", appid];
        getProc.running = true;
    }
    function revert() {
        options = info?.launchOptions ?? "";
        proton = info?.proton ?? "";
        autoUpdate = info?.autoUpdate ?? -1;
    }
    function undo() {
        if (!openedWith) return;
        options = openedWith.options; proton = openedWith.proton; autoUpdate = openedWith.autoUpdate;
        if (live) saveNow();
    }
    function saveNow() { autoSave.stop(); save(); } // Not waiting for typing to pause
    property var _sending: null // What's being saved, live: Steam has it once it's done
    function save() {
        if (!changed || busy) return;
        status = "saving";
        _sending = { launchOptions: options, proton: proton, autoUpdate: autoUpdate };
        const cmd = ["python3", "-I", helper, "set", appid, JSON.stringify(_sending)];
        if (restartNeeded) cmd.push("--restart");
        setProc.command = cmd;
        setProc.running = true;
    }
    // Live: each change goes to Steam on its own, typing once it pauses
    onOptionsChanged: queueSave()
    onProtonChanged: queueSave()
    onAutoUpdateChanged: queueSave()
    function queueSave() { if (live && changed) autoSave.restart(); }
    Timer { id: autoSave; interval: 600; onTriggered: root.save() }
    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(text);
                    root.revert();
                    if (!root.openedWith) root.openedWith = { options: root.options, proton: root.proton, autoUpdate: root.autoUpdate };
                    root.status = "";
                } catch (e) { root.status = "error:" + Translation.tr("Couldn't read Steam's settings"); }
            }
        }
    }
    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null; try { r = JSON.parse(text); } catch (e) {}
                if (!r?.ok) {
                    root.status = "error:" + (r?.error === "steam-wont-close" ? Translation.tr("Steam didn't close. Try again")
                                                : Translation.tr("Couldn't save. See the shell log"));
                    return;
                }
                root.status = "saved";
                savedReset.restart();
                // Live: Steam has what was sent. Not read back, which would undo typing since; anything newer goes next
                if (root.live) {
                    root.info = Object.assign({}, root.info, root._sending);
                    root.queueSave();
                } else root.load();
            }
        }
    }
    Timer { id: savedReset; interval: 2500; onTriggered: if (root.status === "saved") root.status = "" }

    function handleKey(key) {
        if (key === Qt.Key_Escape) { closeRequested(); return true; }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && changed) { saveNow(); return true; }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the panel
    }

    SheetEmptyState { // Reading, or couldn't
        anchors.centerIn: parent
        visible: !root.loaded
        icon: root.status.startsWith("error:") ? "error" : "hourglass_empty"
        text: root.status.startsWith("error:") ? root.status.substring(6) : Translation.tr("Reading Steam's settings…")
    }

    // ── Banner: the game, how saving works (and how it's going), close; and on its foot the whole line as Steam will
    //    run it, with Undo and Save. Joined over the wells under it (as the rail's Play over its well) ──
    ArtBanner {
        id: banner
        visible: root.loaded
        game: root.game
        showLogo: true
        coverIcon: "tune"
        anchors { top: parent.top; topMargin: 12; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        height: 116
        topLeftRadius: Appearance.rounding.normal; topRightRadius: Appearance.rounding.normal
        bottomLeftRadius: root._join; bottomRightRadius: root._join
        Column {
            anchors { left: banner.coverItem.right; leftMargin: 18; right: closeButton.left; rightMargin: 18; top: parent.top; topMargin: 16 }
            spacing: 3
            StyledText {
                text: Translation.tr("Launch options")
                font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Row {
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.status.startsWith("error:") ? "error" : root.busy ? "progress_activity"
                        : root.status === "saved" ? "check_circle" : root.live ? "bolt" : root.changed ? "edit"
                        : root.unreachable ? "extension_off" : "info"
                    iconSize: 16; fill: 1
                    color: stateText.color
                    RotationAnimation on rotation { running: root.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                }
                StyledText {
                    id: stateText
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: root.status.startsWith("error:") ? Appearance.colors.colError
                        : root.status === "saved" ? Appearance.colors.colPrimary
                        : root.unreachable && !root.changed && !root.busy ? Appearance.colors.colError
                        : Appearance.colors.colSubtextGlass
                    text: root.status.startsWith("error:") ? root.status.substring(6)
                        : root.busy ? (root.restartNeeded ? Translation.tr("Restarting Steam…") : Translation.tr("Saving…"))
                        : root.status === "saved" ? Translation.tr("Saved to Steam")
                        : root.live ? Translation.tr("Changes go straight to Steam")
                        : root.changed ? (root.restartNeeded ? Translation.tr("Not saved yet · Steam restarts to apply it") : Translation.tr("Not saved yet"))
                        : root.unreachable ? Translation.tr("Steam's plugin isn't answering, so saving restarts Steam")
                        : root.steamRunning ? Translation.tr("Saving restarts Steam") : Translation.tr("Saved into Steam's settings")
                }
            }
        }
        SheetIconButton {
            id: closeButton
            anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14 }
            grouped: false
            width: 30
            buttonRadius: Appearance.rounding.segment
            iconName: "close"
            tip: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
        RowLayout { // What Steam runs, as you change it, then Undo and Save: one glass piece
            id: commandRow
            anchors { left: banner.coverItem.right; leftMargin: 18; right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 12 }
            height: 36
            spacing: 3
            OptionBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "terminal"
                topLeftRadius: 12; bottomLeftRadius: 12
                topRightRadius: undoButton.visible || saveButton.visible ? root._join : 12
                bottomRightRadius: topRightRadius
                text: root.options
                placeholder: "gamemoderun %command% -novid"
                tip: Translation.tr("What Steam runs. %command% is the game: words before it run it, words after it go to the game")
                onEdited: t => root.options = t
            }
            FooterButton {
                id: undoButton
                visible: root.live ? root.canUndo : root.changed && !root.busy
                last: !saveButton.visible
                symbol: "undo"; label: root.live ? Translation.tr("Undo") : Translation.tr("Revert")
                onClicked: root.live ? root.undo() : root.revert()
            }
            FooterButton {
                id: saveButton
                visible: !root.live
                last: true
                dim: !primary
                primary: root.changed && !root.busy // Lit once there's something to save (save() ignores it otherwise)
                symbol: root.restartNeeded ? "restart_alt" : "save"
                label: root.restartNeeded ? Translation.tr("Save & restart Steam") : Translation.tr("Save")
                onClicked: root.save()
            }
        }
    }

    // What a row says while it's on: MangoHud's layout; gamescope's size (the 16:9 picture's, when it's that), refresh and FSR
    readonly property var mangohudPresets: [
        { value: "", label: Translation.tr("Default") },
        { value: "1", label: Translation.tr("FPS only") },
        { value: "2", label: Translation.tr("Horizontal") },
        { value: "3", label: Translation.tr("Extended") },
        { value: "4", label: Translation.tr("Detailed") }
    ]
    readonly property string mangohudSetting: mangohudPreset === "custom" ? Translation.tr("Your own")
        : mangohudPresets.find(p => p.value === mangohudPreset)?.label ?? ""
    readonly property string scopeSetting: {
        const parts = [];
        if (gameAspect) parts.push(gameAspect);
        else if (scope.W && scope.H) parts.push(`${scope.W}×${scope.H}`);
        if (scope.r) parts.push(`${scope.r} Hz`);
        if (fsrLevel) parts.push("FSR");
        return parts.join(" · ");
    }
    readonly property int _join: Appearance.rounding.joined

    // ── Under the banner: Tools, Proton and Steam, each a well of one-line rows (as the side menus'); the settings of
    //    the tools that are on in a well across under them. Scrolls when gamescope's are out ──
    Flickable {
        id: body
        visible: root.loaded
        anchors { top: banner.bottom; topMargin: 3; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20; bottom: parent.bottom; bottomMargin: 16 }
        contentHeight: bodyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ColumnLayout {
            id: bodyColumn
            width: body.width
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Section {
                    first: true
                    iconName: "build"; title: Translation.tr("Tools")
                    ToolRow {
                        tool: "gamemode"; iconName: "speed"; title: "GameMode"; pkg: "gamemode"
                        description: Translation.tr("Tunes the CPU and GPU while it runs")
                    }
                    ToolRow {
                        tool: "mangohud"; iconName: "monitoring"; title: "MangoHud"; pkg: "mangohud"
                        description: Translation.tr("FPS, frame times and temperatures")
                        setting: root.mangohudSetting
                    }
                    ToolRow {
                        tool: "gamescope"; iconName: "fit_screen"; title: "gamescope"; pkg: "gamescope"
                        description: Translation.tr("A set size and refresh rate, and upscaling")
                        setting: root.scopeSetting
                    }
                }
                Section {
                    iconName: "wine_bar"; title: Translation.tr("Proton")
                    ToolRow { tool: "wayland"; iconName: "web_asset"; title: Translation.tr("Wayland"); description: Translation.tr("Not through Xwayland") }
                    ToolRow { // Not hdr_on: that's a wide "HDR" wordmark, a smudge at this size
                        tool: "hdr"; iconName: "contrast"; title: "HDR"
                        description: root.toolsOn.wayland ? Translation.tr("In games that have it") : Translation.tr("Turns Wayland on with it")
                    }
                    ToolRow {
                        tool: "ntsync"; iconName: "sync"; title: "NTSYNC"
                        description: Translation.tr("Faster game threads, through the kernel")
                        missing: Translation.tr("Needs the kernel's ntsync module")
                    }
                }
                Section { // Which Proton, and when Steam updates it (once it's installed: the mode lives in its appmanifest)
                    visible: root.hasProton || root.autoUpdate >= 0
                    last: true
                    iconName: "cloud"; title: "Steam"
                    MenuRow {
                        visible: root.hasProton
                        iconName: "science"; label: Translation.tr("Version")
                        options: root.protonOptions
                        value: root.proton
                        // A tool Steam has mapped that isn't installed any more: named, so it isn't shown as the default
                        fallbackText: root.proton
                        onSelected: v => root.proton = v
                    }
                    MenuRow {
                        visible: root.autoUpdate >= 0
                        iconName: "update"; label: Translation.tr("Updates")
                        options: root.updateOptions
                        value: root.autoUpdate
                        onSelected: v => root.autoUpdate = v
                    }
                }
            }
            GlassWell { // The settings of the tools that are on
                visible: root.toolsOn.mangohud || root.toolsOn.gamescope
                Layout.fillWidth: true
                implicitHeight: settingsColumn.implicitHeight + 24
                ColumnLayout {
                    id: settingsColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 16 }
                    spacing: 8
                    SettingRow {
                        visible: root.toolsOn.mangohud
                        iconName: "monitoring"; label: Translation.tr("MangoHud layout")
                        Segmented {
                            Layout.fillWidth: true
                            value: root.mangohudPreset
                            options: root.mangohudPresets
                            onPicked: v => root.setMangohudPreset(v)
                        }
                    }
                    SettingRow {
                        visible: root.toolsOn.gamescope
                        iconName: "fit_screen"; label: Translation.tr("Screen")
                        StyledComboBox {
                            Layout.fillWidth: true; Layout.preferredWidth: 4; minimumWidth: 0
                            options: root.sizeOptions
                            value: root.scope.W ? `${root.scope.W}x${root.scope.H}` : ""
                            fallbackText: Translation.tr("Size")
                            onSelected: v => { const [W, H] = v.split("x").map(Number); root.setScope({ W: W, H: H }); }
                        }
                        StyledComboBox {
                            Layout.fillWidth: true; Layout.preferredWidth: 3; minimumWidth: 0
                            options: root.refreshOptions
                            value: root.scope.r
                            fallbackText: Translation.tr("Refresh")
                            onSelected: v => root.setScope({ r: v })
                        }
                        StyledComboBox {
                            Layout.fillWidth: true; Layout.preferredWidth: 4; minimumWidth: 0
                            options: root.modeOptions
                            value: root.scope.mode
                            onSelected: v => root.setScope({ mode: v })
                        }
                    }
                    SettingRow { // The picture's shape (only on a screen wider than 16:9) and the mouse
                        visible: root.toolsOn.gamescope
                        iconName: root.canNarrow ? "aspect_ratio" : "mouse"
                        label: root.canNarrow ? Translation.tr("Picture") : Translation.tr("Mouse")
                        Segmented {
                            visible: root.canNarrow
                            Layout.fillWidth: true; Layout.horizontalStretchFactor: 1 // Halves with the mouse's
                            value: root.gameAspect
                            options: root.aspectOptions
                            onPicked: v => root.setPicture(v, root.fsrLevel)
                        }
                        // gamescope flips the mouse between the desktop's pointer and the game's own movement as the
                        // game hides and shows its cursor: inside Hyprland that made aiming catch. Locked, it's the game's
                        Segmented {
                            Layout.fillWidth: true; Layout.horizontalStretchFactor: 1
                            Layout.leftMargin: root.canNarrow ? 6 : 0
                            value: root.scope.grab ? "grab" : ""
                            options: root.mouseOptions
                            onPicked: v => root.setScope({ grab: v === "grab" })
                        }
                    }
                    SettingRow {
                        visible: root.toolsOn.gamescope
                        iconName: "upscale"; label: Translation.tr("FSR")
                        Segmented {
                            Layout.fillWidth: true
                            value: root.fsrLevel
                            options: root.fsrLevels
                            onPicked: v => root.setPicture(root.gameAspect, v)
                        }
                    }
                    SettingRow {
                        visible: root.toolsOn.gamescope
                        iconName: "flag"; label: Translation.tr("Other flags")
                        OptionBox { // Any other flags, as typed
                            Layout.fillWidth: true
                            implicitHeight: 34
                            followWhileTyping: false
                            text: root.scope.rest.join(" ")
                            placeholder: Translation.tr("Other gamescope flags")
                            onEdited: t => root.setScope({ rest: t.trim().split(/\s+/).filter(x => x) })
                        }
                    }
                }
            }
        }
    }
    Rectangle { // The fine edge light round the banner and the wells as one object
        visible: root.loaded
        x: banner.x; y: banner.y; width: banner.width
        height: Math.min(body.y + bodyColumn.implicitHeight, body.y + body.height) - banner.y
        radius: Appearance.rounding.normal
        color: "transparent"
        border { width: 1; color: ColorUtils.transparentize("white", 0.84) }
    }

    // A column under the banner: its name, then a well of rows. The outer two meet the banner's corners joined
    component Section: GlassWell {
        id: section
        property string iconName
        property string title
        property bool first: false
        property bool last: false
        default property alias rows: sectionRows.data
        Layout.fillWidth: true
        Layout.preferredWidth: 1 // Even widths
        Layout.fillHeight: true // As tall as the tallest
        implicitHeight: sectionRows.implicitHeight + 46
        topLeftRadius: first ? root._join : Appearance.rounding.normal
        topRightRadius: last ? root._join : Appearance.rounding.normal
        Row {
            x: 14; y: 12
            spacing: 8
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: section.iconName; iconSize: 15; fill: 1; color: Appearance.colors.colPrimary }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: section.title
                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold
                color: Appearance.colors.colSubtextGlass
            }
        }
        ColumnLayout {
            id: sectionRows
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 38; leftMargin: 4; rightMargin: 4 }
            spacing: 2
        }
    }

    // A footer piece, joined to the line before it: neutral, or accent (primary: Save, once there's something to save).
    // Not disabled for nothing to save, which would drop its background and leave the footer's end bare
    component FooterButton: RippleButton {
        id: fb
        property string symbol
        property string label
        property bool primary: false
        property bool last: false
        Layout.fillHeight: true
        implicitWidth: fbRow.implicitWidth + 28
        buttonRadiusTopLeft: root._join; buttonRadiusBottomLeft: root._join
        buttonRadiusTopRight: last ? 12 : root._join; buttonRadiusBottomRight: buttonRadiusTopRight
        property bool dim: false // Nothing to do yet: its words in the subtext
        // A glass piece on the banner's art, as the line before it
        colBackground: primary ? Appearance.colors.colPrimary : root.glassOverArt
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : dim ? colBackground
            : root.glassOverArtHover
        colRipple: primary ? Appearance.colors.colPrimaryActive : dim ? "transparent" : Appearance.colors.colLayer3Active
        pointingHandCursor: !dim
        readonly property color fg: primary ? Appearance.colors.colOnPrimary : dim ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer3
        contentItem: Row {
            id: fbRow
            anchors.centerIn: parent; spacing: 6
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: fb.symbol; iconSize: 17; color: fb.fg }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: fb.label; color: fb.fg; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.DemiBold }
        }
    }

    // A tool or Proton switch as a row of its well: its word in front of %command%, switched by a click anywhere on
    // it. The icon on a squircle (the accent while it's on), its name, what's set on the right while it's on, its
    // switch; the description (or, missing, how to get it) in its tooltip. A soft card when pointed at
    component ToolRow: GlassRow {
        id: tile
        property string tool
        property string iconName
        property string title
        property string description
        property string setting: "" // While it's on, on the right
        property string pkg: "" // A program to install (the tools); Proton's switches need none
        property string missing: pkg ? Translation.tr("Not installed: sudo dnf install %1").arg(pkg) : ""
        readonly property bool isOn: root.toolsOn[tool]
        readonly property bool available: pkg ? (root.info?.tools?.[tool] ?? false) : tool === "ntsync" ? (root.info?.ntsync ?? false) : true
        usable: available || isOn // Can always be switched off
        Layout.fillWidth: true
        implicitHeight: 46
        onClicked: if (usable) root.toggle(tool)
        contentItem: RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 12
            IconSquircle {
                icon: tile.iconName
                filled: tile.isOn
                color: tile.isOn ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer4
                iconColor: tile.isOn ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                opacity: tile.usable ? 1 : 0.5
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: tile.title
                font.pixelSize: Appearance.font.pixelSize.small
                color: !tile.usable ? Appearance.colors.colSubtext : tile.isOn ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
            }
            StyledText { // What's set, or that it can't be had
                Layout.maximumWidth: 150
                elide: Text.ElideRight
                visible: text !== ""
                text: !tile.available ? Translation.tr("Not installed") : tile.isOn ? tile.setting : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({})
                color: tile.available ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
            }
            StyledSwitch {
                checked: tile.isOn
                enabled: tile.usable
                scale: 0.85
                onClicked: root.toggle(tile.tool)
            }
        }
        HoverHandler { id: tileHover }
        StyledToolTip { text: tile.available ? tile.description : tile.missing; extraVisibleCondition: tileHover.hovered }
    }

    // A setting in the well under the columns: its icon and name, then its controls (the row's children after them)
    component SettingRow: RowLayout {
        id: settingRow
        property string iconName
        property string label
        Layout.fillWidth: true
        spacing: 6
        MaterialSymbol { Layout.preferredWidth: 22; text: settingRow.iconName; iconSize: 16; color: Appearance.colors.colSubtext }
        StyledText {
            Layout.preferredWidth: 120
            text: settingRow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // A choice as a row of its well: the icon on a squircle, its name, the menu on the right
    component MenuRow: RowLayout {
        id: menuRow
        property string iconName
        property string label
        property alias options: menu.options
        property alias value: menu.value
        property alias fallbackText: menu.fallbackText
        signal selected(var v)
        Layout.fillWidth: true
        Layout.leftMargin: 8; Layout.rightMargin: 4
        implicitHeight: 46
        spacing: 12
        IconSquircle { icon: menuRow.iconName }
        StyledText { text: menuRow.label; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer3 }
        StyledComboBox {
            id: menu
            Layout.fillWidth: true
            minimumWidth: 0
            onSelected: v => menuRow.selected(v)
        }
    }

    // A row of choices, one picked (a value not among them, as "custom", picks none): joined chips, the picked one
    // tinted in the accent
    component Segmented: Item {
        id: seg
        property var options: []
        property string value
        signal picked(string v)
        implicitHeight: 34
        RowLayout {
            anchors.fill: parent
            spacing: 3
            Repeater {
                model: seg.options
                Rectangle {
                    id: segItem
                    required property var modelData
                    required property int index
                    readonly property bool active: seg.value === modelData.value
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    topLeftRadius: 10
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: 10
                    bottomRightRadius: topRightRadius
                    // Glass: straight on the well, the picked one on the accent squircle, a soft card when pointed at
                    color: active ? Appearance.colors.colLayer3Accent
                        : ColorUtils.transparentize(Appearance.colors.colOnLayer3, segMa.containsMouse ? 0.93 : 1)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    StyledText {
                        anchors.centerIn: parent
                        text: segItem.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: segItem.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(segItem.modelData.value)
                    }
                    StyledToolTip { // An option's tip, if it has one
                        extraVisibleCondition: segMa.containsMouse && !!segItem.modelData.tip
                        text: segItem.modelData.tip ?? ""
                    }
                }
            }
        }
    }

    // A one-line box for options, in monospace, an icon before it if it has one, and a tip on hover. Enter saves,
    // Esc closes. followWhileTyping: false for a box whose text comes back rewritten (gamescope's other flags, split
    // into words: a trailing space would go)
    component OptionBox: Rectangle {
        id: box
        property string text
        property string placeholder
        property string icon: ""
        property string tip: ""
        property bool followWhileTyping: true
        signal edited(string text)
        implicitHeight: 42
        radius: 12
        // Glass: a darker field with a fine rim (on the banner: a glass piece), as the launcher's search
        color: root.glassOverArt
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? Appearance.colors.colPrimary : ColorUtils.transparentize("white", 0.9)
        HoverHandler { id: boxHover }
        MaterialSymbol {
            visible: box.icon !== ""
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: box.icon
            iconSize: 17
            color: Appearance.colors.colSubtext
        }
        ToolbarTextField {
            id: field
            anchors { fill: parent; leftMargin: box.icon !== "" ? 34 : 6; rightMargin: 6 }
            colBackground: "transparent"
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            placeholderText: box.placeholder
            onTextEdited: box.edited(text)
            Binding on text { value: box.text; when: box.followWhileTyping || !field.activeFocus }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.saveNow(); event.accepted = true; }
                else if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
            }
        }
        StyledToolTip { text: box.tip; extraVisibleCondition: box.tip !== "" && boxHover.hovered && !field.activeFocus }
    }
}
