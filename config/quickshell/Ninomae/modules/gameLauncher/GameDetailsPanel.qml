import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
    id: root
    required property var game
    signal backPressed()
    signal playPressed(var game, int option) // option: one of its Steam launch options (launchChoices), or -1
    focus: true
    property bool animationReady: false
    // Live install state (GameLauncherService.installState), and download progress 0–1 (-1 = unknown)
    readonly property string installState: {
        const _ = GameLauncherService.games; // Re-evaluate when the game list is re-detected
        return GameLauncherService.installState(game);
    }
    readonly property bool _downloading: installState === "installing" || installState === "updating"
    readonly property bool _paused: installState === "updatePaused" // Still shows how far it got
    property real downloadProgress: -1
    // Workshop mods downloading for an installed game (GameLauncherService.workshopDownloading)
    readonly property bool _modsOnly: !_downloading && installState === "installed" && !!GameLauncherService.workshopDownloading[game?.id]
    // What's downloading, if anything: progress starts over when this changes (not on a pause)
    readonly property string _downloadPhase: _downloading || _paused ? "game" : _modsOnly ? "mods" : ""
    on_DownloadPhaseChanged: { downloadProgress = -1; _manifestProgress = -1; _bytesToStage = 0; }
    // Steam only rewrites the manifest's byte counts on state changes (start, pause, finish), so it
    // gives the totals (a Workshop job's too), and the live part is the data written so far under
    // steamapps/downloading/<id> or workshop/downloads/<id>
    property real _manifestProgress: -1
    property real _bytesToStage: 0
    function _updateProgress(staged) {
        const disk = root._bytesToStage > 0 && staged >= 0 ? Math.min(1, staged / root._bytesToStage) : -1;
        // Never step back: Steam moves finished files out of the download folder while it commits
        root.downloadProgress = Math.max(root.downloadProgress, root._manifestProgress, disk);
    }
    FileView { // Polled only while a download is running
        id: manifestFile
        path: root._downloadPhase !== "" ? (GameLauncherService.steamPaths(root.game)?.manifest ?? "") : ""
        printErrors: false
        onLoaded: {
            const t = text();
            const num = k => Number((t.match(new RegExp(`"${k}"\\s+"(\\d+)"`)) ?? [])[1] ?? 0);
            const toStage = num("BytesToStage") || num("BytesToDownload");
            // New totals (the Workshop job replacing the game's): the old progress doesn't apply
            if (toStage !== root._bytesToStage) root.downloadProgress = -1;
            root._bytesToStage = toStage;
            // A Workshop job never fills in the counts; leftovers from the game's download would mislead
            const total = num("BytesToDownload") + num("BytesToStage");
            root._manifestProgress = root._downloadPhase === "game" && total > 0
                ? Math.min(1, (num("BytesDownloaded") + num("BytesStaged")) / total) : -1;
            root._updateProgress(-1);
        }
    }
    Process { // Allocated bytes, not apparent size: Steam writes the files sparsely
        id: stagedSizeProc
        command: ["du", "-sc", "--block-size=1", ...(GameLauncherService.steamPaths(root.game)?.downloads ?? [])]
        stdout: StdioCollector {
            onStreamFinished: { // Last line is the total (a folder that doesn't exist yet just adds nothing)
                const lines = text.trim().split("\n");
                const bytes = parseInt(lines[lines.length - 1]);
                if (!isNaN(bytes)) root._updateProgress(bytes);
            }
        }
    }
    Timer {
        interval: root._paused ? 10000 : 1500 // Paused: only Steam resuming it changes anything
        running: root._downloadPhase !== "" && root.visible && manifestFile.path !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            manifestFile.reload();
            if (!stagedSizeProc.running) stagedSizeProc.running = true;
        }
    }
    // Custom art overrides — reactively track changes
    readonly property var customArtData: {
        const _ = GameLauncherService.customArtRevision;
        return game ? GameLauncherService.getCustomArt(game.id) : {};
    }
    readonly property string customHeroArt: customArtData.heroArt || ""
    readonly property string customLogo: customArtData.logo || ""
    // Particle override — reactively track changes
    readonly property string particleOverride: {
        const _ = GameLauncherService.particleOverridesRevision;
        return game ? GameLauncherService.getParticleOverride(game.id) : "";
    }
    readonly property string _bannerSource: {
        if (customHeroArt.length > 0 && customHeroArt.startsWith("/")) return customHeroArt;
        if (game?.heroArt?.length > 0 && game.heroArt.startsWith("/")) return game.heroArt;
        if (game?.derivedHeroArt?.length > 0) return game.derivedHeroArt;
        return "";
    }
    readonly property string _logoSource: {
        if (customLogo.length > 0 && customLogo.startsWith("/")) return customLogo;
        if (game?.icon?.length > 0 && game.icon.startsWith("/")) return game.icon;
        return "";
    }
    // Cached sidebar buttons for keyboard nav (avoids re-scanning on every keypress)
    property var _cachedSidebarButtons: []
    function _refreshSidebarButtons() {
        const btns = [];
        for (let i = 0; i < sidebarRepeater.count; i++) {
            const item = sidebarRepeater.itemAt(i);
            if (item?.visible) btns.push(item);
        }
        _cachedSidebarButtons = btns;
    }
    function _sidebarButtons() { return _cachedSidebarButtons; }
    function _currentSidebarIndex() {
        const btns = _cachedSidebarButtons;
        for (let i = 0; i < btns.length; i++) {
            if (btns[i].activeFocus) return i;
        }
        return -1;
    }
    // The launcher builds a game's page ahead, hidden, while its tile is hovered (shown: false), so a click
    // shows it at once. Hidden, it loads its pictures and plays its entrance (banner, logo) out of sight, so
    // it comes in whole with the launcher's own fade; the keys and the fetches wait until it arrives
    property bool shown: true
    property bool _arrived: false
    signal arrived()
    function _arrive() {
        if (root._arrived || !root.shown) return;
        root._arrived = true;
        root.forceActiveFocus();
        _updateLastPlayedText();
        GameLauncherService.fetchPlayerCount(game);
        if (game?.id?.startsWith("steam_")) {
            GameLauncherService.fetchMetadata(game);
            GameLauncherService.loadNews(game); // For the News button's unread count (cached an hour)
        } else if (game?.id?.startsWith("lutris_")) GameLauncherService.fetchLutrisMetadata(game);
        root.arrived();
    }
    Component.onCompleted: { animationResetTimer.start(); _arrive(); }
    onShownChanged: _arrive()
    onGameChanged: if (_arrived) GameLauncherService.fetchPlayerCount(game)
    // "3 days ago": for the Updated chip
    function _ago(ms) {
        const m = Math.floor((Date.now() - ms) / 60000);
        if (m < 60) return Translation.tr("just now");
        if (m < 1440) return Math.floor(m / 60) === 1 ? Translation.tr("an hour ago") : Translation.tr("%1 hours ago").arg(Math.floor(m / 60));
        const d = Math.floor(m / 1440);
        return d === 1 ? Translation.tr("yesterday") : Translation.tr("%1 days ago").arg(d);
    }
    // Memoized last-played text — refreshes every 60s instead of every frame
    property string _lastPlayedText: ""
    function _updateLastPlayedText() {
        if (!game?.lastPlayed || game.lastPlayed === 0) { _lastPlayedText = ""; return; }
        const now = Date.now();
        const lastMs = game.lastPlayed < 1e12 ? game.lastPlayed * 1000 : game.lastPlayed;
        const diff = now - lastMs;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(diff / 3600000);
        const days = Math.floor(diff / 86400000);
        if (minutes < 1) { _lastPlayedText = "Just now"; return; }
        if (minutes < 60) { _lastPlayedText = minutes + " min ago"; return; }
        if (hours < 24) { _lastPlayedText = hours + " hour" + (hours > 1 ? "s" : "") + " ago"; return; }
        if (days === 1) { _lastPlayedText = "Yesterday"; return; }
        if (days < 7) { _lastPlayedText = days + " days ago"; return; }
        if (days < 30) { const w = Math.floor(days / 7); _lastPlayedText = w + " week" + (w > 1 ? "s" : "") + " ago"; return; }
        const m = Math.floor(days / 30); _lastPlayedText = m + " month" + (m > 1 ? "s" : "") + " ago";
    }
    Timer { interval: 60000; running: root.visible && root.animationReady; repeat: true; onTriggered: _updateLastPlayedText() }
    Timer {
        id: animationResetTimer
        interval: 50
        repeat: false
        onTriggered: root.animationReady = true
    }
    Keys.onPressed: event => {
        if (root.openPanel !== "" && root.topPanelItem?.handleKey(event.key, event.modifiers)) {
            event.accepted = true;
            return;
        }
        const btns = root._sidebarButtons();
        const idx = root._currentSidebarIndex();
        if (event.key === Qt.Key_Escape) {
            if (moreMenu.open || tagMenuPopup.open) {
                moreMenu.open = false;
                tagMenuPopup.open = false;
            } else {
                root.backPressed();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            if (playButton.activeFocus) {
                // From play → first sidebar button
                if (btns.length > 0) btns[0].forceActiveFocus();
            } else if (idx >= 0 && idx < btns.length - 1) {
                // Move down through sidebar buttons
                btns[idx + 1].forceActiveFocus();
            } else {
                // Nothing focused → focus play
                playButton.forceActiveFocus();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            if (idx === 0) {
                // First sidebar button → play
                playButton.forceActiveFocus();
            } else if (idx > 0) {
                // Move up through sidebar buttons
                btns[idx - 1].forceActiveFocus();
            } else {
                playButton.forceActiveFocus();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            root.backPressed();
            event.accepted = true;
        }
    }
    // Fixed rounded frame for the banner: only the picture inside zooms, so the frame edges and the
    // fade behind the menu stay put next to the sidebar instead of sliding in under it
    Item {
        id: bannerFrame
        anchors { fill: parent; margins: 16 }
        z: 0
        opacity: (bannerImage.status === Image.Ready && root.animationReady) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.effect: RoundedMask { maskWidth: bannerFrame.width; maskHeight: bannerFrame.height; radius: Appearance.rounding.normal }
        Image {
            id: bannerImage
            anchors.fill: parent
            source: root._bannerSource
            cache: false
            fillMode: Image.PreserveAspectCrop
            // Decoded near the frame's width, not at 3840×1240 (~19 MB). Width only, in 256 px steps: any new
            // sourceSize decodes it again (Loading: the frame fades out), and the frame's height eases a pixel
            // at a time as the page settles, which made the art flicker. A hero is wider than the frame's
            // shape, so cropped it still covers the frame at full sharpness
            sourceSize.width: Math.ceil(bannerFrame.width * Screen.devicePixelRatio / 256) * 256
            asynchronous: true
            // Slow settle from a slight zoom, no overshoot
            scale: (status === Image.Ready && root.animationReady) ? 1.0 : 1.04
            Behavior on scale { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        }
        // The fades are in the panel's colour: dark shading in dark mode, but in light mode the same
        // amounts would wash the art out white, so there they stay light past the menu's edge
        readonly property bool _light: !Appearance.m3colors.darkmode
        Rectangle { // Fade into the panel behind the menu on the left, keep the art visible on the right
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.05) }
                GradientStop { position: 0.28; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 0.5 : 0.25) }
                GradientStop { position: 0.6; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 0.95 : 0.75) }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 0.95 : 0.6) }
            }
        }
        Rectangle { // Slight shading at the bottom
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.4
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 0.9 : 0.5) }
            }
        }
    }
    Item {
        id: particleContainer
        anchors { fill: parent; margins: 16 }
        z: 1
        layer.enabled: root.animationReady && root._arrived
        layer.effect: RoundedMask { maskWidth: particleContainer.width; maskHeight: particleContainer.height; radius: Appearance.rounding.normal }
        Loader {
            anchors.fill: parent
            // Every game gets an effect: auto-detected, or the preset picked with the ✦ button ("None" turns it off)
            active: root.animationReady && root._arrived && root.particleOverride !== "none" // Not for a page built ahead
            asynchronous: true
            sourceComponent: GameParticles {
                anchors.fill: parent
                gameId: root.game ? (root.game.id || "") : ""
                // Its strength, from the Customize panel's Effect tab
                readonly property var tweak: { const _ = GameLauncherService.particleTweaksRevision; return GameLauncherService.getParticleTweak(gameId); }
                densityScale: tweak.density
                opacityScale: tweak.opacity
                gameName: root.game ? (root.game.name || "") : ""
                imageSource: {
                    if (bannerImage.source && bannerImage.source.toString() !== "") return bannerImage.source.toString();
                    if (root.game?.boxArt?.length > 0 && root.game.boxArt.startsWith("/")) return root.game.boxArt;
                    if (root.game?.icon?.length > 0 && root.game.icon.startsWith("/")) return root.game.icon;
                    return "";
                }
                active: true
            }
        }
    }
    // The logo waits for the banner behind it: a logo is small and decodes almost at once, a Steam hero
    // (3840×1240) takes a moment, so on their own the logo popped in over an empty panel first. No banner,
    // or one that failed: the logo doesn't wait
    readonly property bool _bannerSettled: root._bannerSource === "" || bannerImage.status === Image.Ready || bannerImage.status === Image.Error
    Image {
        id: logoImage
        readonly property bool shown: status === Image.Ready && root.animationReady && root._bannerSettled
        anchors.centerIn: parent
        readonly property real aspectRatio: sourceSize.width > 0 ? sourceSize.width / sourceSize.height : 1.0
        width: Math.min(parent.width * 0.5, 650)
        height: aspectRatio > 2.5 ? Math.min(parent.height * 0.35, 160)
             : aspectRatio > 1.5  ? Math.min(parent.height * 0.45, 200)
             :                      Math.min(parent.height * 0.5, 250)
        source: root._logoSource
        cache: false
        fillMode: Image.PreserveAspectFit; asynchronous: true
        visible: status === Image.Ready
        opacity: shown ? 1.0 : 0.0
        scale: shown ? 1.0 : 0.96
        z: 2
        transform: Translate {
            y: logoImage.shown ? 0 : 6
            Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
    }
    MaterialSymbol {
        anchors.centerIn: parent
        text: "videogame_asset"
        iconSize: 64
        color: Appearance.colors.colOnSurfaceVariant
        visible: (root._bannerSource === "" && root._logoSource === "")
              || (bannerImage.status === Image.Error && logoImage.status === Image.Error)
        z: 2
    }
    Rectangle {
        id: sidebarPanel
        anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: 16; bottom: parent.bottom; bottomMargin: 16 }
        width: sidebarContent.width + 28
        color: "transparent"; z: 5
        // Base fill behind the Play button and menu: the drawer's own colour, rounded where it
        // meets the banner's rounded left edge, so it reads as part of the panel. Pushed 1px past the
        // banner on the outer edges so the banner's antialiased corner can't show through as a thin arc
        Rectangle {
            anchors { fill: parent; leftMargin: -1; topMargin: -1; bottomMargin: -1 }
            color: Appearance.m3colors.m3background
            topLeftRadius: Appearance.rounding.normal
            bottomLeftRadius: Appearance.rounding.normal
        }
    }
    // What a Lutris game runs with, for the stats pill and the info drawer
    readonly property string _runnerLabel: {
        if (!(game?.id?.startsWith("lutris_") ?? false)) return "";
        if (game.flatpakId) return "Flatpak";
        const names = { "linux": "Native Linux", "wine": "Wine", "steam": "Steam", "dosbox": "DOSBox",
                        "libretro": "RetroArch", "scummvm": "ScummVM", "web": "Browser", "flatpak": "Flatpak" };
        const r = game.runner || "";
        return names[r] ?? (r ? r.charAt(0).toUpperCase() + r.slice(1) : "");
    }
    readonly property bool _runsNatively: game?.runner === "linux" || !!game?.flatpakId
    // ─── Stats pill (top-right): status · ProtonDB · playtime · playing now, in the panel's own style; its
    // drawer (hover) has last played, install size and where it's from ───
    readonly property var _stats: {
        if (!game) return [];
        const out = [];
        if (root._runnerLabel !== "")
            out.push({ icon: root._runsNatively ? "terminal" : "wine_bar", label: Translation.tr("Runs on"), value: root._runnerLabel, accent: Appearance.colors.colPrimary });
        const st = root.installState;
        const pct = root.downloadProgress >= 0 ? ` ${Math.floor(root.downloadProgress * 100)}%` : "";
        if (GameClips.gameId === game.id) // Running now
            out.push({ icon: "sports_esports", label: Translation.tr("Status"), value: Translation.tr("Playing"), accent: Appearance.colors.colPrimary });
        else if (st === "installing")
            out.push({ icon: "download", label: Translation.tr("Status"), value: Translation.tr("Installing") + pct, accent: Appearance.colors.colTertiary });
        else if (st === "updating")
            out.push({ icon: "downloading", label: Translation.tr("Status"), value: Translation.tr("Updating") + pct, accent: Appearance.colors.colTertiary });
        else if (st === "updateRequired")
            out.push({ icon: "downloading", label: Translation.tr("Status"), value: Translation.tr("Update ready"), accent: Appearance.colors.colTertiary });
        else if (st === "updatePaused")
            out.push({ icon: "pause_circle", label: Translation.tr("Status"), value: Translation.tr("Update paused") + pct, accent: Appearance.colors.colTertiary });
        else if (st === "uninstalling")
            out.push({ icon: "delete", label: Translation.tr("Status"), value: Translation.tr("Uninstalling"), accent: Appearance.colors.colError });
        else if (root._modsOnly)
            out.push({ icon: "extension", label: Translation.tr("Status"), value: Translation.tr("Downloading mods") + pct, accent: Appearance.colors.colTertiary });
        else if (st === "installed" && GameLauncherService.updatedSincePlayed(game)) // Patched since you last played
            out.push({ icon: "new_releases", label: Translation.tr("Updated"), value: root._ago(game.lastUpdated * 1000), accent: Appearance.colors.colTertiary });

        const tier = game.protondbTier || "";
        if (tier !== "") {
            const tierColors = { "platinum": "#b4c7dc", "gold": "#cfb53b", "silver": "#a6a6a6", "bronze": "#cd7f32", "borked": "#ff4444", "native": "#5cb85c" };
            out.push({ icon: "science", label: "ProtonDB", value: tier.charAt(0).toUpperCase() + tier.slice(1),
                       accent: ColorUtils.mix(tierColors[tier] || Appearance.colors.colPrimary, Appearance.colors.colPrimary, 0.45) });
        }
        if (game.playtime > 0) {
            const h = Math.floor(game.playtime / 60);
            out.push({ icon: "timer", label: Translation.tr("Played"), value: h > 0 ? h + (h === 1 ? " hour" : " hours") : "< 1 hour", accent: Appearance.colors.colPrimary });
        }
        // Players in it right now (Steam's count; not for games it doesn't count)
        const players = GameLauncherService.playerCount(game); // Re-read as the counts come in (the binding sees playerCounts)
        if (players > 0)
            out.push({ icon: "group", label: Translation.tr("Playing now"), value: String(players).replace(/\B(?=(\d{3})+(?!\d))/g, ","), accent: Appearance.colors.colPrimary });
        return out;
    }
    Rectangle {
        id: infoCard
        anchors { right: parent.right; rightMargin: 30; top: parent.top; topMargin: 30 }
        // Grows while the drawer is out so the drawer (which must fit under the flat edge) has room for its values
        width: Math.max(statsRow.implicitWidth + 8, root.statsHovered ? root._statsCardNeededW + 2 * (radius + root._statsJoin + 4) : 0)
        Behavior on width {
            NumberAnimation {
                duration: root.statsHovered ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.statsHovered ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        height: 42
        radius: height / 3
        color: Appearance.m3colors.m3background
        visible: root._stats.length > 0
        z: 10
        opacity: root.animationReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        HoverHandler { id: statsPillHover; onHoveredChanged: root._syncStatsHover() }
        Row {
            id: statsRow
            anchors.centerIn: parent
            Repeater {
                model: root._stats
                Row {
                    required property var modelData
                    required property int index
                    height: 42
                    Rectangle { // Divider between stats
                        visible: index > 0
                        width: 1; height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.88)
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 5; rightPadding: 11
                        spacing: 8
                        Rectangle {
                            width: 26; height: 26; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            color: ColorUtils.transparentize(modelData.accent, 0.82)
                            MaterialSymbol { anchors.centerIn: parent; text: modelData.icon; iconSize: 14; fill: 1; color: modelData.accent }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            StyledText { text: modelData.label; font.pixelSize: 9; color: Appearance.colors.colSubtext }
                            StyledText { text: modelData.value; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                        }
                    }
                }
            }
        }
    }
    // ─── Stats hover card: drops down from the stats pill with more detail ───
    property bool statsHovered: false
    function _syncStatsHover() {
        if (statsPillHover.hovered || statsCardHover.hovered) { statsCloseTimer.stop(); statsHovered = true; }
        else statsCloseTimer.restart();
    }
    Timer { id: statsCloseTimer; interval: 250; onTriggered: root.statsHovered = statsPillHover.hovered || statsCardHover.hovered }
    function _fmtBytes(b) {
        const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return (i >= 3 ? b.toFixed(1) : Math.round(b)) + " " + u[i];
    }
    property string _installSize: ""
    property string _installSizeFor: ""
    // Installed: measured on disk, with its Workshop mods. Not installed (Steam): what it would take,
    // from Steam's own app cache
    readonly property bool _sizeFromSteam: !(game?.gameDir) && (game?.id?.startsWith("steam_") ?? false)
    onStatsHoveredChanged: {
        // Re-measured once something changes what's on disk: an install, an update or mods coming in
        const key = game ? [game.id, game.gameDir || "", installState, root._modsOnly].join("|") : "";
        if (!statsHovered || !game || _installSizeFor === key) return;
        if (game.gameDir) {
            _installSizeFor = key; _installSize = "…";
            sizeProc.modsDir = GameLauncherService.steamPaths(game)?.mods ?? "";
            sizeProc.command = ["du", "-sb", game.gameDir, ...(sizeProc.modsDir ? [sizeProc.modsDir] : [])];
            sizeProc.running = true;
        } else if (_sizeFromSteam) {
            _installSizeFor = key; _installSize = "…";
            steamSizeProc.command = ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/steam_install_size.py"), game.id.substring(6)];
            steamSizeProc.running = true;
        }
    }
    Process {
        id: sizeProc
        property string modsDir: ""
        stdout: StdioCollector {
            onStreamFinished: { // "<bytes>\t<path>" per folder; no mods folder just means no line for it
                let game = NaN, mods = 0;
                for (const line of text.trim().split("\n")) {
                    const tab = line.indexOf("\t");
                    const b = parseInt(line);
                    if (tab < 0 || isNaN(b)) continue;
                    if (sizeProc.modsDir !== "" && line.substring(tab + 1) === sizeProc.modsDir) mods = b;
                    else game = b;
                }
                root._installSize = isNaN(game) ? ""
                    : root._fmtBytes(game + mods) + (mods > 0 ? "  ·  " + root._fmtBytes(mods) + " " + Translation.tr("mods") : "");
            }
        }
    }
    Process {
        id: steamSizeProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}; try { r = JSON.parse(text); } catch (e) {}
                root._installSize = r.size ? root._fmtBytes(r.size) + (r.download ? "  ·  " + root._fmtBytes(r.download) + " " + Translation.tr("download") : "") : "";
            }
        }
    }
    readonly property var _extraStats: {
        if (!game) return [];
        const rows = [];
        if (root._lastPlayedText !== "")
            rows.push({ icon: "history", label: Translation.tr("Last played"), value: root._lastPlayedText });
        if (game.gameDir || root._sizeFromSteam)
            rows.push({ icon: "hard_drive", label: root._sizeFromSteam ? Translation.tr("Download size") : Translation.tr("Install size"),
                        value: root._installSize || "…" });
        const src = game.id.startsWith("steam_") ? "Steam" : game.id.startsWith("lutris_") ? "Lutris"
            : game.source === "Custom" ? Translation.tr("Added by you") : (game.source || "");
        if (src) rows.push({ icon: "storefront", label: Translation.tr("From"), value: src });
        return rows;
    }
    // Drawer that slides down out of the pill's bottom edge (same blob animation as the bar drawers)
    // Keep the drawer (plus its gooey joins) under the pill's flat bottom edge, clear of the rounded
    // ends, so the pill keeps its shape while the drawer is out
    readonly property real _statsJoin: 10
    readonly property real _statsCardW: infoCard.width - 2 * (infoCard.radius + _statsJoin + 4)
    // Width the drawer needs to show every value in full (icon + label column + widest value + margins), capped
    readonly property real _statsCardNeededW: Math.min(420, 15 + 78 + 16 + _statsValueMeasure.implicitWidth + 28 + 2)
    Column { // Invisible measure of the widest drawer value
        id: _statsValueMeasure
        visible: false
        Repeater {
            model: root._extraStats
            StyledText { required property var modelData; text: modelData.value; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Medium }
        }
    }
    readonly property real _statsCardH: statsCol.implicitHeight + 24
    property real _statsOffset: root.statsHovered ? 0 : 1 // 0 = out, 1 = tucked in
    Behavior on _statsOffset {
        NumberAnimation {
            duration: root.statsHovered ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.statsHovered ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
        }
    }
    readonly property real _statsTop: -(_statsCardH + 60) * _statsOffset
    readonly property real _statsY: Math.min(0, _statsTop)
    readonly property real _statsLen: _statsCardH + Math.max(0, _statsTop)
    readonly property real _statsShown: Math.max(0, _statsY + _statsLen)
    Item {
        id: statsStage
        // Starts at the pill's top: the blob's stand-in is an exact copy of the pill (hidden behind
        // it), so the gooey joins follow the pill's rounded shape instead of a flat bar
        anchors { horizontalCenter: infoCard.horizontalCenter; top: infoCard.top }
        width: infoCard.width
        height: infoCard.height + root._statsCardH * 1.12 + 20
        clip: true
        z: 9
        visible: infoCard.visible && root._extraStats.length > 0 && root._statsOffset < 1
        Loader {
            anchors.fill: parent
            active: statsStage.visible
            source: Qt.resolvedUrl("../overview/BlobDrawerBackground.qml")
            onLoaded: {
                item.barBottom = Qt.binding(() => infoCard.height);
                // Copy of the pill inset by 4px (bottom edge kept) so its corners never peek out
                // around the real pill and change its roundness while the drawer is open
                item.barHeight = Qt.binding(() => infoCard.height - 4);
                item.barRadius = Qt.binding(() => infoCard.radius - 4);
                item.barX = 4;
                item.barWidth = Qt.binding(() => statsStage.width - 8);
                item.fillColor = Appearance.m3colors.m3background;
                item.fillOpacity = 1.0;
                item.smoothing = root._statsJoin;
                item.drawerX = Qt.binding(() => (statsStage.width - root._statsCardW) / 2);
                item.drawerY = Qt.binding(() => infoCard.height + root._statsY);
                item.drawerWidth = Qt.binding(() => root._statsCardW);
                item.drawerHeight = Qt.binding(() => root._statsLen);
                item.drawerRadius = Qt.binding(() => Math.min(Appearance.rounding.large, root._statsShown / 2));
            }
        }
        Item {
            id: statsCard
            x: (statsStage.width - width) / 2
            y: infoCard.height + root._statsY // Slides with the drawer
            width: root._statsCardW
            height: root._statsCardH
            opacity: 1 - root._statsOffset
            HoverHandler { id: statsCardHover; onHoveredChanged: root._syncStatsHover() }
            Column {
                id: statsCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 12 }
                spacing: 2
                Repeater {
                    model: root._extraStats
                    Row {
                        required property var modelData
                        height: 28; spacing: 8
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; iconSize: 15; color: Appearance.colors.colPrimary }
                        StyledText { anchors.verticalCenter: parent.verticalCenter; width: 78; text: modelData.label; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: statsCol.width - 15 - 78 - 16
                            text: modelData.value
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
            }
        }
    }
    Item { // Back button, top-left
        anchors { left: parent.left; top: parent.top; leftMargin: 30; topMargin: 28 }
        width: 36; height: 36; z: 10
        RippleButton {
            id: backButton
            anchors.fill: parent
            width: 36
            height: 36
            buttonRadius: 12
            padding: 0
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
            colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.7)
            buttonColor: (hovered || activeFocus) ? colBackgroundHover : colBackground
            opacity: hovered || activeFocus ? 1.0 : 0.7
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            contentItem: Item {
                implicitWidth: 36; implicitHeight: 36
                MaterialSymbol {
                    anchors.centerIn: parent; text: "arrow_back"; iconSize: 20
                    color: Appearance.colors.colOnLayer0
                }
            }
            onClicked: { root.backPressed(); focus = false; }
            StyledToolTip { text: Translation.tr("Back") }
        }
    }
    Row { // Game actions, laid out under the Play button (slot reserved in sidebarContent)
        id: topLeftButtons
        x: sidebarContent.x + actionRowSlot.x + (actionRowSlot.width - width) / 2
        y: sidebarContent.y + actionRowSlot.y + (actionRowSlot.height - height) / 2
        spacing: 14; z: 11
        ToggleIcon {
            iconName: "star"
            on: { const _ = GameLauncherService.favoritesRevision; return !!game && GameLauncherService.isFavorite(game.id); }
            tip: on ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
            onFlipped: GameLauncherService.toggleFavorite(game.id)
        }
        ToggleIcon {
            iconName: "check_circle"
            on: { const _ = GameLauncherService.completedGamesRevision; return !!game && GameLauncherService.isCompleted(game.id); }
            tip: on ? Translation.tr("Remove from completed") : Translation.tr("Mark as completed")
            onFlipped: GameLauncherService.toggleCompleted(game)
        }
        // --- Tag button with popup menu ---
        RippleButton {
            id: tagIconBtn
            width: 36; height: 36
            buttonRadius: 12; padding: 0
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
            colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.7)
            buttonColor: (hovered || activeFocus || tagMenuPopup.open) ? colBackgroundHover : colBackground
            property var gameTags: {
                const _ = GameLauncherService.tagsRevision;
                return game ? GameLauncherService.getGameTags(game.id) : [];
            }
            property bool hasTags: gameTags.length > 0
            opacity: (hovered || activeFocus || hasTags || tagMenuPopup.open) ? 1.0 : 0.7
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            contentItem: Item {
                implicitWidth: 36; implicitHeight: 36
                MaterialSymbol {
                    anchors.centerIn: parent; text: "sell"; iconSize: 20
                    fill: tagIconBtn.hasTags ? 1 : 0
                    color: tagIconBtn.hasTags ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    Behavior on fill { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
            onClicked: { tagMenuPopup.open = !tagMenuPopup.open; if (tagMenuPopup.open) tagInputField.forceActiveFocus(); else focus = false; }
            StyledToolTip { text: Translation.tr("Tags"); visible: !tagMenuPopup.open && tagIconBtn.hovered }
        }
        ToggleIcon { // The crosshair overlay in this game (services/Crosshair.qml)
            readonly property var games: Config.options.crosshair?.games ?? []
            iconName: "my_location"
            on: !!game && games.indexOf(game.id) >= 0
            tip: on ? Translation.tr("Crosshair on in this game") : Translation.tr("Turn on the crosshair in this game")
            onFlipped: Config.options.crosshair.games = on ? games.filter(id => id !== game.id) : [...games, game.id]
        }
        // --- More: less-used actions in a small labelled menu ---
        RippleButton {
            id: moreBtn
            width: 36; height: 36; buttonRadius: 12; padding: 0
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
            colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.7)
            buttonColor: (hovered || moreMenu.open) ? colBackgroundHover : colBackground
            opacity: (hovered || moreMenu.open) ? 1.0 : 0.7
            contentItem: Item {
                implicitWidth: 36; implicitHeight: 36
                MaterialSymbol { anchors.centerIn: parent; text: "more_horiz"; iconSize: 22; color: moreMenu.open ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0 }
            }
            onClicked: moreMenu.open = !moreMenu.open
        }
    }
    // ── Side menus (⋯ and tags): slide out of the left menu's right edge, level with their button ──
    // The ⋯, tags and install-where menus and the info pane: one at a time
    function _sideMenuOpened(menu) {
        root.metadataPaneOpen = false;
        for (const m of [moreMenu, tagMenuPopup, libraryMenu, launchMenu]) if (m !== menu) m.open = false;
    }
    onMetadataPaneOpenChanged: if (metadataPaneOpen) { moreMenu.open = false; tagMenuPopup.open = false; libraryMenu.open = false; launchMenu.open = false; }
    SideDrawer {
        id: moreMenu
        paneW: 260 // Same as the tags menu; room for Uninstall's confirm note
        paneH: moreCol.implicitHeight + 16
        anchorCenterY: topLeftButtons.y + moreBtn.y + moreBtn.height / 2
        opener: moreBtn; exclusive: true
        Column {
            id: moreCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2
            MoreItem {
                iconName: "folder_open"; label: Translation.tr("Open game folder")
                visible: game && (game.gameDir || "") !== ""
                onTriggered: Quickshell.execDetached(["xdg-open", game.gameDir])
            }
            MoreItem {
                iconName: "tune"; label: Translation.tr("Launch options")
                visible: game?.id?.startsWith("steam_") ?? false
                onTriggered: { moreMenu.open = false; root.openPanel = "launchOptions"; }
            }
            MoreItem { // The game's art and particle effect: a panel out of the launcher's top (CustomizePanel)
                iconName: "palette"; label: Translation.tr("Customize")
                onTriggered: { moreMenu.open = false; root.openPanel = "customize"; }
            }
            Rectangle {
                visible: uninstallItem.visible || removeItem.visible
                width: parent.width - 24; x: 12; height: 1
                color: Appearance.m3colors.m3surfaceContainerHighest
            }
            MoreItem {
                // Asks here instead of in Steam: the first click arms it, a second one uninstalls. Steam games
                // go without opening Steam (it restarts in the tray if it's open); Lutris still asks itself
                id: uninstallItem
                property bool armed: false
                property bool steamOpen: false
                readonly property bool isSteam: (game?.source ?? "").toLowerCase() === "steam"
                // Mid-install it cancels it: the same uninstall stops the download (Steam closes first) and
                // deletes what's been downloaded
                readonly property bool cancels: root.installState === "installing"
                iconName: cancels ? "cancel" : "delete_forever"
                label: armed ? Translation.tr("Click to confirm") : cancels ? Translation.tr("Cancel install") : Translation.tr("Uninstall")
                detail: !armed || !isSteam ? ""
                    : cancels ? Translation.tr("Stops the download · deletes it")
                    : steamOpen ? Translation.tr("Restarts Steam · keeps saves") : Translation.tr("Deletes files · keeps saves")
                filled: armed
                danger: true
                closesMenu: armed
                // Steam games mid-install or mid-update too (Lutris only uninstalls installed games)
                visible: (["installed", "updateRequired", "updatePaused"].includes(root.installState)
                          || (isSteam && ["installing", "updating"].includes(root.installState)))
                    && !GameLauncherService.isCustomGame(game?.id)
                onTriggered: {
                    if (!armed) {
                        armed = true;
                        disarmTimer.restart();
                        return;
                    }
                    armed = false;
                    GameLauncherService.uninstallGame(game);
                }
                Timer { id: disarmTimer; interval: 5000; onTriggered: uninstallItem.armed = false }
                Connections { // Checked when the menu opens, so the note is right before it shows
                    target: moreMenu
                    function onOpenChanged() {
                        if (!moreMenu.open) uninstallItem.armed = false;
                        else if (uninstallItem.isSteam) steamCheck.running = true;
                    }
                }
                Process {
                    id: steamCheck
                    command: ["pgrep", "-x", "steam"]
                    onExited: (exitCode) => uninstallItem.steamOpen = exitCode === 0
                }
            }
            MoreItem { // A game added by hand: out of the launcher (the app itself stays installed). Click twice, as Uninstall
                id: removeItem
                property bool armed: false
                iconName: "playlist_remove"
                label: armed ? Translation.tr("Click to confirm") : Translation.tr("Remove from launcher")
                detail: armed ? Translation.tr("The app stays installed") : ""
                filled: armed
                danger: true
                closesMenu: armed
                visible: GameLauncherService.isCustomGame(game?.id)
                onTriggered: {
                    if (!armed) { armed = true; removeDisarm.restart(); return; }
                    armed = false;
                    GameLauncherService.removeCustomGame(game.id);
                    root.backPressed(); // Its page is gone with it
                }
                Timer { id: removeDisarm; interval: 5000; onTriggered: removeItem.armed = false }
                Connections { target: moreMenu; function onOpenChanged() { if (!moreMenu.open) removeItem.armed = false; } }
            }
        }
    }
    MouseArea { // While the tag menu is out: a click anywhere else on the page puts it away (it's under the menu)
        anchors.fill: parent
        z: 29
        visible: tagMenuPopup.open
        onClicked: tagMenuPopup.open = false
    }
    // ── A Steam game's launch options, when it has more than one: Play asks which, here, so Steam doesn't
    // (scripts/game-launcher/steam_launch_options.py, read when the page opens) ──
    property var launchChoices: []
    Process {
        id: launchChoicesProc
        stdout: StdioCollector {
            onStreamFinished: { try { root.launchChoices = JSON.parse(text); } catch (e) { root.launchChoices = []; } }
        }
    }
    readonly property string _steamAppId: (game?.id ?? "").startsWith("steam_") ? game.id.substring(6) : ""
    function _loadLaunchChoices() {
        if (_steamAppId === "") return;
        launchChoicesProc.running = false;
        launchChoicesProc.command = ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/steam_launch_options.py"), _steamAppId];
        launchChoicesProc.running = true;
    }
    on_SteamAppIdChanged: {
        root.launchChoices = [];
        launchMenu.open = false;
        _loadLaunchChoices();
    }
    // Installed while its page was open: Steam has its launch options now
    onInstallStateChanged: if (installState === "installed") _loadLaunchChoices()
    SideDrawer { // Which way to start it: one row per launch option, as Steam's dialog but here
        id: launchMenu
        paneW: 280
        paneH: launchCol.implicitHeight + 16
        anchorCenterY: sidebarContent.y + playButton.y + playButton.height / 2
        opener: playButton; exclusive: true
        Column {
            id: launchCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2
            Repeater {
                model: root.launchChoices
                MoreItem {
                    required property var modelData
                    // The first, unnamed one is the game itself; the others say what they are
                    iconName: modelData.index === 0 ? "play_arrow" : "tune"
                    filled: modelData.index === 0
                    label: modelData.label || (modelData.index === 0 ? Translation.tr("Play") : Translation.tr("Option %1").arg(modelData.index + 1))
                    detail: modelData.detail
                    onTriggered: { launchMenu.open = false; root.playPressed(root.game, modelData.index); }
                }
            }
        }
    }
    SideDrawer { // Install where? One row per Steam library, with its free space
        id: libraryMenu
        paneW: 260
        paneH: libraryCol.implicitHeight + 16
        anchorCenterY: sidebarContent.y + playButton.y + playButton.height / 2
        opener: playButton; exclusive: true
        Column {
            id: libraryCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2
            Repeater {
                model: GameLauncherService.steamLibraries
                MoreItem {
                    required property var modelData
                    // Named by drive, not by path (a long path cut off at the end hid what told them apart):
                    // the home one, else the folder holding it, skipping a "SteamLibrary"/"Steam" folder
                    readonly property string home: Quickshell.env("HOME")
                    readonly property var parts: modelData.path.split("/").filter(p => p !== "")
                    iconName: "hard_drive"
                    label: modelData.path.startsWith(home + "/") ? Translation.tr("Home folder")
                         : (/^steam(library)?$/i.test(parts[parts.length - 1] ?? "") && parts.length > 1 ? parts[parts.length - 2] : parts[parts.length - 1] ?? "/")
                    detail: Translation.tr("%1 GB free").arg(Math.floor(modelData.free / 1e9))
                    onTriggered: { libraryMenu.open = false; GameLauncherService.installGame(game, modelData.path); }
                }
            }
        }
    }
    SideDrawer { // Tags: chips for the game's tags, an input pill, suggestion chips
        id: tagMenuPopup
        paneW: 260
        paneH: _tagPopupContent.implicitHeight + 28
        anchorCenterY: topLeftButtons.y + tagIconBtn.y + tagIconBtn.height / 2
        exclusive: true // No opener: it has a text field, so it stays while the pointer is away (a click outside closes it)
        MouseArea { anchors.fill: parent } // Keep clicks inside the card
        Column {
            id: _tagPopupContent
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12
            // Header: badge, title + count
            Row {
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 12
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                    MaterialSymbol { anchors.centerIn: parent; text: "sell"; iconSize: 18; fill: 1; color: Appearance.colors.colPrimary }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 1
                    StyledText {
                        text: Translation.tr("Tags")
                        font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: tagIconBtn.hasTags
                            ? tagIconBtn.gameTags.length + (tagIconBtn.gameTags.length === 1 ? " tag · click to remove" : " tags · click to remove")
                            : Translation.tr("No tags yet")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            // The game's tags as chips; hover turns one red to remove it
            Flow {
                width: parent.width; spacing: 6
                visible: tagIconBtn.hasTags
                Repeater {
                    model: tagIconBtn.gameTags
                    Rectangle {
                        id: _tagChip
                        required property string modelData
                        readonly property bool hovered: _tagChipMa.containsMouse
                        width: _tagChipRow.implicitWidth + 22; height: 28; radius: Appearance.rounding.segment
                        color: hovered ? ColorUtils.transparentize(Appearance.colors.colError, 0.82)
                            : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: _tagChipRow
                            anchors.centerIn: parent; spacing: 4
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: _tagChip.modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                                color: _tagChip.hovered ? Appearance.colors.colError : Appearance.colors.colPrimary
                            }
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "close"; iconSize: 14
                                color: _tagChip.hovered ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
                            }
                        }
                        MouseArea {
                            id: _tagChipMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.game) GameLauncherService.removeTag(root.game.id, _tagChip.modelData); }
                        }
                    }
                }
            }
            // Add-tag input pill
            Rectangle {
                width: parent.width; height: 38; radius: 13
                color: tagInputField.activeFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                border.width: tagInputField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: tagInputField.forceActiveFocus()
                }
                MaterialSymbol {
                    id: _tagAddIcon
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "add"; iconSize: 18
                    color: tagInputField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                TextInput {
                    id: tagInputField
                    anchors { left: _tagAddIcon.right; leftMargin: 8; right: parent.right; rightMargin: 14; top: parent.top; bottom: parent.bottom }
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colOnLayer1
                    clip: true; maximumLength: 30; selectByMouse: true
                    selectedTextColor: Appearance.colors.colOnPrimary
                    selectionColor: Appearance.colors.colPrimary
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const tag = text.trim();
                            if (tag.length > 0 && root.game) {
                                GameLauncherService.addTag(root.game.id, tag);
                                text = "";
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            tagMenuPopup.open = false;
                            text = "";
                            root.forceActiveFocus();
                            event.accepted = true;
                        }
                    }
                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Add a tag and press Enter")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        visible: tagInputField.text.length === 0
                    }
                }
            }
            // Suggestions from tags used on other games
            Column {
                id: _tagSuggest
                property var _allTags: { const _ = GameLauncherService.tagsRevision; return GameLauncherService.allTags; }
                property var _availableTags: {
                    const input = tagInputField.text.trim().toLowerCase();
                    return _allTags.filter(t => tagIconBtn.gameTags.indexOf(t) < 0 && (input.length === 0 || t.toLowerCase().indexOf(input) >= 0));
                }
                width: parent.width; spacing: 8
                visible: _availableTags.length > 0
                StyledText {
                    text: Translation.tr("Suggestions")
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
                Flow {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: _tagSuggest._availableTags
                        Rectangle {
                            id: _suggestChip
                            required property string modelData
                            width: _suggestRow.implicitWidth + 20; height: 28; radius: Appearance.rounding.segment
                            color: _suggestMa.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                id: _suggestRow
                                anchors.centerIn: parent; spacing: 4
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "add"; iconSize: 14
                                    color: _suggestMa.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: _suggestChip.modelData
                                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                            MouseArea {
                                id: _suggestMa
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.game) return;
                                    // Text first: adding the tag takes this chip out of the list (destroyed mid-click)
                                    const tag = _suggestChip.modelData, gameId = root.game.id;
                                    tagInputField.text = "";
                                    GameLauncherService.addTag(gameId, tag);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        id: sidebarContent
        anchors { left: parent.left; leftMargin: 30; verticalCenter: parent.verticalCenter; verticalCenterOffset: 22 } // Room for the back arrow above
        width: 270; z: 10
        spacing: 0
        RippleButton {
            id: playButton
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            buttonRadius: height / 3
            padding: 0
            activeFocusOnTab: true
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            buttonColor: (hovered || activeFocus) ? colBackgroundHover : colBackground
            horizontalPadding: 0
            enabled: root.installState !== "uninstalling"
            opacity: enabled ? 1 : 0.6
            // Running now (GameClips' watcher): the button says so and goes back to it, instead of starting it again
            readonly property bool playing: !!game && GameClips.gameId === game.id
            function activate() {
                if (playing) {
                    const matchers = GameLauncherService.processMatchers(game);
                    if (matchers.length > 0)
                        Quickshell.execDetached(["python3", "-I", Quickshell.shellPath("scripts/game-launcher/focus_game.py"), ...matchers]);
                    GlobalStates.gameLauncherOpen = false;
                }
                // While a download runs, the button opens Steam's downloads instead of starting it again
                else if (root._downloading || root.installState === "updatePaused") GameLauncherService.openDownloads();
                // More than one Steam library: ask which here, instead of Steam's install dialog
                else if (root.installState === "notInstalled" && (game?.id ?? "").startsWith("steam_")
                         && GameLauncherService.steamLibraries.length > 1) libraryMenu.open = !libraryMenu.open;
                // More than one way to start it (Project Zomboid: Play or Compatibility Mode): ask here, not in Steam
                else if (root.installState === "installed" && root.launchChoices.length > 1) launchMenu.open = !launchMenu.open;
                else root.playPressed(game, -1);
            }
            onClicked: activate()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activate(); event.accepted = true; }
            }
            readonly property var _look: playing ? { icon: "", text: Translation.tr("Playing") } : ({
                "notInstalled":   { icon: "download",    text: Translation.tr("Install") },
                "installing":     { icon: "downloading", text: Translation.tr("Installing") },
                "updating":       { icon: "downloading", text: Translation.tr("Updating") },
                "updateRequired": { icon: "update",      text: Translation.tr("Update & play") },
                "updatePaused":   { icon: "downloading", text: Translation.tr("Resume update") },
                "uninstalling":   { icon: "delete",      text: Translation.tr("Uninstalling…") },
                "installed":      { icon: "play_arrow",  text: Translation.tr("Play") }
            })[root.installState] ?? { icon: "play_arrow", text: Translation.tr("Play") }
            contentItem: Item {
                implicitHeight: 44
                Rectangle { // Download progress (the game's, or its mods'), filling the pill from the left
                    visible: root._downloadPhase !== "" && root.downloadProgress >= 0
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * Math.max(0, root.downloadProgress)
                    radius: height / 3
                    color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.8)
                    Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                }
                Row {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -4
                    spacing: 8
                    PlayingDot { // Playing: where the icon goes (as the grid's badge)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: playButton.playing && root.visible
                        size: 9
                        color: Appearance.colors.colOnPrimary
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !playButton.playing
                        text: playButton._look.icon
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const pct = root.downloadProgress >= 0 ? ` ${Math.floor(root.downloadProgress * 100)}%` : "";
                            if (playButton.playing) return playButton._look.text;
                            if (root._downloading || root._paused) return playButton._look.text + (pct ? " " + pct : "");
                            if (root._modsOnly) return playButton._look.text + "  ·  " + Translation.tr("mods") + pct;
                            return playButton._look.text;
                        }
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.5
                    }
                }
            }
        }
        Item { // Slot for the action icons (topLeftButtons is positioned on top of it)
            id: actionRowSlot
            Layout.fillWidth: true
            Layout.leftMargin: 8; Layout.rightMargin: 8
            Layout.topMargin: 10; Layout.bottomMargin: 14
            Layout.preferredHeight: 36
        }
        readonly property bool _isSteam: game?.id?.startsWith("steam_") ?? false
        readonly property bool _isLutris: game?.id?.startsWith("lutris_") ?? false
        readonly property var _steamActions: [
                { icon: "newspaper",            label: qsTr("News"),         type: "news" },
                { icon: "science",              label: qsTr("ProtonDB"),     url: "https://www.protondb.com/app/" },
                { icon: "perm_media",           label: qsTr("Captures"),     type: "screenshots" },
                { icon: "emoji_events",         label: qsTr("Achievements"), type: "achievements" }
        ]
        readonly property var _lutrisActions: {
            const _ = GameLauncherService.metadataCacheRevision;
            const meta = game ? GameLauncherService.getMetadata(game.id) : null;
            const hasSteamId = meta && meta.steamId;
            const actions = [
                { icon: "perm_media",     label: qsTr("Captures"),      type: "screenshots" },
                { icon: "sports_esports", label: qsTr("Open Lutris"),   type: "lutris_app" },
                { icon: "public",         label: qsTr("Lutris page"),   type: "lutris_page" },
            ];
            if (hasSteamId)
                actions.push({ icon: "storefront", label: qsTr("Steam Store"), type: "steam_store" });
            // ProtonDB is about running Windows games: not for native Linux / Flatpak ones
            if (!root._runsNatively)
                actions.push({ icon: "science", label: qsTr("ProtonDB"), type: "protondb" });
            actions.push({ icon: "devices", label: qsTr("PCGamingWiki"),  type: "pcgamingwiki" });
            return actions;
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 2
            Repeater {
                id: sidebarRepeater
                model: sidebarContent._isSteam ? sidebarContent._steamActions
                     : sidebarContent._isLutris ? sidebarContent._lutrisActions
                     : []
                onCountChanged: Qt.callLater(root._refreshSidebarButtons)
                RippleButton {
                    id: actionBtn
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    buttonRadius: height / 3
                    padding: 0
                    activeFocusOnTab: true
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.92)
                    colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
                    // Its panel is open: tinted, with the icon and label in the accent (accent = active)
                    readonly property bool panelOpen: root.openPanel !== "" && root.openPanel === modelData.type
                    readonly property bool lit: hovered || activeFocus
                    buttonColor: panelOpen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86)
                        : lit ? colBackgroundHover : colBackground
                    // News: how many posts are new since its panel was last opened
                    readonly property int unread: modelData.type === "news" && GameLauncherService.newsFor === (game?.id ?? "")
                        ? GameLauncherService.unreadNews : 0
                    contentItem: Item {
                        implicitHeight: 32
                        Rectangle { // Unread count
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            visible: actionBtn.unread > 0
                            width: Math.max(height, unreadText.implicitWidth + 12); height: 18; radius: Appearance.rounding.unsharpenmore
                            color: Appearance.colors.colPrimary
                            StyledText {
                                id: unreadText
                                anchors.centerIn: parent
                                text: actionBtn.unread > 9 ? "9+" : actionBtn.unread
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.leftMargin: 12
                            spacing: 12
                            MaterialSymbol {
                                text: actionBtn.modelData.icon; iconSize: 20
                                fill: actionBtn.panelOpen ? 1 : 0
                                color: (actionBtn.lit || actionBtn.panelOpen) ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
                                Behavior on color { ColorAnimation { duration: 180 } }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: actionBtn.modelData.label
                                color: actionBtn.panelOpen ? Appearance.colors.colPrimary
                                    : actionBtn.lit ? Appearance.colors.colOnLayer0 : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                Behavior on color { ColorAnimation { duration: 180 } }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    onClicked: {
                        if (!game || !game.id) return;
                        // The page takes focus back (it passes keys on to the panels, and links open outside),
                        // so this button doesn't stay highlighted as focused
                        root.forceActiveFocus();
                        if (root.panelTypes.includes(modelData.type)) {
                            // Its own panel's button closes it again; another one's switches to that
                            root.openPanel = root.openPanel === modelData.type ? "" : modelData.type;
                            return;
                        }
                        if (sidebarContent._isSteam) {
                            const appid = game.id.substring(6);
                            Quickshell.execDetached(["xdg-open", modelData.url + appid]);
                        } else if (sidebarContent._isLutris) {
                            const slug = game.id.substring(7);
                            const gameName = encodeURIComponent(game.name || "");
                            const meta = root._currentMetadata;
                            const steamId = meta?.steamId || null;
                            switch (modelData.type) {
                            case "lutris_app":
                                Quickshell.execDetached(["lutris"]);
                                break;
                            case "lutris_page":
                                Quickshell.execDetached(["xdg-open", "https://lutris.net/games/" + slug + "/"]);
                                break;
                            case "protondb":
                                if (steamId)
                                    Quickshell.execDetached(["xdg-open", "https://www.protondb.com/app/" + steamId]);
                                else
                                    Quickshell.execDetached(["xdg-open", "https://www.protondb.com/search?q=" + gameName]);
                                break;
                            case "steam_store":
                                if (steamId)
                                    Quickshell.execDetached(["xdg-open", "https://store.steampowered.com/app/" + steamId]);
                                else
                                    Quickshell.execDetached(["xdg-open", "https://store.steampowered.com/search/?term=" + gameName]);
                                break;
                            case "pcgamingwiki":
                                Quickshell.execDetached(["xdg-open", "https://www.pcgamingwiki.com/w/index.php?search=" + gameName]);
                                break;
                            }
                        }
                    }
                    Keys.onPressed: event => { if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { clicked(); event.accepted = true; } }
                }
            }
        }
    }
    property bool metadataPaneOpen: false
    // ─── Metadata Hover Panel (right side of sidebar) ────────────
    readonly property var _currentMetadata: {
        const _ = GameLauncherService.metadataCacheRevision;
        return game ? GameLauncherService.getMetadata(game.id) : null;
    }
    // ─── Info drawer: a SideDrawer centred on the menu, opened by hovering its reveal tab ───
    // The ⋯ and tags menus cover the tab, but hover still reaches it underneath: ignore it while they're open
    readonly property bool _otherSideMenuOpen: moreMenu.open || tagMenuPopup.open
    function _syncInfoHover() {
        if (infoTabHover.hovered || infoPaneHover.hovered) { metadataCloseTimer.stop(); root.metadataPaneOpen = true; }
        else metadataCloseTimer.restart();
    }
    Timer {
        id: metadataCloseTimer; interval: 300
        onTriggered: root.metadataPaneOpen = infoTabHover.hovered || infoPaneHover.hovered
    }
    Rectangle { // Reveal tab: a small nub sticking out of the menu edge
        id: metadataNotch
        visible: root._currentMetadata !== null
        x: sidebarPanel.x + sidebarPanel.width
        y: sidebarPanel.y + (sidebarPanel.height - height) / 2
        z: 9
        width: 18; height: 64
        topRightRadius: 9; bottomRightRadius: 9
        color: Appearance.m3colors.m3background
        opacity: infoDrawer.offset > 0.5 ? 1 : 0 // Hidden once the drawer covers it
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MaterialSymbol {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -1
            text: "chevron_right"
            iconSize: 18
            color: infoTabHover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        HoverHandler { id: infoTabHover; enabled: !root._otherSideMenuOpen; onHoveredChanged: root._syncInfoHover() }
        TapHandler { enabled: !root._otherSideMenuOpen; onTapped: root.metadataPaneOpen = !root.metadataPaneOpen }
    }
    SideDrawer {
        id: infoDrawer
        open: root.metadataPaneOpen && root._currentMetadata !== null
        paneW: 280
        paneH: Math.min(_metaCol.implicitHeight + 36, sidebarPanel.height - 32)
        anchorCenterY: sidebarPanel.y + sidebarPanel.height / 2
        HoverHandler { id: infoPaneHover; onHoveredChanged: root._syncInfoHover() }
        Flickable {
            anchors { fill: parent; margins: 18 }
            contentHeight: _metaCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: _metaCol
                width: parent.width
                spacing: 14
                // Metacritic: round score badge coloured by rating
                Row {
                    visible: root._currentMetadata?.metacritic != null
                    spacing: 12
                    readonly property int score: root._currentMetadata?.metacritic ?? 0
                    readonly property color tone: score >= 75 ? Appearance.colors.colPrimary
                        : score >= 50 ? Appearance.colors.colTertiary : Appearance.colors.colError
                    Rectangle {
                        width: 36; height: 36; radius: 12
                        color: parent.tone
                        StyledText {
                            anchors.centerIn: parent
                            text: parent.parent.score
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        StyledText {
                            text: parent.parent.score >= 75 ? "Favorable" : parent.parent.score >= 50 ? "Mixed" : "Unfavorable"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: parent.parent.tone
                        }
                        StyledText {
                            text: "Metacritic"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                // Details: icon badge + label + value, like the clock/battery popups
                MetaRow { iconName: "code"; label: "Developer"; value: root._currentMetadata?.developers?.join(", ") ?? "" }
                MetaRow { iconName: "storefront"; label: "Publisher"; value: root._currentMetadata?.publishers?.join(", ") ?? "" }
                MetaRow { iconName: "calendar_month"; label: "Released"; value: root._currentMetadata?.releaseDate ?? "" }
                // Lutris games: what the Lutris database knows (Steam games have the store's details above)
                readonly property bool _lutris: game?.id?.startsWith("lutris_") ?? false
                MetaRow { iconName: "category"; label: "Genres"; value: _metaCol._lutris ? (root._currentMetadata?.genres ?? []).join(", ") : "" }
                MetaRow { iconName: "devices"; label: "Platforms"; value: _metaCol._lutris ? (root._currentMetadata?.platforms ?? []).join(", ") : "" }
                MetaRow { iconName: root._runsNatively ? "terminal" : "wine_bar"; label: "Runs on"; value: root._runnerLabel }
                MetaRow { iconName: "group"; label: "Lutris players"; value: _metaCol._lutris && (root._currentMetadata?.userCount ?? 0) > 0 ? Number(root._currentMetadata.userCount).toLocaleString(Qt.locale(), "f", 0) : "" }
                // Description
                Column {
                    width: parent.width
                    spacing: 6
                    topPadding: 2
                    visible: (root._currentMetadata?.description ?? "") !== ""
                    StyledText {
                        text: "About"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        width: parent.width
                        text: GameLauncherService.decodeEntities(root._currentMetadata?.description ?? "")
                        textFormat: Text.PlainText // Store text, never markup
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        lineHeight: 1.3
                        maximumLineCount: 8
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    // ─── Screenshots / Achievements / News / Customize / Launch options: panels out of the launcher's top edge ───
    // One at a time. GameLauncher.qml shows the one named here, and sets topPanelItem, which gets the
    // keys while it's open. The buttons and the launcher's show… IPC calls set it
    readonly property var panelTypes: ["screenshots", "achievements", "news", "customize", "launchOptions"]
    property string openPanel: ""     // One of panelTypes, "" when none
    property Item topPanelItem: null
    // ─── Inline Components ────────────────────────────────────
    // A menu that grows out of the left menu's right edge on the same blob + drawer curves as the
    // info drawer, centred on the button that opened it and kept inside the panel
    component SideDrawer: Item {
        id: sd
        property bool open: false
        property real anchorCenterY: 0 // In panel coordinates
        property real paneW: 230
        property real paneH: 0
        default property alias content: pane.data
        property Item opener: null // The button that opens it (see the pane's HoverHandler)
        property bool exclusive: false // One of the side menus: opening it closes the others
        property real offset: (open && root.animationReady) ? 0 : 1 // 0 = out, 1 = tucked in
        Behavior on offset {
            NumberAnimation {
                duration: sd.open ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: sd.open ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        readonly property real _top: -(paneW + 60) * offset
        readonly property real _y: Math.min(0, _top)
        readonly property real _len: paneW + Math.max(0, _top) // Overshoot stretches
        readonly property real _shown: Math.max(0, _y + _len)
        readonly property real menuTop: Math.max(16, Math.min(anchorCenterY - sidebarPanel.y - paneH / 2, height - paneH - 16))
        anchors { left: sidebarPanel.right; top: sidebarPanel.top; bottom: sidebarPanel.bottom }
        width: paneW + 40
        z: 30; clip: true
        visible: offset < 1
        Item { // The blob, rotated -90° so its "bar" edge is the menu's right edge
            id: stage
            readonly property real along: sd.height
            readonly property real out: sd.width
            width: along; height: out
            x: (out - along) / 2; y: (along - out) / 2
            rotation: -90
            clip: true
            Loader {
                anchors.fill: parent
                active: sd.visible
                source: Qt.resolvedUrl("../overview/BlobDrawerBackground.qml")
                onLoaded: {
                    item.barBottom = 0;
                    item.barHeight = 40;
                    item.barRadius = 0;
                    item.fillColor = Appearance.m3colors.m3background;
                    item.fillOpacity = 1.0;
                    // Rotated: the stage's x runs up the screen
                    item.drawerX = Qt.binding(() => stage.along - sd.menuTop - sd.paneH);
                    item.drawerY = Qt.binding(() => sd._y);
                    item.drawerWidth = Qt.binding(() => sd.paneH);
                    item.drawerHeight = Qt.binding(() => sd._len);
                    item.drawerRadius = Qt.binding(() => Math.min(Appearance.rounding.large, sd._shown / 2));
                }
            }
        }
        Item {
            id: pane
            x: sd._shown - width // Slides with the drawer
            y: sd.menuTop
            width: sd.paneW
            height: sd.paneH
            opacity: 1 - sd.offset
            // With an opener, the menu closes shortly after the pointer leaves both it and its button
            HoverHandler { id: sdHover; enabled: sd.opener !== null; onHoveredChanged: if (!hovered) sdCloseTimer.restart(); else sdCloseTimer.stop() }
        }
        Timer { id: sdCloseTimer; interval: 600; onTriggered: if (!sdHover.hovered && !(sd.opener?.hovered ?? false)) sd.open = false }
        onOpenChanged: if (open && exclusive) root._sideMenuOpened(sd)
    }
    // An on/off icon in the row under Play (favourite, completed, crosshair): faded while off, the icon
    // filled in the accent while on, a bounce when clicked
    component ToggleIcon: RippleButton {
        id: ti
        property string iconName
        property bool on: false
        property string tip
        signal flipped() // (not toggled(): buttons have that already)
        width: 36; height: 36
        buttonRadius: 12; padding: 0
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.7)
        buttonColor: (hovered || activeFocus) ? colBackgroundHover : colBackground
        opacity: (hovered || activeFocus || on) ? 1.0 : 0.7
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        contentItem: Item {
            implicitWidth: 36; implicitHeight: 36
            MaterialSymbol {
                id: tiIcon
                anchors.centerIn: parent; text: ti.iconName; iconSize: 20
                fill: ti.on ? 1 : 0
                color: ti.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                Behavior on fill { NumberAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }
                SequentialAnimation {
                    id: tiBounce
                    NumberAnimation { target: tiIcon; property: "scale"; to: 1.4; duration: 120; easing.type: Easing.OutQuad }
                    NumberAnimation { target: tiIcon; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
            }
        }
        onClicked: { if (!game) return; ti.flipped(); tiBounce.start(); focus = false; }
        StyledToolTip { text: ti.tip }
    }
    component MoreItem: RippleButton {
        id: mi
        property string iconName
        property string label
        property string detail: "" // A second, smaller line under the label (fits in the same height)
        property bool filled: false // Solid squircle behind the icon: armed/active
        property bool closesMenu: true
        property bool danger: false
        signal triggered()
        readonly property color accent: danger ? Appearance.colors.colError : Appearance.colors.colPrimary
        width: parent ? parent.width : 200
        height: visible ? 44 : 0 // Never changes: a taller item would resize and move the open menu
        buttonRadius: 14
        padding: 0
        colBackground: "transparent"
        colBackgroundHover: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.88) : Appearance.m3colors.m3surfaceContainerHigh
        colRipple: ColorUtils.transparentize(accent, 0.75)
        onClicked: { const close = closesMenu; if (game) mi.triggered(); if (close) moreMenu.open = false; }
        contentItem: Item {
            Row {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 12
                Rectangle {
                    width: 32; height: 32; radius: Appearance.rounding.segment
                    color: mi.filled ? mi.accent : ColorUtils.transparentize(mi.accent, 0.82)
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    MaterialSymbol {
                        anchors.centerIn: parent; text: mi.iconName; iconSize: 17
                        color: mi.filled ? (mi.danger ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary) : mi.accent
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: mi.width - 6 - 32 - 12 - 10 // What's left of the row: long text is cut off, not spilled
                    StyledText { width: parent.width; elide: Text.ElideRight; text: mi.label; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium; color: mi.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer0 }
                    StyledText { width: parent.width; elide: Text.ElideRight; visible: mi.detail !== ""; text: mi.detail; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                }
            }
        }
    }
    component MetaRow: Row {
        id: metaRow
        property string iconName: ""
        property string label: ""
        property string value: ""
        width: parent.width
        spacing: 12
        visible: value !== ""
        Rectangle {
            width: 32; height: 32; radius: Appearance.rounding.segment
            anchors.verticalCenter: parent.verticalCenter
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
            MaterialSymbol { anchors.centerIn: parent; text: metaRow.iconName; iconSize: 17; color: Appearance.colors.colPrimary }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: metaRow.width - 32 - metaRow.spacing
            spacing: 1
            StyledText { text: metaRow.label; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
            StyledText { width: parent.width; text: metaRow.value; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
        }
    }
}
