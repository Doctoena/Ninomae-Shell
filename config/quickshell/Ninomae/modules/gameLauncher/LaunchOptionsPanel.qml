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
 * On top, an art banner (ArtBanner, the game's logo) with how saving works, the Proton and Updates menus
 * (Updates once it's installed: the mode lives in the game's appmanifest) and close. Under it on the left, the
 * tools: GameMode, MangoHud and gamescope switch their word in front of %command% (MangoHud with a layout, as
 * MANGOHUD_CONFIG=preset=N; gamescope with its screen, refresh rate, mode and FSR upscaling, and any other
 * flags). On the right, the whole line as Steam holds it, and Proton's switches (Wayland, HDR, NTSYNC), each
 * a variable in front of it.
 * With the shell's Millennium plugin in Steam (themes/steam/ninomae-plugin) every change goes straight to
 * Steam as it's made (typing, after a pause), and Undo puts back what it was on opening. Without it Steam
 * rewrites its settings when it quits, so there's a Save, which closes and restarts Steam while it's open.
 * Keys: Enter in a box saves, Esc closes.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1160
    panelHeight: 600
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
        const g = { W: 0, H: 0, w: 0, h: 0, r: 0, mode: "", filter: "", rest: [] };
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
            else g.rest.push(a);
        }
        return g;
    }
    function setScope(change) {
        const g = Object.assign(parseGamescope(parsed.gamescope), change);
        // FSR keeps its share of the output as the output changes
        if (change.W && g.filter === "fsr" && scope.W) { const k = scope.w / scope.W; g.w = Math.round(g.W * k); g.h = Math.round(g.H * k); }
        const out = [];
        if (g.mode === "fullscreen") out.push("-f"); else if (g.mode === "borderless") out.push("-b");
        if (g.W && g.H) out.push("-W", g.W, "-H", g.H);
        if (g.w && g.h) out.push("-w", g.w, "-h", g.h);
        if (g.r) out.push("-r", g.r);
        if (g.filter) out.push("-F", g.filter);
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
    readonly property string fsrLevel: {
        if (scope.filter !== "fsr" || !scope.w || !scope.W) return "";
        const k = scope.w / scope.W;
        return fsrLevels.slice(1).reduce((best, l) => Math.abs(l.value - k) < Math.abs(best.value - k) ? l : best).value;
    }
    function setFsr(level) {
        const W = scope.W || (info?.monitors?.[0]?.width ?? 0), H = scope.H || (info?.monitors?.[0]?.height ?? 0);
        if (level === "") setScope({ w: 0, h: 0, filter: "" });
        else setScope({ W: W, H: H, w: Math.round(W * level), h: Math.round(H * level), filter: "fsr" });
    }
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
        if (!live) return;
        autoSave.stop();
        save();
    }
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
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && changed) { autoSave.stop(); save(); return true; }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the panel
    }

    SheetEmptyState { // Reading, or couldn't
        anchors.centerIn: parent
        visible: !root.loaded
        icon: root.status.startsWith("error:") ? "error" : "hourglass_empty"
        text: root.status.startsWith("error:") ? root.status.substring(6) : Translation.tr("Reading Steam's settings…")
    }

    // ── Banner: the game, how saving works (and how it's going), Proton and Updates, close ──
    ArtBanner {
        id: banner
        visible: root.loaded
        game: root.game
        showLogo: true
        coverIcon: "tune"
        shadeMid: 0.8; shadeEnd: 0.7 // The menus sit on its right
        anchors { top: parent.top; topMargin: 12; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        height: 96
        Column {
            anchors { left: banner.coverItem.right; leftMargin: 18; right: bannerMenus.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
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
                        : root.status === "saved" ? "check_circle" : root.live ? "bolt" : root.changed ? "edit" : "info"
                    iconSize: 16; fill: 1
                    color: stateText.color
                    RotationAnimation on rotation { running: root.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                }
                StyledText {
                    id: stateText
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.status.startsWith("error:") ? Appearance.colors.colError
                        : root.status === "saved" ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
                    text: root.status.startsWith("error:") ? root.status.substring(6)
                        : root.busy ? (root.restartNeeded ? Translation.tr("Restarting Steam…") : Translation.tr("Saving…"))
                        : root.status === "saved" ? Translation.tr("Saved to Steam")
                        : root.live ? Translation.tr("Changes go straight to Steam")
                        : root.changed ? (root.restartNeeded ? Translation.tr("Not saved yet · Steam restarts to apply it") : Translation.tr("Not saved yet"))
                        : root.steamRunning ? Translation.tr("Saving restarts Steam") : Translation.tr("Saved into Steam's settings")
                }
            }
        }
        RowLayout {
            id: bannerMenus
            anchors { right: closeButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 10
            SettingMenu {
                visible: root.hasProton
                Layout.preferredWidth: 200
                label: Translation.tr("Proton")
                options: root.protonOptions
                value: root.proton
                // A tool Steam has mapped that isn't installed any more: named, so it isn't shown as the default
                fallbackText: root.proton
                onSelected: v => root.proton = v
            }
            SettingMenu {
                visible: root.autoUpdate >= 0
                Layout.preferredWidth: 200
                label: Translation.tr("Updates")
                options: root.updateOptions
                value: root.autoUpdate
                onSelected: v => root.autoUpdate = v
            }
        }
        SheetIconButton { // As far in from the right edge as the logo is from the left
            id: closeButton
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            grouped: false
            width: 30
            buttonRadius: Appearance.rounding.segment
            iconName: "close"
            tip: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
    }

    // ── Left: the tools (scrolls when gamescope's controls and MangoHud's layouts are both out) ──
    Flickable {
        id: toolsScroll
        visible: root.loaded
        anchors { top: banner.bottom; topMargin: 14; left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 16 }
        width: 500
        contentHeight: toolsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ColumnLayout {
            id: toolsColumn
            width: toolsScroll.width
            spacing: 3 // Rows join into a group, as Settings'
            SectionLabel { Layout.bottomMargin: 5; text: Translation.tr("Tools") }
            ToolCard {
                tool: "gamemode"; iconName: "speed"; title: "GameMode"; pkg: "gamemode"
                description: Translation.tr("Tunes the CPU and GPU for games while it runs")
            }
            ToolCard {
                tool: "mangohud"; iconName: "monitoring"; title: "MangoHud"; pkg: "mangohud"
                description: Translation.tr("FPS, frame times and temperatures over the game")
                // What it shows, while it's on
                extra: Segmented {
                    value: root.mangohudPreset
                    options: [
                        { value: "", label: Translation.tr("Default") },
                        { value: "1", label: Translation.tr("FPS only") },
                        { value: "2", label: Translation.tr("Horizontal") },
                        { value: "3", label: Translation.tr("Extended") },
                        { value: "4", label: Translation.tr("Detailed") }
                    ]
                    onPicked: v => root.setMangohudPreset(v)
                }
            }
            ToolCard {
                tool: "gamescope"; iconName: "fit_screen"; title: "gamescope"; pkg: "gamescope"
                description: Translation.tr("A set resolution and refresh rate, and upscaling")
                // Its controls, while it's on
                extra: ColumnLayout {
                    spacing: 8
                    RowLayout {
                        spacing: 8
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
                    Segmented { // FSR upscaling
                        Layout.fillWidth: true
                        value: root.fsrLevel
                        options: root.fsrLevels
                        onPicked: v => root.setFsr(v)
                    }
                    OptionBox { // Any other flags, as typed
                        Layout.fillWidth: true
                        implicitHeight: 36
                        followWhileTyping: false
                        text: root.scope.rest.join(" ")
                        placeholder: Translation.tr("Other gamescope flags")
                        onEdited: t => root.setScope({ rest: t.trim().split(/\s+/).filter(x => x) })
                    }
                }
            }
        }
    }

    // ── Right: the whole line, and Proton's switches ──
    ColumnLayout {
        visible: root.loaded
        anchors { top: banner.bottom; topMargin: 14; left: toolsScroll.right; leftMargin: 20; right: parent.right; rightMargin: 20 }
        spacing: 3 // Rows join into a group, as Settings'
        SectionLabel { Layout.bottomMargin: 5; text: Translation.tr("Launch line") }
        Rectangle { // The whole line, and what it means, in a card of its own
            Layout.fillWidth: true
            implicitHeight: launchLine.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3
            ColumnLayout {
                id: launchLine
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: 8
                OptionBox {
                    Layout.fillWidth: true
                    text: root.options
                    placeholder: "gamemoderun %command% -novid"
                    onEdited: t => root.options = t
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6; Layout.rightMargin: 6; Layout.bottomMargin: 2
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: Translation.tr("As Steam has it. <tt>%command%</tt> is the game: words before it run it, words after it go to the game.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
        SectionLabel { Layout.topMargin: 14; Layout.bottomMargin: 5; text: Translation.tr("Proton (for games it runs)") }
        ToolCard {
            tool: "wayland"; iconName: "web_asset"; title: Translation.tr("Wayland")
            description: Translation.tr("Draws straight on Wayland, not through Xwayland")
        }
        ToolCard {
            tool: "hdr"; iconName: "hdr_on"; title: "HDR"
            description: Translation.tr("HDR in games that have it (with Wayland)")
        }
        ToolCard {
            tool: "ntsync"; iconName: "sync"; title: "NTSYNC"
            description: Translation.tr("Faster game threads, through the kernel")
            missing: Translation.tr("Needs the kernel's ntsync module")
        }
    }

    // ── Under the right side: Undo, and Save without the plugin (the tools keep the left down to the bottom) ──
    RowLayout {
        id: footer
        visible: root.loaded
        anchors { left: toolsScroll.right; right: parent.right; bottom: parent.bottom; leftMargin: 20; rightMargin: 20; bottomMargin: 16 }
        height: 32
        spacing: 6
        Item { Layout.fillWidth: true }
        FooterButton {
            visible: root.live ? root.canUndo : root.changed && !root.busy
            symbol: "undo"; label: root.live ? Translation.tr("Undo") : Translation.tr("Revert")
            onClicked: root.live ? root.undo() : root.revert()
        }
        FooterButton {
            id: saveButton
            visible: !root.live
            primary: true
            enabled: root.changed && !root.busy
            symbol: root.restartNeeded ? "restart_alt" : "save"
            label: root.restartNeeded ? Translation.tr("Save & restart Steam") : Translation.tr("Save")
            onClicked: root.save()
        }
    }

    // A column's small heading
    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    // A footer button: neutral, or accent (Save)
    component FooterButton: RippleButton {
        id: fb
        property string symbol
        property string label
        property bool primary: false
        implicitHeight: 32
        implicitWidth: fbRow.implicitWidth + 24
        buttonRadius: Appearance.rounding.segment
        colBackground: primary && enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
        readonly property color fg: primary ? (enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext) : Appearance.colors.colOnLayer1
        contentItem: Row {
            id: fbRow
            anchors.centerIn: parent; spacing: 5
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: fb.symbol; iconSize: 16; color: fb.fg }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: fb.label; color: fb.fg; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium }
        }
    }

    // A tool or switch: what it does, and a switch for its word in front of %command%. Missing: how to get it.
    // `extra` shows under it while it's on (MangoHud's layouts, gamescope's controls)
    component ToolCard: Rectangle {
        id: card
        property string tool
        property string iconName
        property string title
        property string description
        property string pkg: "" // A program to install (the tools); Proton's switches need none
        property string missing: pkg ? Translation.tr("Not installed: <tt>sudo dnf install %1</tt>").arg(pkg) : ""
        property Component extra: null
        readonly property bool isOn: root.toolsOn[tool]
        readonly property bool available: pkg ? (root.info?.tools?.[tool] ?? false) : tool === "ntsync" ? (root.info?.ntsync ?? false) : true
        readonly property bool usable: available || isOn // Can always be switched off
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 20
        // Cards next to each other join into a group (rounded at its ends), as Settings' rows
        readonly property bool settingsRow: true
        GroupCorners { id: corners; item: card }
        topLeftRadius: corners.top
        topRightRadius: corners.top
        bottomLeftRadius: corners.bottom
        bottomRightRadius: corners.bottom
        color: cardMa.containsMouse && usable ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        clip: true
        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: card.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (card.usable) root.toggle(card.tool)
        }
        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    implicitWidth: 34; implicitHeight: 34
                    radius: 9
                    // On: an accent-tinted square (as the game page's facts); off: a neutral one
                    color: card.isOn ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer4
                    Behavior on color { ColorAnimation { duration: 120 } }
                    opacity: card.usable ? 1 : 0.5
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.iconName
                        iconSize: 19
                        fill: card.isOn ? 1 : 0
                        color: card.isOn ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: card.title
                        font.weight: Font.DemiBold
                        color: card.usable ? Appearance.colors.colOnLayer3 : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: card.available ? card.description : card.missing
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledSwitch {
                    checked: card.isOn
                    enabled: card.usable
                    onClicked: root.toggle(card.tool)
                }
            }
            Loader {
                Layout.fillWidth: true
                active: card.isOn && card.extra !== null
                visible: active
                sourceComponent: card.extra
            }
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
                    topLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.joined
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: index === seg.options.length - 1 ? Appearance.rounding.small : Appearance.rounding.joined
                    bottomRightRadius: topRightRadius
                    color: active ? Appearance.colors.colLayer3Accent
                        : segMa.containsMouse ? Appearance.colors.colLayer4Hover : Appearance.colors.colLayer4
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
                }
            }
        }
    }

    // A one-line box for options, in monospace. Enter saves, Esc closes. followWhileTyping: false for a box whose
    // text comes back rewritten (gamescope's other flags, split into words: a trailing space would go)
    component OptionBox: Rectangle {
        id: box
        property string text
        property string placeholder
        property bool followWhileTyping: true
        signal edited(string text)
        implicitHeight: 42
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer4
        border.width: field.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
        ToolbarTextField {
            id: field
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            colBackground: "transparent"
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            placeholderText: box.placeholder
            onTextEdited: box.edited(text)
            Binding on text { value: box.text; when: box.followWhileTyping || !field.activeFocus }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { autoSave.stop(); root.save(); event.accepted = true; }
                else if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
            }
        }
    }

    // A labelled dropdown
    component SettingMenu: ColumnLayout {
        id: settingMenu
        property string label
        property alias options: menu.options
        property alias value: menu.value
        property alias fallbackText: menu.fallbackText
        signal selected(var v)
        spacing: 4
        SectionLabel { text: settingMenu.label; color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3) }
        StyledComboBox {
            id: menu
            Layout.fillWidth: true
            minimumWidth: 0
            onSelected: v => settingMenu.selected(v)
        }
    }
}
