import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * Launch drawer: when a game is started from the launcher, a drawer slides out of the middle of the
 * bar (like the volume pop-up): a small banner of the game's hero art and logo, with the steps Steam
 * has been through as a row of ticked squircles, what it's doing right now (updating, cloud sync,
 * processing shaders…, with real progress along the bottom edge where there is a number) and how long
 * it's been. scripts/game-launcher/launch_watch.py follows the launch. Once one of the game's own
 * windows opens (Steam's dialogs and other apps don't count) it slides back at once, ticking
 * "Launched" on the way. It stays up until then, pointer or not. If the game quits before showing a
 * window, or Steam can't start it, it says so with Retry. Stays on the screen it opened on, and never
 * takes keyboard focus.
 * While Steam processes Vulkan shaders it brings its main window up to ask about them: that waits on a hidden
 * workspace instead, and the drawer has Skip (Steam's, through the shell's plugin in Steam).
 * Off in Settings → Launcher (Config.options.gameLauncher.launchAnimation).
 */
Scope {
    id: root
    property var game: null
    property bool shown: false
    property string screenName: "" // The focused monitor when the launch started
    property real launchedAt: 0
    property int elapsed: 0 // Seconds since the launch

    // From launch_watch.py: preparing | updating | setup | cloud | shaders | choose | starting
    // | exited | failed. "window" shows launched, "timeout" just closes the drawer
    property string stage: "starting"
    property real progress: -1 // 0–1, -1 when there's no number
    property string error: ""
    readonly property bool failedState: isFailure(stage)
    readonly property bool canSkip: stage === "shaders" && (game?.id ?? "").startsWith("steam_")
    function isFailure(stage) { return stage === "exited" || stage === "failed"; }
    // Steps already done this launch, oldest first ({ stage }): filled in by the drawer as it shows each one
    property ListModel doneSteps: ListModel {}
    readonly property bool launched: stage === "launched"
    // Games the watcher can't follow (not Steam or Lutris): the first new window that isn't Steam's
    property bool _fallback: false

    function stageText(stage) {
        const pct = root.progress >= 0 ? ` · ${Math.round(root.progress * 100)}%` : "";
        switch (stage) {
        case "preparing": return Translation.tr("Getting ready");
        case "updating": return progress >= 0 ? Translation.tr("Updating") + pct : Translation.tr("Checking for updates");
        case "setup": return Translation.tr("Running first-time setup");
        case "cloud": return Translation.tr("Syncing cloud saves");
        case "shaders": return Translation.tr("Processing shaders") + pct;
        case "choose": return Translation.tr("Pick a launch option in Steam");
        case "exited": return Translation.tr("Closed before its window opened");
        case "failed": return Translation.tr("Steam couldn't start it") + (error ? ` (${error})` : "");
        case "launched": return Translation.tr("Launched");
        default: return elapsed >= 20 ? Translation.tr("Still starting") : Translation.tr("Starting");
        }
    }
    function stageIcon(stage) {
        switch (stage) {
        case "preparing": return "hourglass_top";
        case "updating": return "download";
        case "setup": return "build";
        case "cloud": return "cloud_sync";
        case "shaders": return "memory";
        case "choose": return "list";
        case "exited": case "failed": return "error";
        case "launched": return "check";
        default: return "rocket_launch";
        }
    }
    readonly property string elapsedText: `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, "0")}`

    readonly property var _customArt: game ? GameLauncherService.getCustomArt(game.id) : ({})
    readonly property string coverSource: {
        if ((_customArt.boxArt ?? "").startsWith("/")) return _customArt.boxArt;
        return (game?.boxArt ?? "").startsWith("/") ? game.boxArt : "";
    }
    // The banner: the same art as the details page's, else the cover (blurred)
    readonly property string heroSource: {
        if (!game) return "";
        if ((_customArt.heroArt ?? "").startsWith("/")) return _customArt.heroArt;
        if ((game.heroArt ?? "").startsWith("/")) return game.heroArt;
        if ((game.derivedHeroArt ?? "").length > 0) return game.derivedHeroArt;
        return coverSource;
    }
    readonly property bool heroIsCover: heroSource !== "" && heroSource === coverSource
    readonly property string logoSource: {
        if ((_customArt.logo ?? "").startsWith("/")) return _customArt.logo;
        return (game?.icon ?? "").startsWith("/") ? game.icon : "";
    }

    function _stopAll() {
        watcher.running = false;
        previewStep.stop();
        failTime.stop();
    }
    function dismiss() {
        root.shown = false;
        _stopAll();
        _restoreSteam(root.stage === "launched");
    }
    function start(game) {
        _stopAll();
        root.game = game;
        root.launchedAt = Date.now();
        root.elapsed = 0;
        root.stage = "starting";
        root.progress = -1;
        root.error = "";
        root.doneSteps.clear();
        if (!root.shown) root.screenName = Hyprland.focusedMonitor?.name ?? ""; // A retry stays put
        root.shown = true;
        const id = game?.id ?? "";
        const args = id.startsWith("steam_") ? ["steam", id.substring(6), (GameLauncherService.steamPaths(game)?.manifest ?? "")]
            : id.startsWith("lutris_") ? ["lutris", game.name] : null;
        root._fallback = args === null;
        if (args) {
            watcher.command = ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/launch_watch.py"), ...args];
            watcher.running = true;
        }
    }
    // A made-up launch, to see every state without starting anything (IPC previewSplash).
    // Any query ending in "!" ends on a failure instead of launching
    function preview(game, fail) {
        start(game);
        watcher.running = false;
        root._fallback = false;
        previewStep.fail = fail;
        previewStep.step = 0;
        previewStep.restart();
    }
    // The game's window is up: get out of its way at once, showing the check as the drawer goes
    function _succeed() {
        root.stage = "launched";
        root.progress = 1;
        dismiss();
    }
    function _onStatus(s) {
        if (s.stage === "window") { _succeed(); return; }
        if (s.stage === "timeout") { dismiss(); return; }
        root.stage = s.stage;
        root.progress = s.progress ?? -1;
        root.error = s.error ?? "";
        if (root.failedState) { failTime.restart(); _restoreSteam(false); } // Steam may have more to say
        if (root.stage === "shaders") _hideSteamWindows();
    }

    // ── Steam's window while shaders process ──
    // Steam's main window (class steam, title Steam), as hidden: address → the workspace to put it back on, or
    // "" if it opened during this launch (then it goes back to the tray once the game is up)
    property var _hiddenSteam: ({})
    property var _openedSteam: ({}) // Addresses of the ones that opened during this launch
    readonly property string _hideWorkspace: "special:steamlaunch" // As Steam's "Launching..." dialog's rule
    function _isSteamMain(w) { return w?.class === "steam" && w?.title === "Steam"; }
    function _hideSteam(address, workspace) {
        if (root._hiddenSteam[address] !== undefined) return;
        root._hiddenSteam = Object.assign({}, root._hiddenSteam, { [address]: workspace });
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${root._hideWorkspace}", follow = false, window = "address:${address}" })`);
    }
    function _hideSteamWindows() {
        for (const w of HyprlandData.windowList ?? [])
            if (root._isSteamMain(w) && !w.workspace?.name?.startsWith("special:"))
                root._hideSteam(w.address, root._openedSteam[w.address] ? "" : w.workspace.name);
    }
    // The launch is over (or the drawer gone, Skip with it): Steam's window back, or to the tray if it only
    // opened to ask about shaders and the game is up
    function _restoreSteam(launched) {
        const back = Hyprland.focusedWorkspace?.name ?? "";
        for (const [address, workspace] of Object.entries(root._hiddenSteam)) {
            if (workspace === "" && launched)
                Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${address}" })`); // Steam keeps running
            else
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${workspace || back}", follow = false, window = "address:${address}" })`);
        }
        root._hiddenSteam = ({});
        root._openedSteam = ({});
    }
    Connections {
        target: Hyprland
        enabled: root.shown && !root._fallback
        function onRawEvent(event) { // "openwindow": address,workspace,class,title
            if (event.name !== "openwindow") return;
            const [address, , windowClass, title] = event.data.split(",");
            if (!root._isSteamMain({ class: windowClass, title: title })) return;
            root._openedSteam = Object.assign({}, root._openedSteam, { ["0x" + address]: true });
            if (root.stage === "shaders") root._hideSteam("0x" + address, "");
        }
    }
    function skipShaders() {
        if (skipProc.running || !root.game) return;
        skipProc.command = ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/steam_control.py"), "skip-shaders", root.game.id.substring(6)];
        skipProc.running = true;
    }
    Process {
        id: skipProc
        onExited: exitCode => {
            if (exitCode === 0) return; // The watcher sees the launch move on
            console.warn("[LaunchSplash] Skip didn't reach Steam: its window comes back, with its own Skip");
            root._restoreSteam(false);
        }
    }

    Connections {
        target: GameLauncherService
        function onGameLaunching(game) {
            if (!(Config.options.gameLauncher.launchAnimation ?? true)) return;
            root.start(game);
        }
    }
    Process {
        id: watcher
        stdout: SplitParser {
            onRead: line => {
                let s;
                try { s = JSON.parse(line); } catch (e) { return; }
                root._onStatus(s);
            }
        }
    }
    Connections { // Fallback for games the watcher can't follow
        target: Hyprland
        enabled: root.shown && root._fallback
        function onRawEvent(event) {
            if (event.name !== "openwindow" || Date.now() - root.launchedAt < 400) return;
            const windowClass = (event.data.split(",")[2] ?? "").toLowerCase();
            if (windowClass === "steam" || windowClass === "steamwebhelper") return;
            root._succeed();
        }
    }
    Timer { // The fallback has no other way to know: give up after a while
        interval: 30000
        running: root.shown && root._fallback
        onTriggered: root.dismiss()
    }
    Timer { // A failure stays up long enough to read and retry, and while the pointer is on it
        id: failTime
        interval: 12000
        onTriggered: hoverArea.hovered ? restart() : root.dismiss()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.shown && !root.failedState && !root.launched
        onTriggered: root.elapsed = Math.round((Date.now() - root.launchedAt) / 1000)
    }
    Timer {
        id: previewStep
        property int step: 0
        property bool fail: false
        readonly property var steps: [
            { stage: "preparing", progress: -1 }, { stage: "updating", progress: 0.2 }, { stage: "updating", progress: 0.65 },
            { stage: "cloud", progress: -1 }, { stage: "shaders", progress: 0.1 }, { stage: "shaders", progress: 0.94 },
            { stage: "starting", progress: -1 }
        ]
        interval: 1400
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (step >= steps.length) {
                stop();
                root._onStatus({ stage: fail ? "exited" : "window" });
                return;
            }
            root._onStatus(steps[step++]);
        }
    }

    PanelWindow {
        id: drawer
        readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
        readonly property real padding: 10
        readonly property real bottomRadius: 26
        readonly property real hiddenExtra: 60
        readonly property real barBottom: GlobalStates.drawerTopOn(screen) // Below the bar, or near the top without one
        readonly property real panelWidth: card.width + padding * 2
        readonly property real fullHeight: card.height + padding * 2

        // 0 = out, 1 = tucked under the bar
        readonly property bool opening: root.shown && readiness.ready
        property real offsetScale: opening ? 0 : 1
        Behavior on offsetScale {
            NumberAnimation {
                duration: root.shown ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shown ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
        readonly property real drawerY: Math.min(0, drawerTop)
        readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
        readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

        // Entrance: the banner settles, then the logo, the steps and the progress line arrive in turn
        property real entrance: 1
        onOpeningChanged: if (opening) { entrance = 0; entranceAnim.restart(); }
        NumberAnimation {
            id: entranceAnim
            target: drawer; property: "entrance"
            from: 0; to: 1
            duration: 800
        }
        // 0–1 for a part that starts `delay` into the entrance, eased out
        function reveal(delay) {
            const t = Math.max(0, Math.min(1, (entrance - delay) / 0.5));
            return 1 - Math.pow(1 - t, 3);
        }

        // The step on screen: follows root.stage, but swaps with a slide while the drawer is out.
        // The step it replaces joins the ticked ones (not the "starting" every launch begins on)
        property string shownStage: "starting"
        readonly property bool shownFailed: root.isFailure(shownStage)
        property real swapOpacity: 1
        property real swapShift: 0
        function applyStage(stage) {
            const prev = drawer.shownStage;
            drawer.shownStage = stage;
            if (prev === stage || root.isFailure(prev) || root.isFailure(stage)) return;
            for (let i = root.doneSteps.count - 1; i >= 0; i--) // Back to a step from before: it isn't done
                if (root.doneSteps.get(i).stage === stage) root.doneSteps.remove(i);
            let seen = false;
            for (let i = 0; i < root.doneSteps.count; i++) seen = seen || root.doneSteps.get(i).stage === prev;
            if (prev !== "starting" && !seen) root.doneSteps.append({ stage: prev });
        }
        Connections {
            target: root
            function onStageChanged() {
                const launched = root.stage === "launched"; // The drawer is already on its way out: no slide
                if (drawer.visible && drawer.offsetScale <= 0.5 && !launched) {
                    swapAnim.restart();
                    return;
                }
                swapAnim.stop();
                drawer.swapOpacity = 1;
                drawer.swapShift = 0;
                drawer.applyStage(root.stage);
                if (launched) chipPop.restart();
            }
        }
        SequentialAnimation {
            id: swapAnim
            ParallelAnimation {
                NumberAnimation { target: drawer; property: "swapOpacity"; to: 0; duration: 120; easing.type: Easing.InCubic }
                NumberAnimation { target: drawer; property: "swapShift"; to: -6; duration: 120; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: {
                    drawer.applyStage(root.stage);
                    drawer.swapShift = 6;
                }
            }
            ParallelAnimation {
                NumberAnimation { target: drawer; property: "swapOpacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: drawer; property: "swapShift"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }

        visible: root.shown || offsetScale < 1 // Stay mapped while retracting
        screen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
        color: "transparent"
        WlrLayershell.namespace: "quickshell:launchSplash"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // Never take the game's input
        anchors.top: true // Horizontally centred
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins.top: barBottom // Directly below the bar, which skips its border here (BarJoin)
        implicitWidth: panelWidth + sideMargin * 2
        implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
        mask: Region { item: maskArea }

        Item {
            id: maskArea
            x: drawer.sideMargin
            width: drawer.panelWidth
            height: drawer.visibleHeight
            HoverHandler { id: hoverArea } // A failure stays while the pointer is on it
        }

        Item {
            id: stageArea
            anchors.fill: parent
            clip: true

            DrawerReadiness {
                id: readiness
                active: drawer.visible
            }
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                name: "launchSplash"
                active: drawer.visible && drawer.visibleHeight > 0
                joinX: ((drawer.screen?.width ?? 0) - drawer.implicitWidth) / 2 + drawer.sideMargin
                joinWidth: drawer.panelWidth
            }
            DrawerBackground {
                followBar: true // A card while there's no bar (a fullscreen game)
                id: background
                anchors.fill: parent
                active: drawer.visible
                drawerX: drawer.sideMargin
                drawerY: drawer.drawerY
                drawerWidth: drawer.panelWidth
                drawerHeight: drawer.drawerHeight
                drawerRadius: Math.min(drawer.bottomRadius, drawer.visibleHeight / 2)
                fallbackRadius: drawer.bottomRadius
            }

            ClippingRectangle {
                id: card
                x: drawer.sideMargin + drawer.padding
                y: drawer.drawerY + drawer.padding
                width: 520
                height: 140
                radius: drawer.bottomRadius - drawer.padding
                color: Appearance.colors.colLayer1
                opacity: 1 - drawer.offsetScale
                transform: Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob

                Image { // The banner: settles from a slight zoom, then drifts slowly side to side
                    id: hero
                    property real loaded: status === Image.Ready ? 1 : 0
                    Behavior on loaded { NumberAnimation { duration: 350 } }
                    width: parent.width * 1.12
                    height: parent.height * 1.12
                    y: (parent.height - height) / 2
                    source: root.heroSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: root.heroIsCover ? 240 : Math.ceil(width * Screen.devicePixelRatio) // A cover gets blurred: small is fine
                    visible: status === Image.Ready
                    opacity: loaded * drawer.reveal(0)
                    scale: 1 + 0.1 * (1 - drawer.reveal(0))
                    layer.enabled: visible && root.heroIsCover // A cover stretched this wide only works blurred
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 32
                        saturation: 0.35
                    }
                    SequentialAnimation on x {
                        running: drawer.visible && hero.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: card.width - hero.width; duration: 10000; easing.type: Easing.InOutSine }
                        NumberAnimation { from: card.width - hero.width; to: 0; duration: 10000; easing.type: Easing.InOutSine }
                    }
                }
                // Shade so the logo and steps read on any art (the background colour can be translucent:
                // made solid here): darker at the bottom and on the left, where they sit
                Rectangle {
                    id: scrim
                    anchors.fill: parent
                    readonly property color base: Appearance.m3colors.m3background
                    function shade(a) { return Qt.rgba(base.r, base.g, base.b, a); }
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: scrim.shade(0.2) }
                        GradientStop { position: 0.5; color: scrim.shade(0.45) }
                        GradientStop { position: 1.0; color: scrim.shade(0.9) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: scrim.shade(0.55) }
                        GradientStop { position: 0.6; color: scrim.shade(0) }
                    }
                }

                Item { // Logo, else the name, with a soft shadow to stand out from the art
                    id: logoArea
                    x: 20; y: 16
                    width: 240; height: 58
                    opacity: drawer.reveal(0.15)
                    transform: Translate { y: 8 * (1 - drawer.reveal(0.15)) }
                    layer.enabled: drawer.visible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: scrim.base
                        shadowBlur: 0.6
                        shadowOpacity: 0.7
                    }
                    Image {
                        id: logo
                        anchors.fill: parent
                        source: root.logoSource
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignLeft
                        verticalAlignment: Image.AlignVCenter
                        asynchronous: true
                        sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
                        visible: status === Image.Ready
                    }
                    StyledText {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: !logo.visible
                        text: root.game?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                }

                Item { // Steps done, the one now, and the time. Or what went wrong, with Retry / Dismiss
                    id: stepsArea
                    anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 14 }
                    height: 34
                    opacity: drawer.reveal(0.3)
                    transform: Translate { y: 8 * (1 - drawer.reveal(0.3)) }

                    Row {
                        id: stepsRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater { // Ticked steps: the step's icon on a dark squircle with an accent edge
                            model: root.doneSteps
                            delegate: Rectangle {
                                required property string stage
                                visible: !drawer.shownFailed // Room for what went wrong
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22
                                radius: 7
                                color: scrim.shade(0.7)
                                border.width: 1
                                border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.stageIcon(stage)
                                    iconSize: 14
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                        add: Transition {
                            NumberAnimation { property: "scale"; from: 0.4; to: 1; duration: 300; easing.type: Easing.OutBack }
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                        }
                        move: Transition {
                            NumberAnimation { properties: "x"; duration: 280; easing.type: Easing.OutCubic }
                        }

                        Rectangle { // The step now: solid accent squircle (red on a failure)
                            id: chip
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26
                            radius: 8
                            color: drawer.shownFailed ? Appearance.colors.colError : Appearance.colors.colPrimary
                            Behavior on color { ColorAnimation { duration: 200 } }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.stageIcon(drawer.shownStage)
                                iconSize: 17
                                fill: 1
                                color: drawer.shownFailed ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
                                opacity: drawer.swapOpacity
                            }
                            SequentialAnimation {
                                id: chipPop
                                NumberAnimation { target: chip; property: "scale"; to: 1.25; duration: 140; easing.type: Easing.OutCubic }
                                NumberAnimation { target: chip; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
                            }
                        }
                        StyledText {
                            leftPadding: 2
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: drawer.swapShift
                            width: Math.min(implicitWidth, stepsArea.width - x - (drawer.shownFailed ? failButtons.width : elapsedRow.width) - 12)
                            text: root.stageText(drawer.shownStage)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: drawer.shownFailed ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                            opacity: drawer.swapOpacity
                            elide: Text.ElideRight
                        }
                    }

                    Row { // Skip while shaders process, then the time
                        id: elapsedRow
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        DialogButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.canSkip && drawer.shownStage === "shaders"
                            enabled: !skipProc.running
                            buttonText: Translation.tr("Skip")
                            onClicked: root.skipShaders()
                            StyledToolTip { text: Translation.tr("Start now and build shaders while you play") }
                        }
                        StyledText {
                            id: elapsedLabel
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: drawer.shownFailed || drawer.shownStage === "launched" ? 0 : 0.75
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            text: root.elapsedText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    Row {
                        id: failButtons
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        enabled: drawer.shownFailed
                        opacity: drawer.shownFailed ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        DialogButton {
                            buttonText: Translation.tr("Retry")
                            primary: true
                            onClicked: GameLauncherService.launchGame(root.game, GameLauncherService.lastLaunchOption[root.game?.id] ?? -1)
                        }
                        DialogButton {
                            buttonText: Translation.tr("Dismiss")
                            onClicked: root.dismiss()
                        }
                    }
                }

                Item { // Progress along the bottom edge: real when Steam gives a number, else a shimmer
                    id: track
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 3
                    // Fades out on a failure (animated apart from the entrance, which moves every frame)
                    property real shown: drawer.shownFailed ? 0 : 1
                    Behavior on shown { NumberAnimation { duration: 200 } }
                    opacity: shown * drawer.reveal(0.4)
                    Rectangle {
                        anchors.fill: parent
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
                    }
                    Rectangle {
                        width: track.width * Math.max(0, root.progress)
                        height: track.height
                        color: Appearance.colors.colPrimary
                        opacity: root.progress >= 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        id: shimmer
                        width: track.width * 0.3; height: track.height
                        radius: 1.5
                        color: Appearance.colors.colPrimary
                        opacity: root.progress < 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        NumberAnimation on x {
                            running: drawer.visible && track.shown > 0 && shimmer.opacity > 0
                            loops: Animation.Infinite
                            from: -shimmer.width; to: track.width
                            duration: 1500
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }
    }
}
