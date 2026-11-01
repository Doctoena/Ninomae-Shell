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
 * bar (like the volume pop-up): a card over the game's blurred hero art with its cover, what Steam is
 * doing right now (updating, cloud sync, processing shaders…, with real progress where there is a
 * number) and how long it's been. scripts/game-launcher/launch_watch.py follows the launch, and the
 * drawer slides back once one of the game's own windows opens (Steam's dialogs and other apps don't
 * count) or when the pointer touches it. If the game quits before showing a window, or Steam can't
 * start it, it says so with Retry. Never takes keyboard focus.
 * Off in Settings → Launcher (Config.options.gameLauncher.launchAnimation).
 */
Scope {
    id: root
    property var game: null
    property bool shown: false
    property real launchedAt: 0
    property int elapsed: 0 // Seconds since the launch

    // From launch_watch.py: preparing | updating | setup | cloud | shaders | choose | starting
    // | exited | failed. "window" and "timeout" just close the drawer
    property string stage: "starting"
    property real progress: -1 // 0–1, -1 when there's no number
    property string error: ""
    readonly property bool failedState: stage === "exited" || stage === "failed"
    // Games the watcher can't follow (not Steam or Lutris): the first new window that isn't Steam's
    property bool _fallback: false

    readonly property string stageText: {
        const pct = root.progress >= 0 ? ` · ${Math.round(root.progress * 100)}%` : "";
        switch (root.stage) {
        case "preparing": return Translation.tr("Getting ready");
        case "updating": return progress >= 0 ? Translation.tr("Updating") + pct : Translation.tr("Checking for updates");
        case "setup": return Translation.tr("Running first-time setup");
        case "cloud": return Translation.tr("Syncing cloud saves");
        case "shaders": return Translation.tr("Processing shaders") + pct;
        case "choose": return Translation.tr("Pick a launch option in Steam");
        case "exited": return Translation.tr("Closed before its window opened");
        case "failed": return Translation.tr("Steam couldn't start it") + (error ? ` (${error})` : "");
        default: return elapsed >= 20 ? Translation.tr("Still starting") : Translation.tr("Starting");
        }
    }
    readonly property string elapsedText: `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, "0")}`

    readonly property var _customArt: game ? GameLauncherService.getCustomArt(game.id) : ({})
    readonly property string coverSource: {
        if ((_customArt.boxArt ?? "").startsWith("/")) return _customArt.boxArt;
        return (game?.boxArt ?? "").startsWith("/") ? game.boxArt : "";
    }
    // Behind the card, blurred: the same art as the details page's banner, else the cover
    readonly property string heroSource: {
        if (!game) return "";
        if ((_customArt.heroArt ?? "").startsWith("/")) return _customArt.heroArt;
        if ((game.heroArt ?? "").startsWith("/")) return game.heroArt;
        if ((game.derivedHeroArt ?? "").length > 0) return game.derivedHeroArt;
        return coverSource;
    }

    function dismiss() {
        root.shown = false;
        watcher.running = false;
        previewStep.stop();
        failTime.stop();
    }
    function start(game) {
        watcher.running = false;
        previewStep.stop();
        failTime.stop();
        root.game = game;
        root.launchedAt = Date.now();
        root.elapsed = 0;
        root.stage = "starting";
        root.progress = -1;
        root.error = "";
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
    // A made-up launch, to see every state without starting anything (IPC previewSplash)
    function preview(game) {
        start(game);
        watcher.running = false;
        root._fallback = false;
        previewStep.step = 0;
        previewStep.restart();
    }
    function _onStatus(line) {
        let s;
        try { s = JSON.parse(line); } catch (e) { return; }
        if (s.stage === "window" || s.stage === "timeout") { dismiss(); return; }
        root.stage = s.stage;
        root.progress = s.progress ?? -1;
        root.error = s.error ?? "";
        if (root.failedState) failTime.restart();
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
        stdout: SplitParser { onRead: line => root._onStatus(line) }
    }
    Connections { // Fallback for games the watcher can't follow
        target: Hyprland
        enabled: root.shown && root._fallback
        function onRawEvent(event) {
            if (event.name !== "openwindow" || Date.now() - root.launchedAt < 400) return;
            const windowClass = (event.data.split(",")[2] ?? "").toLowerCase();
            if (windowClass === "steam" || windowClass === "steamwebhelper") return;
            root.dismiss();
        }
    }
    Timer { // The fallback has no other way to know: give up after a while
        interval: 30000
        running: root.shown && root._fallback
        onTriggered: root.dismiss()
    }
    Timer { // A failure stays up long enough to read and retry
        id: failTime
        interval: 12000
        onTriggered: root.dismiss()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.shown && !root.failedState
        onTriggered: root.elapsed = Math.round((Date.now() - root.launchedAt) / 1000)
    }
    Timer {
        id: previewStep
        property int step: 0
        readonly property var steps: [
            { stage: "preparing", progress: -1 }, { stage: "updating", progress: 0.2 }, { stage: "updating", progress: 0.65 },
            { stage: "cloud", progress: -1 }, { stage: "shaders", progress: 0.1 }, { stage: "shaders", progress: 0.94 },
            { stage: "starting", progress: -1 }, { stage: "exited", progress: -1 }
        ]
        interval: 1400
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._onStatus(JSON.stringify(steps[step]));
            if (++step >= steps.length) stop();
        }
    }

    PanelWindow {
        id: drawer
        readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
        readonly property real padding: 10
        readonly property real bottomRadius: 26
        readonly property real hiddenExtra: 60
        readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        readonly property real panelWidth: card.width + padding * 2
        readonly property real fullHeight: card.height + padding * 2

        // 0 = out, 1 = tucked under the bar
        property real offsetScale: (root.shown && readiness.ready) ? 0 : 1
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

        visible: root.shown || offsetScale < 1 // Stay mapped while retracting
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
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
            MouseArea { // Get out of the way when the pointer goes there (not on a failure: it has buttons)
                anchors.fill: parent
                hoverEnabled: true
                onEntered: if (!root.failedState) root.dismiss()
            }
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
                width: 460
                height: 108
                radius: drawer.bottomRadius - drawer.padding
                color: Appearance.colors.colLayer1
                opacity: 1 - drawer.offsetScale
                transform: Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob

                Image { // Blurred hero art
                    anchors.fill: parent
                    source: root.heroSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 240 // Half size: it's blurred anyway, and that's cheaper to blur
                    visible: status === Image.Ready
                    layer.enabled: visible
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 32
                        saturation: 0.4
                    }
                }
                Rectangle { // Keeps the text readable on any art: darker behind the text, lighter on the right
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.15) }
                        GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.7) }
                    }
                }

                Rectangle { // Cover
                    id: cover
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 60; height: 80
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    layer.enabled: true
                    layer.effect: RoundedMask { radius: cover.radius }
                    Image {
                        anchors.fill: parent
                        source: root.coverSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 120
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.coverSource === ""
                        text: "sports_esports"
                        iconSize: 26
                        color: Appearance.colors.colPrimary
                    }
                }

                Column {
                    anchors { left: cover.right; leftMargin: 16; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Item { // What's happening, and for how long
                        width: parent.width
                        height: stageLabel.implicitHeight
                        Row {
                            spacing: 5
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.failedState
                                text: "error"
                                iconSize: 15
                                color: Appearance.colors.colError
                            }
                            StyledText {
                                id: stageLabel
                                width: Math.min(implicitWidth, parent.parent.width - elapsedLabel.width - 12)
                                text: root.stageText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.failedState ? Appearance.colors.colError : Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                        StyledText {
                            id: elapsedLabel
                            anchors.right: parent.right
                            visible: !root.failedState
                            text: root.elapsedText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        width: parent.width
                        text: root.game?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                    }
                    Item { // Progress, or Retry / Dismiss after a failure
                        width: parent.width
                        height: 34
                        Rectangle {
                            id: track
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            visible: !root.failedState
                            height: 4; radius: 2
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
                            clip: true
                            Rectangle { // Real progress, when Steam gives a number
                                visible: root.progress >= 0
                                width: track.width * Math.max(0, root.progress)
                                height: track.height; radius: track.radius
                                color: Appearance.colors.colPrimary
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                            Rectangle { // Otherwise a shimmer
                                id: shimmer
                                visible: root.progress < 0
                                width: track.width * 0.3; height: track.height; radius: track.radius
                                color: Appearance.colors.colPrimary
                                NumberAnimation on x {
                                    running: drawer.visible && shimmer.visible
                                    loops: Animation.Infinite
                                    from: -shimmer.width; to: track.width
                                    duration: 1300
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.failedState
                            spacing: 8
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
                }
            }
        }
    }
}
