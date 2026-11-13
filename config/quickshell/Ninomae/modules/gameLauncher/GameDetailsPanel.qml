import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Shapes
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
    readonly property bool _paused: installState === "updatePaused" || installState === "installPaused" // Still shows how far it got
    readonly property bool _queued: installState === "installQueued" || installState === "updateQueued" // In Steam's queue, behind another
    // A first install under way, however it stands (downloading, paused, queued)
    readonly property bool _installing: ["installing", "installPaused", "installQueued"].includes(installState)
    // Workshop mods downloading for an installed game (GameLauncherService.workshopDownloading)
    readonly property bool _modsOnly: !_downloading && installState === "installed" && !!GameLauncherService.workshopDownloading[game?.id]
    // What's downloading, if anything: progress starts over when this changes (not on a pause)
    readonly property string _downloadPhase: _downloading || _paused || _queued ? "game" : _modsOnly ? "mods" : ""
    // The game's own download: the Downloads panel's feed has it (GameLauncherService.steamDownloads), measured
    // once for both. Its Workshop mods, which the feed doesn't follow: measured here (_modsProgress)
    readonly property var _feedItem: {
        const appid = (game?.id ?? "").startsWith("steam_") ? game.id.substring(6) : "";
        return appid ? (GameLauncherService.steamDownloads.items ?? []).find(i => i.appid === appid) ?? null : null;
    }
    readonly property real downloadProgress: _downloadPhase === "game" ? (_feedItem?.progress ?? -1)
        : _downloadPhase === "mods" ? _modsProgress : -1
    // Mods: Steam gives the total in the game's manifest (BytesToStage), and the live part is the data
    // written so far under steamapps/workshop/downloads/<id>
    property real _modsProgress: -1
    property real _bytesToStage: 0
    on_DownloadPhaseChanged: { _modsProgress = -1; _bytesToStage = 0; }
    FileView { // Read only while mods download
        id: manifestFile
        path: root._downloadPhase === "mods" ? (GameLauncherService.steamPaths(root.game)?.manifest ?? "") : ""
        printErrors: false
        onLoaded: {
            const t = text();
            const num = k => Number((t.match(new RegExp(`"${k}"\\s+"(\\d+)"`)) ?? [])[1] ?? 0);
            const toStage = num("BytesToStage") || num("BytesToDownload");
            if (toStage !== root._bytesToStage) root._modsProgress = -1; // A new job: the old progress doesn't apply
            root._bytesToStage = toStage;
        }
    }
    Process { // Allocated bytes, not apparent size: Steam writes the files sparsely
        id: stagedSizeProc
        command: ["du", "-sc", "--block-size=1", ...(GameLauncherService.steamPaths(root.game)?.downloads ?? [])]
        stdout: StdioCollector {
            onStreamFinished: { // Last line is the total (a folder that doesn't exist yet just adds nothing)
                const lines = text.trim().split("\n");
                const bytes = parseInt(lines[lines.length - 1]);
                // Never step back: Steam moves finished files out of the download folder while it commits
                if (!isNaN(bytes) && root._bytesToStage > 0)
                    root._modsProgress = Math.max(root._modsProgress, Math.min(1, bytes / root._bytesToStage));
            }
        }
    }
    Timer {
        interval: 1500
        running: root._downloadPhase === "mods" && root.visible && manifestFile.path !== ""
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
    readonly property string _logoSource: GameLauncherService.logoArt(game)
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
            GameLauncherService.loadNews(game); // For the News row: its newest headline and how many are new (cached an hour)
            GameLauncherService.loadAchievements(game); // For the Achievements row's count (cached a day)
        } else if (game?.id?.startsWith("lutris_")) {
            GameLauncherService.fetchLutrisMetadata(game);
            root._loadSteamRows(); // With a Steam id from a cached entry: at once (else when it arrives)
        }
        capturesPeek.running = true;
        root._measureSize();
        root.arrived();
    }
    Component.onCompleted: { animationResetTimer.start(); _arrive(); }
    onShownChanged: _arrive()
    onGameChanged: {
        factsOpen = false;
        if (_arrived) GameLauncherService.fetchPlayerCount(game);
    }
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
            if (moreMenu.open || tagMenuPopup.open || webMenu.open) {
                moreMenu.open = false;
                tagMenuPopup.open = false;
                webMenu.open = false;
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
                    const cover = GameLauncherService.localArt(root.game, "boxArt"); // Yours if set, as the grid's
                    if (cover) return cover;
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
    // What a Lutris game runs with (a game added by hand: only that it's a Flatpak), for the stats pill and the info drawer
    readonly property string _runnerLabel: {
        const id = game?.id ?? "";
        if (!id.startsWith("lutris_") && !id.startsWith("custom_")) return "";
        if (game.flatpakId) return "Flatpak";
        if (id.startsWith("custom_")) return "";
        const names = { "linux": "Native Linux", "wine": "Wine", "steam": "Steam", "dosbox": "DOSBox",
                        "libretro": "RetroArch", "scummvm": "ScummVM", "web": "Browser", "flatpak": "Flatpak" };
        const r = game.runner || "";
        return names[r] ?? (r ? r.charAt(0).toUpperCase() + r.slice(1) : "");
    }
    readonly property bool _runsNatively: game?.runner === "linux" || !!game?.flatpakId
    // A Lutris game's Steam app id, from its lutris.net entry: with one, its menu has Steam's News, Achievements
    // and ProtonDB rows (the lookups take the id, not the store)
    readonly property string _lutrisSteamId: {
        const _ = GameLauncherService.metadataCacheRevision;
        return (game?.id ?? "").startsWith("lutris_") ? GameLauncherService.steamAppId(game) : "";
    }
    on_LutrisSteamIdChanged: if (_arrived) _loadSteamRows()
    function _loadSteamRows() {
        if (root._lutrisSteamId === "") return;
        GameLauncherService.loadNews(game);
        GameLauncherService.loadAchievements(game);
    }
    // A Lutris game's files: a Flatpak's data folder (its game folder is often empty), else its game folder.
    // The Files row opens it and says where it is: "Flatpak data" (its path is long, all app id), else the path, ~ for home
    readonly property string _filesDir: game?.flatpakId ? `${Quickshell.env("HOME")}/.var/app/${game.flatpakId}` : (game?.gameDir ?? "")
    readonly property string _filesDirShort: {
        const home = Quickshell.env("HOME");
        return game?.flatpakId ? Translation.tr("Flatpak data") : _filesDir.startsWith(home + "/") ? "~" + _filesDir.substring(home.length) : _filesDir;
    }
    // ─── Facts (top-right): joined chips of what changes: how it runs (Lutris), an update since you last played,
    // ProtonDB, hours, players. Not the install status: the Play button says it. Hovered, the rest (_extraStats:
    // last played, size, where it's from) joins under them as rows at the same width, and the ⓘ turns on ───
    readonly property var _pillFacts: {
        if (!game) return [];
        const out = [];
        if (root._runnerLabel !== "")
            out.push({ icon: root._runsNatively ? "terminal" : "wine_bar", value: root._runnerLabel });
        if (root.installState === "installed" && GameClips.gameId !== game.id && !root._modsOnly
                && GameLauncherService.updatedSincePlayed(game)) // Patched since you last played: news, in the tertiary
            out.push({ icon: "new_releases", value: Translation.tr("Updated"), name: root._ago(game.lastUpdated * 1000), accent: Appearance.colors.colTertiary });
        const tier = game.protondbTier || "";
        if (tier !== "")
            out.push({ icon: "science", value: tier.charAt(0).toUpperCase() + tier.slice(1) });
        if (game.playtime > 0) {
            const h = Math.floor(game.playtime / 60);
            out.push({ icon: "timer", value: h > 0 ? `${h} h` : "< 1 h", name: Translation.tr("played") });
        }
        // Players in it right now (Steam's count; not for games it doesn't count)
        const players = GameLauncherService.playerCount(game); // Re-read as the counts come in (the binding sees playerCounts)
        if (players > 0)
            out.push({ icon: "group", value: _thousands(players), name: Translation.tr("playing") });
        // Lutris: how many have it on lutris.net, in the same spot
        const lutrisUsers = game.id.startsWith("lutris_") ? (root._currentMetadata?.userCount ?? 0) : 0;
        if (lutrisUsers > 0)
            out.push({ icon: "group", value: _thousands(lutrisUsers), name: Translation.tr("on Lutris") });
        return out;
    }
    function _thousands(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
    property bool factsOpen: false
    Timer { id: factsCloseTimer; interval: 250; onTriggered: root.factsOpen = factsHover.hovered }
    // The chips stretch to the rows' width when the rows need more, so the two always line up
    readonly property real _factsWidth: Math.max(_chipsNeed, _extrasNeed)
    // Measured when a chip or row comes, goes or changes size (a binding over itemAt() missed rows made
    // again: with no chips, the tab stayed as narrow as the ⓘ). callLater runs it once for many
    property real _chipsNeed: 0 // The chips' own widths, the ⓘ and the gaps
    property real _extrasNeed: 0 // The widest row's own width (label, value), not the width it's given
    function _measureFacts() {
        let c = root._extraStats.length > 0 ? 38 : -3;
        for (let i = 0; i < chipsRepeater.count; i++) c += (chipsRepeater.itemAt(i)?.implicitWidth ?? 0) + 3;
        let e = 0;
        for (let i = 0; i < extrasRepeater.count; i++) e = Math.max(e, extrasRepeater.itemAt(i)?.implicitWidth ?? 0);
        root._chipsNeed = c;
        root._extrasNeed = e;
    }
    // The facts hang from the art's top edge in a tab of the page's colour (as the bar's drawers hang from the bar):
    // curved in where it meets the edge, hugging the chips, and growing down with the rows
    Shape {
        id: factsTab
        readonly property real pad: 5 // Around the chips
        readonly property real r: 12 // The curves in at the edge
        readonly property real rb: Appearance.rounding.normal
        readonly property real w: infoCard.width + pad * 2
        readonly property real h: infoCard.height + pad * 2
        visible: infoCard.visible
        opacity: infoCard.opacity
        x: infoCard.x - pad - r
        y: bannerFrame.y
        width: w + r * 2; height: h
        z: 9
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Appearance.m3colors.m3background
            strokeWidth: -1
            startX: 0; startY: 0
            PathArc { x: factsTab.r; y: factsTab.r; radiusX: factsTab.r; radiusY: factsTab.r }
            PathLine { x: factsTab.r; y: factsTab.h - factsTab.rb }
            PathArc { x: factsTab.r + factsTab.rb; y: factsTab.h; radiusX: factsTab.rb; radiusY: factsTab.rb; direction: PathArc.Counterclockwise }
            PathLine { x: factsTab.r + factsTab.w - factsTab.rb; y: factsTab.h }
            PathArc { x: factsTab.r + factsTab.w; y: factsTab.h - factsTab.rb; radiusX: factsTab.rb; radiusY: factsTab.rb; direction: PathArc.Counterclockwise }
            PathLine { x: factsTab.r + factsTab.w; y: factsTab.r }
            PathArc { x: factsTab.w + factsTab.r * 2; y: 0; radiusX: factsTab.r; radiusY: factsTab.r }
            PathLine { x: 0; y: 0 }
        }
    }
    Column {
        id: infoCard
        anchors { right: parent.right; rightMargin: 35; top: bannerFrame.top; topMargin: factsTab.pad }
        spacing: 3
        visible: root._pillFacts.length > 0 || root._extraStats.length > 0
        z: 10
        HoverHandler { // Open while the pointer is on the chips or the rows; a moment's grace on the way out
            id: factsHover
            onHoveredChanged: {
                if (hovered && root._extraStats.length > 0) { factsCloseTimer.stop(); root.factsOpen = true; }
                else factsCloseTimer.restart();
            }
        }
        opacity: root.animationReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        Row {
            id: factsRow
            z: 1 // Over the rows, which slide out from under it
            readonly property real _stretch: (root._factsWidth - root._chipsNeed) / Math.max(1, root._pillFacts.length)
            spacing: 3
            Repeater {
                id: chipsRepeater
                model: root._pillFacts
                onItemAdded: Qt.callLater(root._measureFacts)
                onItemRemoved: Qt.callLater(root._measureFacts)
                Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: factChip.implicitWidth + 26
                    onImplicitWidthChanged: Qt.callLater(root._measureFacts)
                    width: implicitWidth + factsRow._stretch
                    height: 38
                    color: Appearance.colors.colLayer3
                    topLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.joined
                    bottomLeftRadius: index === 0 && !extrasDrawer.visible ? Appearance.rounding.small : Appearance.rounding.joined
                    topRightRadius: Appearance.rounding.joined
                    bottomRightRadius: Appearance.rounding.joined
                    Row {
                        id: factChip
                        anchors.centerIn: parent
                        spacing: 7
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; iconSize: 17; color: modelData.accent ?? Appearance.colors.colPrimary }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.value
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!modelData.name
                            text: modelData.name ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            Rectangle { // ⓘ: says there's more, and turns on (in the accent) while it's out
                visible: root._extraStats.length > 0
                width: 38; height: 38
                color: root.factsOpen ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
                Behavior on color { ColorAnimation { duration: 150 } }
                topLeftRadius: Appearance.rounding.joined
                bottomLeftRadius: Appearance.rounding.joined
                topRightRadius: Appearance.rounding.small
                bottomRightRadius: extrasDrawer.visible ? Appearance.rounding.joined : Appearance.rounding.small
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "info"
                    iconSize: 19
                    fill: root.factsOpen ? 1 : 0
                    color: root.factsOpen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
        Item { // Last played, size, where it's from: rows joined under the chips, sliding out from under them in one
            // piece on the bar drawers' curve (and their timing), cut off at the chips
            id: extrasDrawer
            property real progress: root.factsOpen ? 1 : 0
            Behavior on progress {
                NumberAnimation {
                    duration: root.factsOpen ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.factsOpen ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
                }
            }
            width: root._factsWidth
            height: extrasCol.implicitHeight * Math.min(1, progress)
            visible: progress > 0
            clip: true
            Column {
                id: extrasCol
                y: extrasCol.implicitHeight * (Math.min(1, extrasDrawer.progress) - 1)
                spacing: 3
                Repeater {
                    id: extrasRepeater
                    model: root._extraStats
                    onItemAdded: Qt.callLater(root._measureFacts)
                    onItemRemoved: Qt.callLater(root._measureFacts) // (Its count also decides the ⓘ)
                    Rectangle {
                        required property var modelData
                        required property int index
                        implicitWidth: 52 + extraLabel.implicitWidth + 24 + extraValue.implicitWidth + 14
                        onImplicitWidthChanged: Qt.callLater(root._measureFacts)
                        width: root._factsWidth
                        height: 46
                        color: Appearance.colors.colLayer3
                        topLeftRadius: Appearance.rounding.joined
                        topRightRadius: Appearance.rounding.joined
                        bottomLeftRadius: index === root._extraStats.length - 1 ? Appearance.rounding.small : Appearance.rounding.joined
                        bottomRightRadius: bottomLeftRadius
                        Rectangle {
                            x: 7; anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34
                            radius: 9
                            color: Appearance.colors.colLayer3Accent
                            MaterialSymbol { anchors.centerIn: parent; text: modelData.icon; iconSize: 18; color: Appearance.colors.colPrimary }
                        }
                        StyledText {
                            id: extraLabel
                            x: 52; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            id: extraValue
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: modelData.value
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: Appearance.colors.colOnLayer3
                        }
                    }
                }
            }
        }
    }
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
    // Measured once the page arrives, and again once something changes what's on disk: an install, an update
    // or mods coming in
    readonly property string _sizeKey: game ? [game.id, game.gameDir || "", installState, root._modsOnly].join("|") : ""
    on_SizeKeyChanged: if (_arrived) _measureSize()
    function _measureSize() {
        const key = _sizeKey;
        if (!game || _installSizeFor === key) return;
        if (game.gameDir || game.flatpakId) { // (A Flatpak added by hand has no game folder, only its data)
            _installSizeFor = key; _installSize = "…";
            sizeProc.modsDir = GameLauncherService.steamPaths(game)?.mods ?? "";
            sizeProc.command = ["du", "-sb", ...(game.gameDir ? [game.gameDir] : []), ...(sizeProc.modsDir ? [sizeProc.modsDir] : []),
                                ...(game.flatpakId ? [root._filesDir] : [])]; // A Flatpak's data
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
                    else game = (isNaN(game) ? 0 : game) + b; // The game folder and a Flatpak's data
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
        if (game.gameDir || game.flatpakId || root._sizeFromSteam)
            rows.push({ icon: "hard_drive", label: root._sizeFromSteam ? Translation.tr("Download size") : Translation.tr("Install size"),
                        value: root._installSize || "…" });
        const src = game.id.startsWith("steam_") ? "Steam" : game.id.startsWith("lutris_") ? "Lutris"
            : game.source === "Custom" ? Translation.tr("Added by you") : (game.source || "");
        if (src) rows.push({ icon: "storefront", label: Translation.tr("From"), value: src });
        return rows;
    }
    Item { // Back to the library, top-left
        anchors { left: parent.left; top: parent.top; leftMargin: 30; topMargin: 28 }
        width: backButton.implicitWidth; height: 36; z: 10
        RippleButton {
            id: backButton
            anchors.fill: parent
            implicitWidth: backRow.implicitWidth + 20
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
                implicitHeight: 36
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "arrow_back"; iconSize: 20
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Library")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
            onClicked: { root.backPressed(); focus = false; }
        }
    }
    Row { // Game actions, laid out under the Play button (slot reserved in sidebarContent)
        id: topLeftButtons
        x: Math.round(sidebarContent.x + actionRowSlot.x)
        y: Math.round(sidebarContent.y + actionRowSlot.y)
        spacing: 3; z: 11
        ToggleIcon {
            buttonRadiusBottomLeft: Appearance.rounding.normal // The group's corner
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
            width: root._stripCell; height: actionRowSlot.height
            buttonRadius: Appearance.rounding.joined; padding: 0
            colBackground: hasTags ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
            colBackgroundHover: hasTags ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            buttonColor: (hovered || activeFocus || tagMenuPopup.open) ? colBackgroundHover : colBackground
            property var gameTags: {
                const _ = GameLauncherService.tagsRevision;
                return game ? GameLauncherService.getGameTags(game.id) : [];
            }
            property bool hasTags: gameTags.length > 0
            contentItem: StripCell {
                iconName: "sell"
                on: tagIconBtn.hasTags
                count: tagIconBtn.gameTags.length
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
            width: root._stripLastCell; height: actionRowSlot.height; padding: 0
            buttonRadius: Appearance.rounding.joined
            buttonRadiusBottomRight: Appearance.rounding.normal // The group's corner
            colBackground: moreMenu.open ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
            colBackgroundHover: moreMenu.open ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            buttonColor: hovered ? colBackgroundHover : colBackground
            contentItem: StripCell {
                iconName: "more_horiz"
                on: moreMenu.open
            }
            onClicked: moreMenu.open = !moreMenu.open
            StyledToolTip { text: Translation.tr("More"); visible: !moreMenu.open && moreBtn.hovered }
        }
    }
    // ── Side menus (⋯ and tags): slide out of the left menu's right edge, level with their button ──
    // The ⋯, tags and install-where menus and the info pane: one at a time
    function _sideMenuOpened(menu) {
        root.metadataPaneOpen = false;
        for (const m of [moreMenu, tagMenuPopup, libraryMenu, launchMenu, webMenu]) if (m && m !== menu) m.open = false; // (m: not made yet at start-up)
    }
    onMetadataPaneOpenChanged: if (metadataPaneOpen) { moreMenu.open = false; tagMenuPopup.open = false; libraryMenu.open = false; launchMenu.open = false; webMenu.open = false; }
    SideDrawer {
        id: moreMenu
        paneW: 260 // Same as the tags menu; room for Uninstall's confirm note
        paneH: moreCol.implicitHeight + 24
        anchorCenterY: topLeftButtons.y + moreBtn.y + moreBtn.height / 2
        opener: moreBtn; exclusive: true
        Column {
            id: moreCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 3 // Joined, as the info drawer's pieces
            MoreItem {
                iconName: "folder_open"; label: Translation.tr("Open game folder")
                // Not when the menu has a Files row (Lutris games without a Steam id, games added by hand)
                visible: (game?.gameDir ?? "") !== "" && (game.id.startsWith("steam_") || root._lutrisSteamId !== "")
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
            Item { // A gap: the destructive one is a group of its own
                visible: uninstallItem.visible || removeItem.visible
                width: parent.width; height: 3
            }
            MoreItem {
                // Asks here instead of in Steam: the first click arms it, a second one uninstalls. Steam games
                // go without opening Steam: straight to it through the shell's Millennium plugin, else it
                // restarts in the tray if it's open; Lutris still asks itself
                id: uninstallItem
                property bool armed: false
                property bool steamOpen: false
                readonly property bool isSteam: (game?.source ?? "").toLowerCase() === "steam"
                // Mid-install it cancels it: the same uninstall stops the download and deletes what's been
                // downloaded
                readonly property bool cancels: root._installing
                iconName: cancels ? "cancel" : "delete_forever"
                label: armed ? Translation.tr("Click to confirm") : cancels ? Translation.tr("Cancel install") : Translation.tr("Uninstall")
                detail: !armed || !isSteam ? ""
                    : cancels ? Translation.tr("Stops the download · deletes it")
                    : steamOpen && !GameLauncherService.canControlDownloads ? Translation.tr("Restarts Steam · keeps saves")
                    : Translation.tr("Deletes files · keeps saves")
                filled: armed
                danger: true
                closesMenu: armed
                // Steam games mid-install or mid-update too (Lutris only uninstalls installed games)
                visible: (["installed", "updateRequired", "updatePaused", "updateQueued"].includes(root.installState)
                          || (isSteam && (root._installing || root.installState === "updating")))
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
    // The way to start it that Play uses without asking ("Always start this way" in launchMenu), -1 to ask
    readonly property var _launchDefaults: Config.options.gameLauncher.launchDefaults ?? []
    readonly property int launchDefault: {
        const option = game?.id ? GameLauncherService.launchDefaultFor(game.id) : -1;
        return option >= 0 && option < launchChoices.length ? option : -1;
    }
    function setLaunchDefault(option) { // -1 to ask again
        if (!game?.id) return;
        const rest = _launchDefaults.filter(e => !e.startsWith(game.id + ":"));
        Config.options.gameLauncher.launchDefaults = option >= 0 ? [...rest, `${game.id}:${option}`] : rest;
    }
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
        paneH: launchCol.implicitHeight + 24
        anchorCenterY: sidebarContent.y + playRow.y + playRow.height / 2
        opener: chooserButton.visible ? chooserButton : playButton; exclusive: true
        // The switch as this game has it each time (a click on it ends its binding, and the page is reused)
        onOpenChanged: if (open) alwaysSwitch.checked = root.launchDefault >= 0
        Column {
            id: launchCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 3 // Joined, as the info drawer's pieces
            Repeater {
                model: root.launchChoices
                MoreItem {
                    required property var modelData
                    // The first, unnamed one is the game itself; the others say what they are. The one Play
                    // always uses is filled (else the game itself)
                    iconName: modelData.index === 0 ? "play_arrow" : "tune"
                    filled: modelData.index === (root.launchDefault >= 0 ? root.launchDefault : 0)
                    label: modelData.label || (modelData.index === 0 ? Translation.tr("Play") : Translation.tr("Option %1").arg(modelData.index + 1))
                    detail: modelData.detail
                    onTriggered: {
                        if (alwaysSwitch.checked) root.setLaunchDefault(modelData.index);
                        launchMenu.open = false;
                        root.playPressed(root.game, modelData.index);
                    }
                }
            }
            Item { width: 1; height: 6 }
            RowLayout { // As Steam's default launch option: Play then starts the one picked without asking
                width: parent.width
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    text: Translation.tr("Always start this way")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledSwitch {
                    id: alwaysSwitch
                    Layout.rightMargin: 6
                    scale: 0.8
                    // Off: Play asks again. On: the next pick is remembered (until then, Play still asks)
                    onClicked: if (!checked) root.setLaunchDefault(-1)
                }
            }
        }
    }
    // ── Lutris's and added games' rows: what each does, and Web's menu of the game's pages ──
    readonly property var _webLinks: {
        const id = game?.id ?? "";
        const name = encodeURIComponent(game?.name || "");
        if (id.startsWith("custom_")) { // Added by you: a Flatpak's Flathub page, and the wiki
            const links = [];
            if (game.flatpakId) links.push({ icon: "storefront", label: "Flathub", url: "https://flathub.org/apps/" + game.flatpakId });
            links.push({ icon: "devices", label: "PCGamingWiki", url: "https://www.pcgamingwiki.com/w/index.php?search=" + name });
            return links;
        }
        if (!id.startsWith("lutris_")) return [];
        const steamId = root._lutrisSteamId;
        const links = [{ icon: "public", label: "Lutris.net", url: "https://lutris.net/games/" + game.id.substring(7) + "/" }];
        if (steamId !== "") links.push({ icon: "storefront", label: Translation.tr("Steam store"), url: "https://store.steampowered.com/app/" + steamId });
        links.push({ icon: "devices", label: "PCGamingWiki", url: "https://www.pcgamingwiki.com/w/index.php?search=" + name });
        // ProtonDB is about running Windows games, and with a Steam id it has its own row
        if (!root._runsNatively && steamId === "") links.push({ icon: "science", label: "ProtonDB", url: "https://www.protondb.com/search?q=" + name });
        return links;
    }
    property Item _webRow: null // The Web row, for its menu to open level with it
    property real _webRowCenter: 0
    function _menuAction(type, row) {
        switch (type) {
        case "files":
            Quickshell.execDetached(["xdg-open", root._filesDir]);
            break;
        case "lutris_app":
            Quickshell.execDetached(["lutris"]);
            break;
        case "protondb":
            Quickshell.execDetached(["xdg-open", "https://www.protondb.com/app/" + root._lutrisSteamId]);
            break;
        case "web":
            root._webRow = row;
            root._webRowCenter = row.mapToItem(root, 0, row.height / 2).y;
            webMenu.open = !webMenu.open;
            break;
        }
    }
    SideDrawer {
        id: webMenu
        paneW: 260
        paneH: webCol.implicitHeight + 24
        anchorCenterY: root._webRowCenter
        opener: root._webRow; exclusive: true
        Column {
            id: webCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 3 // Joined, as the info drawer's pieces
            Repeater {
                model: root._webLinks
                MoreItem {
                    required property var modelData
                    iconName: modelData.icon
                    label: modelData.label
                    onTriggered: { webMenu.open = false; Quickshell.execDetached(["xdg-open", modelData.url]); }
                }
            }
        }
    }
    SideDrawer { // Install where? One row per Steam library, with its free space
        id: libraryMenu
        paneW: 260
        paneH: libraryCol.implicitHeight + 24
        anchorCenterY: sidebarContent.y + playRow.y + playRow.height / 2
        opener: playButton; exclusive: true
        Column {
            id: libraryCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 3 // Joined, as the info drawer's pieces
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
        paneH: _tagPopupContent.implicitHeight + 24
        anchorCenterY: topLeftButtons.y + tagIconBtn.y + tagIconBtn.height / 2
        exclusive: true // No opener: it has a text field, so it stays while the pointer is away (a click outside closes it)
        MouseArea { anchors.fill: parent } // Keep clicks inside the card
        Column { // Joined pieces, as the info drawer's: what it is and its tags, adding one; suggestions apart
            id: _tagPopupContent
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 3
            InfoPiece { // Header: the icon in an accent square, how many
                implicitHeight: 52
                Rectangle {
                    x: 9; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 9
                    color: Appearance.colors.colLayer3Accent
                    MaterialSymbol { anchors.centerIn: parent; text: "sell"; iconSize: 18; fill: 1; color: Appearance.colors.colPrimary }
                }
                Column {
                    x: 54; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                    StyledText {
                        text: Translation.tr("Tags")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        text: tagIconBtn.hasTags
                            ? (tagIconBtn.gameTags.length === 1 ? Translation.tr("1 tag · click one to remove it")
                                : Translation.tr("%1 tags · click one to remove it").arg(tagIconBtn.gameTags.length))
                            : Translation.tr("No tags yet")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            InfoPiece { // The game's tags as chips; hovered, one turns red to remove it
                visible: tagIconBtn.hasTags
                implicitHeight: _tagFlow.implicitHeight + 20
                Flow {
                    id: _tagFlow
                    x: 10; y: 10; width: parent.width - 20; spacing: 6
                    Repeater {
                        model: tagIconBtn.gameTags
                        Rectangle {
                            id: _tagChip
                            required property string modelData
                            readonly property bool hovered: _tagChipMa.containsMouse
                            width: _tagChipRow.implicitWidth + 20; height: 28; radius: 9
                            color: hovered ? Appearance.colors.colLayer3Error : Appearance.colors.colLayer3Accent
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                id: _tagChipRow
                                anchors.centerIn: parent; spacing: 4
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: _tagChip.modelData
                                    font.pixelSize: Appearance.font.pixelSize.smaller
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
            }
            InfoPiece { // Adding one: a box inside the piece
                implicitHeight: 54
                Rectangle {
                    anchors { fill: parent; margins: 8 }
                    radius: 9
                    color: tagInputField.activeFocus ? Appearance.colors.colLayer4Hover : Appearance.colors.colLayer4
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
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "add"; iconSize: 18
                        color: tagInputField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                        TextInput {
                            id: tagInputField
                            anchors { left: _tagAddIcon.right; leftMargin: 8; right: parent.right; rightMargin: 14; top: parent.top; bottom: parent.bottom }
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.main
                            color: Appearance.colors.colOnLayer3
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
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                                visible: tagInputField.text.length === 0
                            }
                        }
                }
            }
            Item { width: 1; height: 3; visible: _tagSuggest.visible } // A gap: suggestions are a group of their own
            InfoPiece { // Suggestions: tags used on other games
                id: _tagSuggest
                property var _allTags: { const _ = GameLauncherService.tagsRevision; return GameLauncherService.allTags; }
                property var _availableTags: {
                    const input = tagInputField.text.trim().toLowerCase();
                    return _allTags.filter(t => tagIconBtn.gameTags.indexOf(t) < 0 && (input.length === 0 || t.toLowerCase().indexOf(input) >= 0));
                }
                visible: _availableTags.length > 0
                implicitHeight: _suggestCol.implicitHeight + 22
                Column {
                    id: _suggestCol
                    x: 10; y: 11; width: parent.width - 20; spacing: 8
                    StyledText {
                        leftPadding: 2
                        text: Translation.tr("Suggestions")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: _tagSuggest._availableTags
                            Rectangle {
                                id: _suggestChip
                                required property string modelData
                                width: _suggestRow.implicitWidth + 20; height: 28; radius: 9
                                color: _suggestMa.containsMouse ? Appearance.colors.colLayer4Hover : Appearance.colors.colLayer4
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
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer3
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
    }
    ColumnLayout {
        id: sidebarContent
        anchors { left: parent.left; leftMargin: 30; verticalCenter: parent.verticalCenter; verticalCenterOffset: 22 } // Room for the back arrow above
        width: 270; z: 10
        spacing: 0
        RowLayout { // Play, and beside it, with a way it always starts, the menu of ways: a split button, one pill
            // in two, their inner corners small
            id: playRow
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 4
            RippleButton {
                id: playButton
                Layout.fillWidth: true
                Layout.preferredHeight: timeLine !== "" ? 58 : 52
                buttonRadius: Appearance.rounding.joined
                buttonRadiusTopLeft: Appearance.rounding.normal
                buttonRadiusTopRight: chooserButton.visible ? Appearance.rounding.joined : Appearance.rounding.normal
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
                // Under Play (installed, nothing downloading): your time in it and when you last played
                readonly property string timeLine: {
                    if (!game || playing || root.installState !== "installed" || root._downloadPhase !== "") return "";
                    const h = Math.floor((game.playtime ?? 0) / 60);
                    const hours = (game.playtime ?? 0) <= 0 ? "" : h > 0 ? Translation.tr("%1 h played").arg(h) : Translation.tr("< 1 h played");
                    return [hours, root._lastPlayedText].filter(t => t).join("  ·  ");
                }
                function activate() {
                    if (playing) {
                        const matchers = GameLauncherService.processMatchers(game);
                        if (matchers.length > 0)
                            Quickshell.execDetached(["python3", "-I", Quickshell.shellPath("scripts/game-launcher/focus_game.py"), ...matchers]);
                        GlobalStates.gameLauncherOpen = false;
                    }
                    // While a download runs, the button shows the launcher's Downloads panel instead of starting it
                    // again. A paused one resumes (or opens Steam's downloads, without pause and resume on)
                    else if (root._paused) GameLauncherService.controlDownload("resume", game.id.substring(6));
                    // Queued: it's set to download already, so the panel (with its Download now) as while it downloads
                    else if (root._downloading || root._queued) root.openPanel = root.openPanel === "downloads" ? "" : "downloads";
                    // More than one Steam library: ask which here, instead of Steam's install dialog
                    else if (root.installState === "notInstalled" && (game?.id ?? "").startsWith("steam_")
                             && GameLauncherService.steamLibraries.length > 1) libraryMenu.open = !libraryMenu.open;
                    // More than one way to start it (Project Zomboid: Play or Compatibility Mode): the one it always
                    // starts with, else ask here, not in Steam
                    else if (root.installState === "installed" && root.launchChoices.length > 1) {
                        if (root.launchDefault >= 0) root.playPressed(game, root.launchDefault);
                        else launchMenu.open = !launchMenu.open;
                    }
                    else root.playPressed(game, -1);
                }
                onClicked: activate()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activate(); event.accepted = true; }
                }
                readonly property var _look: playing ? { icon: "", text: Translation.tr("Playing") } : ({
                    "notInstalled":   { icon: "download",    text: Translation.tr("Install") },
                    "installing":     { icon: "downloading", text: Translation.tr("Installing") },
                    "installPaused":  { icon: "downloading", text: Translation.tr("Resume install") },
                    "installQueued":  { icon: "schedule",    text: Translation.tr("Queued") },
                    "updateQueued":   { icon: "schedule",    text: Translation.tr("Update queued") },
                    "updating":       { icon: "downloading", text: Translation.tr("Updating") },
                    "updateRequired": { icon: "update",      text: Translation.tr("Update & play") },
                    "updatePaused":   { icon: "downloading", text: Translation.tr("Resume update") },
                    "uninstalling":   { icon: "delete",      text: Translation.tr("Uninstalling…") },
                    "installed":      { icon: "play_arrow",  text: Translation.tr("Play") }
                })[root.installState] ?? { icon: "play_arrow", text: Translation.tr("Play") }
                contentItem: Item {
                    implicitHeight: playButton.Layout.preferredHeight
                    Rectangle { // Download progress (the game's, or its mods'), filling the button from the left
                        visible: root._downloadPhase !== "" && root.downloadProgress >= 0
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.max(0, root.downloadProgress)
                        radius: Appearance.rounding.joined
                        topLeftRadius: Appearance.rounding.normal
                        color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.8)
                        Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    }
                    Column {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -4
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
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
                                if (root._downloading || root._paused || root._queued) return playButton._look.text + (pct ? " " + pct : "");
                                if (root._modsOnly) return playButton._look.text + "  ·  " + Translation.tr("mods") + pct;
                                return playButton._look.text;
                            }
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.5
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: playButton.timeLine !== ""
                        text: playButton.timeLine
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.3)
                    }
                    }
                }
            }
            RippleButton { // The other ways to start it, once Play starts one without asking (launchDefault)
                id: chooserButton
                visible: root.installState === "installed" && !playButton.playing && root.launchDefault >= 0
                Layout.preferredWidth: 44
                Layout.preferredHeight: playButton.Layout.preferredHeight
                buttonRadius: Appearance.rounding.joined
                buttonRadiusTopRight: Appearance.rounding.normal
                padding: 0
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                buttonColor: (hovered || launchMenu.open) ? colBackgroundHover : colBackground
                onClicked: launchMenu.open = !launchMenu.open
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "chevron_right"
                    iconSize: 20
                    color: Appearance.colors.colOnPrimary
                    rotation: launchMenu.open ? 180 : 0 // Points back at the menu while it's out
                    Behavior on rotation { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
                StyledToolTip { text: Translation.tr("Other ways to start it") }
            }
        }
        Item { // Where the action buttons go, under Play (topLeftButtons is positioned on it): joined icon squares
            id: actionRowSlot
            Layout.fillWidth: true
            Layout.leftMargin: 8; Layout.rightMargin: 8
            Layout.topMargin: 3; Layout.bottomMargin: 10
            Layout.preferredHeight: 38
        }
        readonly property bool _isSteam: game?.id?.startsWith("steam_") ?? false
        readonly property bool _isLutris: game?.id?.startsWith("lutris_") ?? false
        readonly property bool _isCustom: game?.id?.startsWith("custom_") ?? false
        // Added by you: as a Lutris game without a Steam id, less Lutris (Files counts a Flatpak's data)
        readonly property var _customActions: {
            const actions = [{ icon: "perm_media", label: qsTr("Captures"), type: "screenshots" }];
            if (root._filesDir !== "") actions.push({ icon: "folder_open", label: qsTr("Files"), type: "files" });
            actions.push({ icon: "public", label: qsTr("Web"), type: "web" });
            return actions;
        }
        readonly property var _steamActions: [ // The panels, then the browser link
                { icon: "newspaper",            label: qsTr("News"),         type: "news" },
                { icon: "perm_media",           label: qsTr("Captures"),     type: "screenshots" },
                { icon: "emoji_events",         label: qsTr("Achievements"), type: "achievements" },
                { icon: "science",              label: qsTr("ProtonDB"),     url: "https://www.protondb.com/app/" }
        ]
        // Lutris: with a Steam id, Steam's rows (News, Captures, Achievements once it has any, ProtonDB for Wine);
        // without, Captures, its files and Lutris. Both end in Web: the game's pages, in a side menu
        readonly property var _lutrisActions: {
            const steamId = root._lutrisSteamId;
            const actions = [];
            if (steamId !== "") {
                actions.push({ icon: "newspaper", label: qsTr("News"), type: "news" });
                actions.push({ icon: "perm_media", label: qsTr("Captures"), type: "screenshots" });
                if (GameLauncherService.achievementsFor === (game?.id ?? "") && (GameLauncherService.achievements?.total ?? 0) > 0)
                    actions.push({ icon: "emoji_events", label: qsTr("Achievements"), type: "achievements" });
                if (!root._runsNatively) actions.push({ icon: "science", label: qsTr("ProtonDB"), type: "protondb" });
            } else {
                actions.push({ icon: "perm_media", label: qsTr("Captures"), type: "screenshots" });
                if (root._filesDir !== "") actions.push({ icon: "folder_open", label: qsTr("Files"), type: "files" });
                actions.push({ icon: "sports_esports", label: qsTr("Lutris"), type: "lutris_app" });
            }
            actions.push({ icon: "public", label: qsTr("Web"), type: "web" });
            return actions;
        }
        ColumnLayout { // The menu: joined rows, each saying what's inside
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 4
            Repeater {
                id: sidebarRepeater
                model: sidebarContent._isSteam ? sidebarContent._steamActions
                     : sidebarContent._isLutris ? sidebarContent._lutrisActions
                     : sidebarContent._isCustom ? sidebarContent._customActions
                     : []
                onCountChanged: Qt.callLater(root._refreshSidebarButtons)
                RippleButton {
                    id: actionBtn
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50 // Every row the same, with a line under its name or not
                    buttonRadius: Appearance.rounding.joined
                    buttonRadiusTopLeft: index === 0 ? Appearance.rounding.normal : Appearance.rounding.joined
                    buttonRadiusTopRight: buttonRadiusTopLeft
                    buttonRadiusBottomLeft: index === sidebarRepeater.count - 1 ? Appearance.rounding.normal : Appearance.rounding.joined
                    buttonRadiusBottomRight: buttonRadiusBottomLeft
                    padding: 0
                    activeFocusOnTab: true
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    // Its panel is open: tinted, with the icon and label in the accent (accent = active)
                    readonly property bool panelOpen: root.openPanel !== "" && root.openPanel === modelData.type
                        || modelData.type === "web" && webMenu.open
                    readonly property bool lit: hovered || activeFocus
                    readonly property bool isLink: !root.panelTypes.includes(modelData.type) && modelData.type !== "web"
                    buttonColor: panelOpen ? Appearance.colors.colLayer3Accent
                        : lit ? colBackgroundHover : colBackground
                    // News: how many posts are new since its panel was last opened, and the newest one's title
                    readonly property bool newsLoaded: modelData.type === "news" && GameLauncherService.newsFor === (game?.id ?? "")
                    readonly property int unread: newsLoaded ? GameLauncherService.unreadNews : 0
                    readonly property string headline: newsLoaded ? (GameLauncherService.news[0]?.title ?? "") : ""
                    // Achievements: how many of how many
                    readonly property var achieved: modelData.type === "achievements" && GameLauncherService.achievementsFor === (game?.id ?? "")
                        && (GameLauncherService.achievements?.total ?? 0) > 0 ? GameLauncherService.achievements : null
                    readonly property string tier: modelData.label === "ProtonDB" ? (game?.protondbTier ?? "") : ""
                    // Lutris and added games: its files' size and folder, how it runs and the time Lutris tracked, which pages
                    readonly property string menuLine: sidebarContent._isSteam ? ""
                        : modelData.type === "files" ? [root._installSize === "…" ? "" : root._installSize, root._filesDirShort].filter(t => t !== "").join("  ·  ")
                        : modelData.type === "lutris_app" ? [root._runnerLabel, (game?.playtime ?? 0) > 0
                            ? Translation.tr("%1 tracked").arg(game.playtime >= 60 ? Math.floor(game.playtime / 60) + " h" : game.playtime + " min") : ""].filter(t => t !== "").join("  ·  ")
                        : modelData.type === "web" ? root._webLinks.map(l => l.label).join("  ·  ")
                        : ""
                    // The line under the name: what's inside
                    readonly property string subtitle: headline !== "" ? headline
                        : modelData.type === "screenshots" ? (root._peekCount === 0 ? Translation.tr("None yet")
                            : root._peekCount === 1 ? Translation.tr("1 capture") : Translation.tr("%1 captures").arg(root._peekCount))
                        : achieved ? Translation.tr("%1 of %2 unlocked").arg(achieved.unlocked).arg(achieved.total)
                        : tier !== "" ? Translation.tr("Rated %1").arg(tier.charAt(0).toUpperCase() + tier.slice(1))
                        : menuLine
                    contentItem: Item {
                        implicitHeight: actionBtn.Layout.preferredHeight
                        Rectangle { // The icon in a square: accent for a panel here, grey for the browser. Its panel open (the
                            // row tinted as the square): solid accent, so it still stands out; hovered, a step up
                            id: actionIcon
                            anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                            width: 32; height: 32; radius: 9
                            color: actionBtn.panelOpen ? Appearance.colors.colPrimary
                                : actionBtn.isLink ? (actionBtn.lit ? Appearance.colors.colLayer4Hover : Appearance.colors.colLayer4)
                                : actionBtn.lit ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Accent
                            Behavior on color { ColorAnimation { duration: 150 } }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: actionBtn.modelData.icon; iconSize: 17
                                fill: actionBtn.panelOpen ? 1 : 0
                                color: actionBtn.panelOpen ? Appearance.colors.colOnPrimary
                                    : actionBtn.isLink ? Appearance.colors.colOnLayer3 : Appearance.colors.colPrimary
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                        Column {
                            anchors { left: actionIcon.right; leftMargin: 10; right: detail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Row {
                                spacing: 6
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, detail.x - actionIcon.x - actionIcon.width - 20)
                                    elide: Text.ElideRight
                                    text: actionBtn.modelData.label
                                    color: actionBtn.panelOpen ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: Font.Medium
                                }
                                Rectangle { // New posts
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: actionBtn.unread > 0
                                    width: unreadText.implicitWidth + 10; height: 16; radius: 5
                                    color: Appearance.colors.colPrimary
                                    StyledText {
                                        id: unreadText
                                        anchors.centerIn: parent
                                        text: Translation.tr("%1 new").arg(actionBtn.unread > 9 ? "9+" : actionBtn.unread)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                            StyledText { // What's inside: the newest post, how many captures, how far, the rating
                                width: parent.width
                                visible: actionBtn.subtitle !== ""
                                elide: Text.ElideRight
                                text: actionBtn.subtitle
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        Row { // Where it goes
                            id: detail
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: actionBtn.isLink ? "open_in_new" : "chevron_right"
                                iconSize: actionBtn.isLink ? 15 : 17
                                color: Appearance.colors.colSubtext
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
                        } else {
                            root._menuAction(modelData.type, actionBtn); // Lutris and added games
                        }
                    }
                    Keys.onPressed: event => { if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { clicked(); event.accepted = true; } }
                }
            }
        }
    }
    // Five, 3 px apart, each a whole number of pixels (a fractional width put the icons between pixels, a touch off
    // centre). The last (More) takes the pixels left over, so the row still ends level with Play (split between
    // the ends instead, an odd width put those two icons half a pixel off)
    readonly property int _stripCell: Math.floor((actionRowSlot.width - 12) / 5)
    readonly property int _stripLastCell: Math.round(actionRowSlot.width) - 12 - 4 * _stripCell
    // For the Captures row: how many screenshots (find_screenshots.py, newest first, its folder on the first line)
    // and clips (a last "clips" line) the game has
    property int _peekCount: 0
    Process {
        id: capturesPeek
        command: ["bash", "-c", 'python3 -I "$1" "$2" "$3" "$4" "$5"; printf "clips\t%s\n" "$(find "$6" -maxdepth 1 -type f \\( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mov" \\) 2>/dev/null | wc -l)"',
                  "_", Quickshell.shellPath("scripts/game-launcher/find_screenshots.py"), (root.game?.id ?? "").startsWith("steam_") ? root.game.id.substring(6) : "",
                  root.game?.gameDir ?? "", root.game?.flatpakId ?? "", root.game?.name ?? "", GameClips.folderFor(root.game?.name ?? "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l && !l.startsWith("folder\t"));
                const clipsLine = lines.find(l => l.startsWith("clips\t"));
                const shots = lines.filter(l => !l.startsWith("clips\t")).map(l => l.split("\t").slice(3).join("\t"));
                root._peekCount = shots.length + (parseInt(clipsLine?.split("\t")[1] ?? "0") || 0);
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
    readonly property bool _otherSideMenuOpen: moreMenu.open || tagMenuPopup.open || webMenu.open
    function _syncInfoHover() {
        if (infoTabHover.hovered || infoPaneHover.hovered) { metadataCloseTimer.stop(); root.metadataPaneOpen = true; }
        else metadataCloseTimer.restart();
    }
    Timer {
        id: metadataCloseTimer; interval: 300
        onTriggered: root.metadataPaneOpen = infoTabHover.hovered || infoPaneHover.hovered
    }
    Item { // Reveal tab: a slim accent bar on the menu's edge. Hovered or clicked, it opens the drawer, which then
        // covers it. Its hover area is wider than the bar
        id: metadataNotch
        visible: root._currentMetadata !== null
        x: sidebarPanel.x + sidebarPanel.width
        y: sidebarPanel.y + (sidebarPanel.height - height) / 2
        z: 9
        width: 20; height: 64
        opacity: infoDrawer.offset > 0.5 ? 1 : 0 // Hidden once the drawer covers it
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 3
            width: 6; radius: 3
            height: 40
            color: Appearance.colors.colPrimary
            opacity: 0.6
        }
        HoverHandler { id: infoTabHover; enabled: !root._otherSideMenuOpen; onHoveredChanged: root._syncInfoHover() }
        TapHandler { enabled: !root._otherSideMenuOpen; onTapped: root.metadataPaneOpen = !root.metadataPaneOpen }
    }
    SideDrawer {
        id: infoDrawer
        open: root.metadataPaneOpen && root._currentMetadata !== null
        paneW: 280
        paneH: Math.min(_metaCol.implicitHeight + 24, sidebarPanel.height - 32)
        anchorCenterY: sidebarPanel.y + sidebarPanel.height / 2
        HoverHandler { id: infoPaneHover; onHoveredChanged: root._syncInfoHover() }
        Flickable {
            anchors { fill: parent; margins: 12 }
            contentHeight: _metaCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            // Joined pieces, as the facts' drop-down: the score, then a row each, the description last
            Column {
                id: _metaCol
                width: parent.width
                spacing: 3
                readonly property var meta: root._currentMetadata
                readonly property bool _lutris: game?.id?.startsWith("lutris_") ?? false
                readonly property string _devs: meta?.developers?.join(", ") ?? ""
                readonly property string _pubs: meta?.publishers?.join(", ") ?? ""
                InfoPiece { // Metacritic: the score in an accent square, what it means beside it
                    id: scorePiece
                    visible: _metaCol.meta?.metacritic != null
                    implicitHeight: 58
                    readonly property int score: _metaCol.meta?.metacritic ?? 0
                    Rectangle {
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 11
                        color: Appearance.colors.colLayer3Accent
                        StyledText {
                            anchors.centerIn: parent
                            text: scorePiece.score
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: Appearance.colors.colPrimary
                        }
                    }
                    Column {
                        x: 60; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        StyledText {
                            text: scorePiece.score >= 75 ? Translation.tr("Favorable reviews")
                                : scorePiece.score >= 50 ? Translation.tr("Mixed reviews") : Translation.tr("Unfavorable reviews")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            text: "Metacritic"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                // Who made it: one row when the developer is the publisher too
                InfoRow { iconName: "code"; label: _metaCol._devs === _metaCol._pubs ? Translation.tr("Made by") : Translation.tr("Developer"); value: _metaCol._devs }
                InfoRow { iconName: "storefront"; label: Translation.tr("Publisher"); value: _metaCol._pubs !== _metaCol._devs ? _metaCol._pubs : "" }
                InfoRow { iconName: "calendar_month"; label: Translation.tr("Released"); value: _metaCol.meta?.releaseDate ?? "" }
                // Lutris games: what the Lutris database knows (Steam games have the store's details above)
                InfoRow { iconName: "category"; label: Translation.tr("Genres"); value: _metaCol._lutris ? (_metaCol.meta?.genres ?? []).join(", ") : "" }
                InfoRow { iconName: "devices"; label: Translation.tr("Platforms"); value: _metaCol._lutris ? (_metaCol.meta?.platforms ?? []).join(", ") : "" }
                InfoRow { iconName: root._runsNatively ? "terminal" : "wine_bar"; label: Translation.tr("Runs on"); value: root._runnerLabel }
                InfoPiece { // A line about it, last
                    visible: (_metaCol.meta?.description ?? "") !== ""
                    implicitHeight: aboutText.implicitHeight + 24
                    StyledText {
                        id: aboutText
                        x: 14; y: 12; width: parent.width - 28
                        text: GameLauncherService.decodeEntities(_metaCol.meta?.description ?? "")
                        textFormat: Text.PlainText // Store text, never markup
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        lineHeight: 1.25
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
    // A switch of the action row: a joined square, tinted in the accent while it's on; its name in its tooltip
    component ToggleIcon: RippleButton {
        id: ti
        property string iconName
        property bool on: false
        property string tip
        signal flipped() // (not toggled(): buttons have that already)
        width: root._stripCell; height: actionRowSlot.height
        buttonRadius: Appearance.rounding.joined; padding: 0
        colBackground: on ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
        colBackgroundHover: on ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        buttonColor: (hovered || activeFocus) ? colBackgroundHover : colBackground
        contentItem: StripCell {
            id: tiCell
            iconName: ti.iconName
            on: ti.on
        }
        onClicked: { if (!game) return; ti.flipped(); tiCell.bounce(); focus = false; }
        StyledToolTip { text: ti.tip }
    }
    // A cell of the action row under Play: its icon, in the accent (filled) when on, and a small count (Tags)
    component StripCell: Item {
        id: cell
        property string iconName
        property bool on: false
        property int count: 0
        function bounce() { cellBounce.start(); }
        implicitHeight: 38
        MaterialSymbol {
            id: cellIcon
            anchors.centerIn: parent
            text: cell.iconName; iconSize: 20
            font.hintingPreference: Font.PreferNoHinting // Full hinting snapped the outlines to the pixel grid: they looked squashed
            fill: cell.on ? 1 : 0
            color: cell.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
            Behavior on fill { NumberAnimation { duration: 200 } }
            Behavior on color { ColorAnimation { duration: 200 } }
            SequentialAnimation {
                id: cellBounce
                NumberAnimation { target: cellIcon; property: "scale"; to: 1.4; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: cellIcon; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
            }
        }
        Rectangle { // How many (Tags)
            visible: cell.count > 0
            x: cellIcon.x + cellIcon.width - 6; y: cellIcon.y - 5
            width: Math.max(15, countText.implicitWidth + 8); height: 14; radius: 7
            color: Appearance.colors.colPrimary
            StyledText {
                id: countText
                anchors.centerIn: parent
                text: cell.count > 9 ? "9+" : cell.count
                font.pixelSize: 9
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({}) // Not Roboto Flex's tuning
                color: Appearance.colors.colOnPrimary
            }
        }
    }
    // A row of a side menu (⋯, install where, start how): a piece joined to the rows beside it, as the info drawer's,
    // the icon in an accent square (red for a destructive one; solid while it's armed)
    component MoreItem: RippleButton {
        id: mi
        property string iconName
        property string label
        property string detail: "" // A second, smaller line under the label (fits in the same height)
        property bool filled: false // Solid square behind the icon: armed/active
        property bool closesMenu: true
        property bool danger: false
        signal triggered()
        readonly property color accent: danger ? Appearance.colors.colError : Appearance.colors.colPrimary
        width: parent ? parent.width : 200
        height: visible ? 46 : 0 // Never changes: a taller item would resize and move the open menu
        readonly property bool settingsRow: true
        GroupCorners { id: miCorners; item: mi; outer: Appearance.rounding.small }
        buttonRadius: Appearance.rounding.joined
        buttonRadiusTop: miCorners.top
        buttonRadiusBottom: miCorners.bottom
        padding: 0
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: danger ? Appearance.colors.colLayer3ErrorHover : Appearance.colors.colLayer3Hover
        colRipple: ColorUtils.transparentize(accent, 0.75)
        onClicked: { const close = closesMenu; if (game) mi.triggered(); if (close) moreMenu.open = false; }
        contentItem: Item {
            Row {
                anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                spacing: 11
                Rectangle {
                    width: 32; height: 32; radius: 9
                    color: mi.filled ? mi.accent : mi.danger ? Appearance.colors.colLayer3Error : Appearance.colors.colLayer3Accent
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    MaterialSymbol {
                        anchors.centerIn: parent; text: mi.iconName; iconSize: 17
                        color: mi.filled ? (mi.danger ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary) : mi.accent
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: mi.width - 7 - 32 - 11 - 12 // What's left of the row: long text is cut off, not spilled
                    StyledText { width: parent.width; elide: Text.ElideRight; text: mi.label; font.pixelSize: Appearance.font.pixelSize.smallie; color: mi.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer3 }
                    StyledText { width: parent.width; elide: Text.ElideRight; visible: mi.detail !== ""; text: mi.detail; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                }
            }
        }
    }
    // A piece of the info drawer: joined to the ones beside it (rounded at the group's ends), as Settings' rows
    component InfoPiece: Rectangle {
        id: piece
        default property alias content: pieceBody.data
        width: parent?.width ?? 0
        readonly property bool settingsRow: true
        GroupCorners { id: pieceCorners; item: piece; outer: Appearance.rounding.small }
        topLeftRadius: pieceCorners.top
        topRightRadius: pieceCorners.top
        bottomLeftRadius: pieceCorners.bottom
        bottomRightRadius: pieceCorners.bottom
        color: Appearance.colors.colLayer3
        height: implicitHeight
        Item { id: pieceBody; anchors.fill: parent }
    }
    // A row of it: the icon in an accent square, the name, the value on the right. Hidden without a value
    component InfoRow: InfoPiece {
        id: infoRow
        property string iconName: ""
        property string label: ""
        property string value: ""
        visible: value !== ""
        implicitHeight: 46
        Rectangle {
            x: 7; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 9
            color: Appearance.colors.colLayer3Accent
            MaterialSymbol { anchors.centerIn: parent; text: infoRow.iconName; iconSize: 18; color: Appearance.colors.colPrimary }
        }
        StyledText {
            id: infoLabel
            x: 52; anchors.verticalCenter: parent.verticalCenter
            text: infoRow.label
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
        StyledText {
            anchors { left: infoLabel.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: infoRow.value
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnLayer3
        }
    }
}
