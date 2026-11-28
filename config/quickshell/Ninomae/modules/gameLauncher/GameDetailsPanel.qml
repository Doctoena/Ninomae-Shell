import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
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
            GameLauncherService.loadNews(game); // For the News row: how many posts are new (cached an hour)
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
                GradientStop { position: 0.28; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 0.8 : 0.25) }
                GradientStop { position: 0.6; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 1 : 0.75) }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, bannerFrame._light ? 1 : 0.6) }
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
        // Its shape by what shows (cropped to its visible part, GameLauncherService.logoClip), else the whole file's.
        // Not its implicit size: that follows the size it's given here, a binding loop
        readonly property var crop: GameLauncherService.logoClip(root._logoSource) // (Not "clip": that's Item's own)
        readonly property real aspectRatio: crop ? crop.width / crop.height : sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1.0
        width: Math.min(parent.width * 0.5, 650)
        height: aspectRatio > 2.5 ? Math.min(parent.height * 0.35, 160)
             : aspectRatio > 1.5  ? Math.min(parent.height * 0.45, 200)
             :                      Math.min(parent.height * 0.5, 250)
        source: root._logoSource
        sourceClipRect: crop ?? Qt.rect(0, 0, 0, 0) // Centred by what shows, not its canvas (empty: the whole file)
        mipmap: true
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
    GlassEdge { // The art's edge, as the panels' pictures
        anchors.fill: bannerFrame
        radius: Appearance.rounding.normal
        z: 8
        opacity: bannerFrame.opacity
    }
    Rectangle {
        id: sidebarPanel
        anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: 16; bottom: parent.bottom; bottomMargin: 16 }
        width: sidebarContent.width + 28
        color: "transparent"; z: 5
        // Base fill behind the Play button and menu, curving out into the art at the top and bottom of its right edge
        // (as the bar's drawers curve into the bar), so the art's corners round off where it meets the rail. Pushed 1px
        // past the art on the outer edges so its antialiased corner can't show through as a thin arc.
        // Glass panels off: drawn in the panel's colour. On: only the shape, the mask for the frost under it
        Shape {
            id: railShape
            readonly property real r: 28 // The curves out into the art (rounder than the corners: the rail's the big shape)
            readonly property real rl: Appearance.rounding.normal // The rail's own left corners
            readonly property real edge: width - r // The rail's right edge
            x: -1; y: -1
            width: parent.width + 1 + r; height: parent.height + 2
            visible: !Appearance.colors.glassOn
            layer.enabled: Appearance.colors.glassOn
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Appearance.colors.glassOn ? "white" : Appearance.m3colors.m3background
                strokeWidth: -1
                startX: railShape.rl; startY: 0
                PathLine { x: railShape.width; y: 0 }
                PathArc { x: railShape.edge; y: railShape.r; radiusX: railShape.r; radiusY: railShape.r; direction: PathArc.Counterclockwise }
                PathLine { x: railShape.edge; y: railShape.height - railShape.r }
                PathArc { x: railShape.width; y: railShape.height; radiusX: railShape.r; radiusY: railShape.r; direction: PathArc.Counterclockwise }
                PathLine { x: railShape.rl; y: railShape.height }
                PathArc { x: 0; y: railShape.height - railShape.rl; radiusX: railShape.rl; radiusY: railShape.rl }
                PathLine { x: 0; y: railShape.rl }
                PathArc { x: railShape.rl; y: 0; radiusX: railShape.rl; radiusY: railShape.rl }
            }
        }
        // Glass: the game art under the rail, frosted, under the rail's tint at 80 % (the art is far brighter than
        // what's behind the rest of the panel). Hyprland can't blur what the shell draws itself, so the frost is the
        // art decoded small and scaled back up (no blur shader: a blur layer on the launcher hung the GPU before)
        Item {
            visible: Appearance.colors.glassOn
            x: railShape.x; y: railShape.y; width: railShape.width; height: railShape.height
            opacity: bannerFrame.opacity
            clip: true
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: railShape
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0 // Keeps the edge antialiased
            }
            FrostArt { artX: 1; artY: 1 } // Lined up with the art's frame (the shape reaches a pixel past the rail)
        }
        Canvas { // A soft shadow cast onto the art beside the rail, so the rail reads as glass laid over the picture. It
            // follows the edge round both curves: a fade down the straight part, and in each curve one from the curve in
            // toward its centre, eased out and gone by three quarters of the way, so they meet seamlessly and end softly.
            // Painted once (again only when the rail changes size)
            id: railShadow
            readonly property real r: railShape.r
            x: parent.width; y: railShape.y
            width: r; height: railShape.height
            z: -1 // Under the rail's frost
            opacity: bannerFrame.opacity
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const r = width, h = height;
                // Strength by how far out from the edge, as a fraction of r: eased, nothing from 0.75
                const stops = [[0, 0.5], [0.25, 0.2], [0.5, 0.05], [0.75, 0]];
                const lin = c.createLinearGradient(0, 0, r, 0);
                for (const [p, a] of stops) lin.addColorStop(p, `rgba(0,0,0,${a})`);
                c.fillStyle = lin;
                c.fillRect(0, r, r, h - 2 * r);
                for (const cy of [r, h - r]) { // The curves: a quarter circle each, its gradient from the curve inward
                    const rad = c.createRadialGradient(r, cy, 0, r, cy, r);
                    for (const [p, a] of stops) rad.addColorStop(1 - p, `rgba(0,0,0,${a})`);
                    c.fillStyle = rad;
                    c.beginPath();
                    c.moveTo(r, cy);
                    if (cy === r) c.arc(r, cy, r, Math.PI, 1.5 * Math.PI, false);
                    else c.arc(r, cy, r, 0.5 * Math.PI, Math.PI, false);
                    c.closePath();
                    c.fill();
                    // Toward the tip, where the curve thins to nothing along the art's edge, its shadow goes too: near
                    // the tip the curve runs close to the shadow's side, where it'd stop in a line. Taken out from 30 %
                    // of the way from the straight edge to the tip, all of it by 85 %
                    c.save();
                    c.clip();
                    c.globalCompositeOperation = "destination-out";
                    const tip = cy === r ? 0 : h;
                    const out = c.createLinearGradient(0, cy, 0, tip);
                    out.addColorStop(0.3, "rgba(0,0,0,0)");
                    out.addColorStop(0.85, "rgba(0,0,0,1)");
                    c.fillStyle = out;
                    c.fillRect(0, Math.min(cy, tip), r, r);
                    c.restore();
                }
            }
        }
        Shape { // A fine light down the rail's edge and round both curves. Where a side menu leaves the edge it parts, and
            // the menu's own light (SideDrawer's rim) carries it out round the menu and back
            id: railRim
            // The gap, in this shape's coordinates (it sits a pixel above the panel): the menu's joins, top and bottom
            readonly property Item menu: root._sideMenuShown
            readonly property real gapTop: menu ? menu._rim[0].y + 1 : height / 2
            readonly property real gapBottom: menu ? menu._rim[15].y + 1 : height / 2
            x: railShape.x; y: railShape.y; width: railShape.width; height: railShape.height
            opacity: bannerFrame.opacity
            preferredRendererType: Shape.CurveRenderer
            RimPath {
                startX: railShape.width; startY: 0.5
                PathArc { x: railShape.edge + 0.5; y: railShape.r; radiusX: railShape.r - 0.5; radiusY: railShape.r - 0.5; direction: PathArc.Counterclockwise }
                PathLine { x: railShape.edge + 0.5; y: Math.max(railShape.r, railRim.gapTop) }
            }
            RimPath {
                startX: railShape.edge + 0.5; startY: Math.min(railShape.height - railShape.r, railRim.gapBottom)
                PathLine { x: railShape.edge + 0.5; y: railShape.height - railShape.r }
                PathArc { x: railShape.width; y: railShape.height - 0.5; radiusX: railShape.r - 0.5; radiusY: railShape.r - 0.5; direction: PathArc.Counterclockwise }
            }
        }
    }
    readonly property color _rimColor: ColorUtils.transparentize("white", 0.84) // The rail's edge light, and its menus'
    // A stretch of that light: flat ends, so where the rail's meets a menu's they join exactly (square caps overlapped
    // as a brighter dot)
    component RimPath: ShapePath {
        fillColor: "transparent"
        strokeColor: root._rimColor
        strokeWidth: 1
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin
    }
    // The side menu out of the rail, if any (its edge light takes over from the rail's where it joins)
    readonly property Item _sideMenuShown: [moreMenu, launchMenu, webMenu, libraryMenu, tagMenuPopup, infoDrawer].find(d => d.visible && d._shown >= 1) ?? null
    readonly property var _rimNone: Array(16).fill(Qt.point(0, 0)) // A side menu's light points while it's tucked away
    readonly property real _railClear: railShape.r + 20 + 14 // How far the side menus keep from the rail's top and foot
    readonly property real _playRadius: 22 // Play and the well, rounder with the rail's curves
    // The rows share out the rail's height (46 to 60 px each), so the well reaches its foot as far in as from its side
    readonly property real _railRowH: {
        const n = Math.max(1, sidebarRepeater.count);
        const foot = sidebarPanel.y + sidebarPanel.height - (railWell.x - sidebarPanel.x); // The well's bottom
        const room = foot - 6 - 4 - (sidebarContent.y + railRows.y) - (n - 1) * 2; // Less its padding, the rows' margin and gaps
        return Math.round(Math.max(46, Math.min(60, room / n)));
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
    // The Files row opens it
    readonly property string _filesDir: game?.flatpakId ? `${Quickshell.env("HOME")}/.var/app/${game.flatpakId}` : (game?.gameDir ?? "")
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
            out.push({ icon: "science", value: tier.charAt(0).toUpperCase() + tier.slice(1), accent: root._tierColor(tier), tier: true });
        if (game.playtime > 0) {
            const h = Math.floor(game.playtime / 60);
            out.push({ icon: "timer", value: h > 0 ? `${h} h` : `${game.playtime} min`, name: Translation.tr("played") });
        }
        // Players in it right now (Steam's count; not for games it doesn't count)
        const players = GameLauncherService.playerCount(game); // Re-read as the counts come in (the binding sees playerCounts)
        if (players > 0)
            out.push({ icon: "group", value: _thousands(players), name: Translation.tr("playing"), live: true }); // Live: a pulsing dot
        // Lutris: how many have it on lutris.net, in the same spot
        const lutrisUsers = game.id.startsWith("lutris_") ? (root._currentMetadata?.userCount ?? 0) : 0;
        if (lutrisUsers > 0)
            out.push({ icon: "group", value: _thousands(lutrisUsers), name: Translation.tr("on Lutris") });
        return out;
    }
    // The rail's glass tint (at 92 % over the art), shared with the menus that slide out of it: the panel's colour
    // leaning a touch to the accent, as the frame around picks up the wallpaper's hue through its glass
    readonly property color railTint: ColorUtils.mix(Appearance.m3colors.m3background, Appearance.colors.colPrimary, 0.96)
    // ProtonDB's tiers in their own colours, as protondb.com shows them (other ratings: the accent)
    function _tierColor(tier) {
        return ({ platinum: "#c8d4e3", gold: "#f2c14e", silver: "#b8bec7", bronze: "#cd8b52", borked: Appearance.colors.colError })[tier]
            ?? Appearance.colors.colPrimary;
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
    readonly property real _factsGap: 14 // Between the facts, a dot in each gap
    function _measureFacts() {
        let c = root._extraStats.length > 0 ? 38 : -root._factsGap;
        for (let i = 0; i < chipsRepeater.count; i++) c += (chipsRepeater.itemAt(i)?.implicitWidth ?? 0) + root._factsGap;
        let e = 0;
        for (let i = 0; i < extrasRepeater.count; i++) e = Math.max(e, extrasRepeater.itemAt(i)?.implicitWidth ?? 0);
        root._chipsNeed = c;
        root._extrasNeed = e;
    }
    // The facts: a tab tucked into the art's top-right corner, curving out into its top and right edges as the rail
    // curves into its left (the same 28 px, frost, edge light and shadow), so the page's two pieces of glass are a pair.
    // ⓘ grows it down, the rows opening in a well under the chips, at their width (they stretch to the rows')
    Item {
        id: factsPiece
        readonly property real r: railShape.r // The curves out into the art
        readonly property real cr: Appearance.rounding.normal // Its corner in the art's corner, rounded as the art is
        readonly property real rb: 18 // Its own free corner
        readonly property real padX: 16
        readonly property real padY: 6
        readonly property real wellPad: 4 // The rows' well past them
        readonly property real _open: Math.min(1, extrasDrawer.progress)
        visible: infoCard.visible
        opacity: infoCard.opacity
        anchors { top: bannerFrame.top; right: bannerFrame.right }
        width: infoCard.width + padX * 2
        height: infoCard.height + padY * 2 + wellPad * _open
        z: 9
        // Its outline, from r left of it to r under it: the curves, then its own corners. Glass panels
        // off: drawn in the panel's colour. On: only the shape, the frost's mask
        Shape {
            id: factsShape
            readonly property real leftX: factsPiece.r // Its left edge, in here
            readonly property real rightX: factsPiece.r + factsPiece.width // Its right edge (the art's)
            readonly property real footY: factsPiece.height
            x: -factsPiece.r
            width: factsPiece.width + factsPiece.r; height: factsPiece.height + factsPiece.r
            visible: !Appearance.colors.glassOn
            layer.enabled: Appearance.colors.glassOn
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Appearance.colors.glassOn ? "white" : Appearance.m3colors.m3background
                strokeWidth: -1
                startX: 0; startY: 0
                PathLine { x: factsShape.rightX - factsPiece.cr; y: 0 }
                PathArc { x: factsShape.rightX; y: factsPiece.cr; radiusX: factsPiece.cr; radiusY: factsPiece.cr }
                PathLine { x: factsShape.rightX; y: factsShape.footY + factsPiece.r }
                PathArc { x: factsShape.rightX - factsPiece.r; y: factsShape.footY; radiusX: factsPiece.r; radiusY: factsPiece.r; direction: PathArc.Counterclockwise }
                PathLine { x: factsShape.leftX + factsPiece.rb; y: factsShape.footY }
                PathArc { x: factsShape.leftX; y: factsShape.footY - factsPiece.rb; radiusX: factsPiece.rb; radiusY: factsPiece.rb }
                PathLine { x: factsShape.leftX; y: factsPiece.r }
                PathArc { x: 0; y: 0; radiusX: factsPiece.r; radiusY: factsPiece.r; direction: PathArc.Counterclockwise }
            }
        }
        Canvas { // Its shadow on the art, as the rail's: down its left side, round its free corner, along its foot, and
            // into both curves (fading out toward their tips). Painted again only as it changes size (ⓘ growing it)
            id: factsShadow
            readonly property real s: factsPiece.r // How far it reaches
            x: factsShape.x - s; y: 0
            width: factsShape.width + s; height: factsShape.height + s
            z: -1
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const s = factsShadow.s, r = factsPiece.r, rb = factsPiece.rb;
                const L = s + factsShape.leftX, R = s + factsShape.rightX, H = factsShape.footY;
                const stops = [[0, 0.5], [0.25, 0.2], [0.5, 0.05], [0.75, 0]]; // As the rail's
                function fade(g, flip) { for (const [p, a] of stops) g.addColorStop(flip ? 1 - p : p, `rgba(0,0,0,${a})`); return g; }
                // Down its left side, and along its foot
                c.fillStyle = fade(c.createLinearGradient(L, 0, L - s, 0), false);
                c.fillRect(L - s, r, s, H - rb - r);
                c.fillStyle = fade(c.createLinearGradient(0, H, 0, H + s), false);
                c.fillRect(L + rb, H, R - r - L - rb, s);
                // Round its free corner
                c.fillStyle = fade(c.createRadialGradient(L + rb, H - rb, rb, L + rb, H - rb, rb + s), false);
                c.beginPath(); c.moveTo(L + rb, H - rb); c.arc(L + rb, H - rb, rb + s, 0.5 * Math.PI, Math.PI, false); c.closePath(); c.fill();
                // Into the curves: from each curve in toward its centre, gone toward the tip
                for (const k of [0, 1]) {
                    const cx = k === 0 ? L - r : R - r, cy = k === 0 ? r : H + r;
                    c.save();
                    c.fillStyle = fade(c.createRadialGradient(cx, cy, 0, cx, cy, r), true);
                    c.beginPath(); c.moveTo(cx, cy);
                    c.arc(cx, cy, r, 1.5 * Math.PI, 2 * Math.PI, false); // The quarter between the curve and its tip
                    c.closePath(); c.fill();
                    c.clip();
                    c.globalCompositeOperation = "destination-out";
                    const out = k === 0 ? c.createLinearGradient(0, cy, 0, cy - r) : c.createLinearGradient(cx, 0, cx + r, 0);
                    out.addColorStop(0.3, "rgba(0,0,0,0)");
                    out.addColorStop(0.85, "rgba(0,0,0,1)");
                    c.fillStyle = out;
                    c.fillRect(cx, cy - r, r, r);
                    c.restore();
                }
            }
        }
        Item { // Glass: the frosted art in its shape, as the rail's
            id: factsFrost
            visible: Appearance.colors.glassOn
            x: factsShape.x; width: factsShape.width; height: factsShape.height
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: factsShape
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0 // Keeps the edge antialiased
            }
            // Where it sits on the art, worked out again as it grows and the page moves
            readonly property point _origin: { void factsPiece.x; void factsPiece.height; void bannerFrame.width; return factsFrost.mapToItem(bannerFrame, 0, 0); }
            FrostArt { artX: -factsFrost._origin.x; artY: -factsFrost._origin.y }
        }
        Shape { // The rail's edge light along its free edges, from one curve's tip to the other's
            x: factsShape.x; width: factsShape.width; height: factsShape.height
            preferredRendererType: Shape.CurveRenderer
            RimPath {
                startX: 0; startY: 0.5
                PathArc { x: factsShape.leftX - 0.5; y: factsPiece.r; radiusX: factsPiece.r - 0.5; radiusY: factsPiece.r - 0.5 }
                PathLine { x: factsShape.leftX + 0.5; y: factsShape.footY - factsPiece.rb }
                PathArc { x: factsShape.leftX + factsPiece.rb; y: factsShape.footY - 0.5; radiusX: factsPiece.rb - 0.5; radiusY: factsPiece.rb - 0.5; direction: PathArc.Counterclockwise }
                PathLine { x: factsShape.rightX - factsPiece.r; y: factsShape.footY - 0.5 }
                PathArc { x: factsShape.rightX - 0.5; y: factsShape.footY + factsPiece.r; radiusX: factsPiece.r - 0.5; radiusY: factsPiece.r - 0.5 }
            }
        }
        GlassWell { // The rows' well, growing with them
            visible: extrasDrawer.visible
            opacity: Math.min(1, extrasDrawer.progress * 3)
            radius: 14
            x: factsPiece.padX + extrasDrawer.x - factsPiece.wellPad
            y: factsPiece.padY + extrasDrawer.y - factsPiece.wellPad
            width: extrasDrawer.width + factsPiece.wellPad * 2
            height: extrasDrawer.height + factsPiece.wellPad * 2
        }
    }
    Column {
        id: infoCard
        anchors { right: factsPiece.right; rightMargin: factsPiece.padX; top: factsPiece.top; topMargin: factsPiece.padY }
        spacing: 6 // Room for the rows' well
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
            spacing: root._factsGap
            Repeater {
                id: chipsRepeater
                model: root._pillFacts
                onItemAdded: Qt.callLater(root._measureFacts)
                onItemRemoved: Qt.callLater(root._measureFacts)
                Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: factChip.implicitWidth + 12
                    onImplicitWidthChanged: Qt.callLater(root._measureFacts)
                    width: implicitWidth + factsRow._stretch
                    height: 38
                    color: "transparent" // On the tab's glass, as the bar's parts
                    FactDot { visible: index > 0 }
                    Row {
                        id: factChip
                        anchors.centerIn: parent
                        spacing: 7
                        MaterialSymbol { // Filled, as the rail's; the tier in its own colour
                            visible: !modelData.live
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon; iconSize: 17; fill: 1
                            color: modelData.accent ?? Appearance.colors.colPrimary
                        }
                        Item { // Live (players right now): a dot in the accent, a soft ring pulsing out of it
                            visible: !!modelData.live
                            anchors.verticalCenter: parent.verticalCenter
                            width: 17; height: 17
                            Rectangle {
                                id: livePulse
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: width / 2
                                color: Appearance.colors.colPrimary
                                SequentialAnimation on scale { // Slow and gentle: it's the only thing moving on the page
                                    running: livePulse.visible && root.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 2.2; duration: 1600; easing.type: Easing.OutCubic }
                                    PauseAnimation { duration: 600 }
                                }
                                opacity: 1.4 - scale * 0.6 // Fades as it grows
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.value
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.numbers
                            font.weight: Font.Medium
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: modelData.tier ? modelData.accent : Appearance.colors.colOnLayer3
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
            Item { // ⓘ: the last part, after a dot. It says there's more, and while that's out it fills in with the
                // bar's accent line under it
                visible: root._extraStats.length > 0
                width: 38; height: 38
                FactDot { visible: root._pillFacts.length > 0 }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "info"
                    iconSize: 19
                    fill: root.factsOpen ? 1 : 0
                    color: root.factsOpen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                HoverLine { shown: root.factsOpen; inset: 10 }
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
                spacing: 0
                Repeater {
                    id: extrasRepeater
                    model: root._extraStats
                    onItemAdded: Qt.callLater(root._measureFacts)
                    onItemRemoved: Qt.callLater(root._measureFacts) // (Its count also decides the ⓘ)
                    Rectangle {
                        required property var modelData
                        required property int index
                        implicitWidth: 50 + extraLabel.implicitWidth + 24 + extraValue.implicitWidth + 12
                        onImplicitWidthChanged: Qt.callLater(root._measureFacts)
                        width: root._factsWidth
                        height: 42
                        color: "transparent" // In the well
                        Rectangle { // A grey squircle: a fact, not something to open (as the info drawer's rows)
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 10
                            color: Appearance.colors.colLayer4
                            MaterialSymbol { anchors.centerIn: parent; text: modelData.icon; iconSize: 17; fill: 1; color: Appearance.colors.colOnLayer3 }
                        }
                        StyledText {
                            id: extraLabel
                            x: 50; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            id: extraValue
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
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
    RippleButton { // Back to the library, top-left: "← Library" as a quiet link, the accent line under it when pointed at
        id: backButton
        x: sidebarContent.x - 2
        y: sidebarPanel.y + 10
        z: 10
        implicitWidth: backRow.implicitWidth + 12
        implicitHeight: 28
        buttonRadius: Appearance.rounding.small
        padding: 0
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.8)
        opacity: bannerFrame.opacity
        contentItem: Item {
            Row {
                id: backRow
                anchors.centerIn: parent
                spacing: 5
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "arrow_back"; iconSize: 17
                    color: backButton.hovered || backButton.activeFocus ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtextGlass
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Library")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: backButton.hovered || backButton.activeFocus ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtextGlass
                }
            }
        }
        HoverLine { shown: backButton.hovered || backButton.activeFocus; inset: 6 }
        onClicked: { root.backPressed(); focus = false; }
    }
    // The chips and the rows in one well (as the panels' lists), joined under Play, the chips its top strip, a faint line
    // under them, reaching the rail's foot
    GlassWell {
        id: railWell
        radius: root._playRadius
        topLeftRadius: Appearance.rounding.joined // Joined to Play above it
        topRightRadius: Appearance.rounding.joined
        x: sidebarContent.x
        y: sidebarContent.y + actionRowSlot.y - 6
        width: sidebarContent.width // Play's width: one edge down the rail
        height: railRows.y + railRows.height + 6 - (actionRowSlot.y - 6)
        z: 6 // Over the rail's frost, under its contents
        opacity: bannerFrame.opacity
        Rectangle {
            x: 18; width: parent.width - 36
            y: actionRowSlot.height + 6 + 5
            height: 1
            color: ColorUtils.transparentize("white", 0.93)
        }
    }
    Row { // Game actions, laid out under the Play button (slot reserved in sidebarContent)
        id: topLeftButtons
        x: Math.round(sidebarContent.x + actionRowSlot.x)
        y: Math.round(sidebarContent.y + actionRowSlot.y)
        spacing: 3; z: 11
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
            width: root._stripCell; height: actionRowSlot.height
            buttonRadius: Appearance.rounding.joined; padding: 0
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: Appearance.colors.colLayer3Active
            property var gameTags: {
                const _ = GameLauncherService.tagsRevision;
                return game ? GameLauncherService.getGameTags(game.id) : [];
            }
            property bool hasTags: gameTags.length > 0
            contentItem: StripCell {
                iconName: "sell"
                on: tagIconBtn.hasTags || tagMenuPopup.open
                hot: tagIconBtn.hovered || tagIconBtn.activeFocus
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
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: Appearance.colors.colLayer3Active
            contentItem: StripCell {
                iconName: "more_horiz"
                on: moreMenu.open
                hot: moreBtn.hovered
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
        MenuWell { anchors { fill: moreCol; margins: -4 } }
        Column {
            id: moreCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 2
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
            Item { // A gap: the destructive one apart
                visible: uninstallItem.visible || removeItem.visible
                width: parent.width; height: 6
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
                value: armed || cancels ? "" : (root._installSize.split("  ·  ")[0].replace("…", "")) // What it frees
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
        MenuWell { anchors { fill: launchCol; margins: -4 } }
        Column {
            id: launchCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 2
            Repeater {
                model: root.launchChoices
                MoreItem {
                    required property var modelData
                    // The first, unnamed one is the game itself; the others say what they are. The one Play
                    // always uses is filled (else the game itself)
                    iconName: modelData.index === 0 ? "play_arrow" : "tune"
                    filled: modelData.index === (root.launchDefault >= 0 ? root.launchDefault : 0)
                    label: modelData.label || (modelData.index === 0 ? Translation.tr("Play") : Translation.tr("Option %1").arg(modelData.index + 1))
                    value: modelData.index === root.launchDefault ? Translation.tr("Default") : ""
                    valueColor: Appearance.colors.colPrimary
                    onTriggered: {
                        if (alwaysSwitch.checked) root.setLaunchDefault(modelData.index);
                        launchMenu.open = false;
                        root.playPressed(root.game, modelData.index);
                    }
                }
            }
            Item { // As Steam's default launch option: Play then starts the one picked without asking. A row as the others
                width: parent.width; height: 46
                Rectangle {
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 10
                    color: Appearance.colors.colLayer4
                    MaterialSymbol { anchors.centerIn: parent; text: "push_pin"; iconSize: 17; color: Appearance.colors.colOnLayer3 }
                }
                StyledText {
                    anchors { left: parent.left; leftMargin: 50; right: alwaysSwitch.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: Translation.tr("Always start this way")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colOnLayer3
                }
                StyledSwitch {
                    id: alwaysSwitch
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
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
        MenuWell { anchors { fill: webCol; margins: -4 } }
        Column {
            id: webCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 2
            Repeater {
                model: root._webLinks
                MoreItem {
                    required property var modelData
                    iconName: modelData.icon
                    label: modelData.label
                    link: true
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
        MenuWell { anchors { fill: libraryCol; margins: -4 } }
        Column {
            id: libraryCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 2
            Repeater {
                model: GameLauncherService.steamLibraries
                MoreItem {
                    required property var modelData
                    required property int index
                    // Named by its folder (two on one drive said the same "Home folder"): Steam's own, else the folder,
                    // or the one holding it when it's a "SteamLibrary"/"Steam" folder
                    readonly property var parts: modelData.path.split("/").filter(p => p !== "")
                    iconName: index === 0 ? "hard_drive" : "folder"
                    label: index === 0 ? "Steam"
                         : (/^steam(library)?$/i.test(parts[parts.length - 1] ?? "") && parts.length > 1 ? parts[parts.length - 2] : parts[parts.length - 1] ?? "/")
                    value: Translation.tr("%1 GB free").arg(Math.floor(modelData.free / 1e9))
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
        Column { // What it is and its tags, adding one; suggestions apart
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
        anchors { left: parent.left; leftMargin: 30; top: backButton.bottom; topMargin: 8 } // Under the back link
        width: 270; z: 10
        spacing: 0
        RowLayout { // Play, and with a way it always starts, the menu of ways: one pill, its arrow behind a thin divider
            id: playRow
            Layout.fillWidth: true
            spacing: 0
            RippleButton {
                id: playButton
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                // Joined to the well under it (as the shell's joined pieces): its bottom corners small
                buttonRadius: root._playRadius
                buttonRadiusBottomLeft: Appearance.rounding.joined
                buttonRadiusTopRight: chooserButton.visible ? 0 : root._playRadius
                buttonRadiusBottomRight: chooserButton.visible ? 0 : Appearance.rounding.joined
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
                        topLeftRadius: root._playRadius
                        bottomLeftRadius: Appearance.rounding.joined
                        color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.8)
                        Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    }
                    Item { // Its icon, straight on the pill
                        id: playIcon
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        width: 40; height: 40
                        PlayingDot { // Playing: where the icon goes (as the grid's badge)
                            anchors.centerIn: parent
                            visible: playButton.playing && root.visible
                            size: 9
                            color: Appearance.colors.colOnPrimary
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !playButton.playing
                            text: playButton._look.icon
                            iconSize: 24
                            fill: 1
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    StyledText { // What it does (your time in it is in the facts)
                        anchors { left: playIcon.right; leftMargin: 6; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: {
                            const pct = root.downloadProgress >= 0 ? ` ${Math.floor(root.downloadProgress * 100)}%` : "";
                            if (playButton.playing) return playButton._look.text;
                            if (root._downloading || root._paused || root._queued) return playButton._look.text + (pct ? " " + pct : "");
                            if (root._modsOnly) return playButton._look.text + "  ·  " + Translation.tr("mods") + pct;
                            return playButton._look.text;
                        }
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.normal + 1
                        font.weight: Font.DemiBold
                    }
                }
            }
            RippleButton { // The other ways to start it, once Play starts one without asking (launchDefault)
                id: chooserButton
                visible: root.installState === "installed" && !playButton.playing && root.launchDefault >= 0
                Layout.preferredWidth: 44
                Layout.preferredHeight: playButton.Layout.preferredHeight
                buttonRadius: root._playRadius
                buttonRadiusTopLeft: 0
                buttonRadiusBottomLeft: 0
                buttonRadiusBottomRight: Appearance.rounding.joined
                padding: 0
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                buttonColor: (hovered || launchMenu.open) ? colBackgroundHover : colBackground
                onClicked: launchMenu.open = !launchMenu.open
                contentItem: Item {
                    Rectangle { // The divider from Play, in the same pill
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 1; height: 30
                        color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.8)
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "expand_more"
                        iconSize: 22
                        color: Appearance.colors.colOnPrimary
                        rotation: launchMenu.open ? 180 : 0 // Flips while the menu's out
                        Behavior on rotation { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    }
                }
                StyledToolTip { text: Translation.tr("Other ways to start it") }
            }
        }
        Item { // Where the action buttons go, under Play (topLeftButtons is positioned on it): joined icon squares
            id: actionRowSlot
            Layout.fillWidth: true
            Layout.leftMargin: 8; Layout.rightMargin: 8
            Layout.topMargin: 9; Layout.bottomMargin: 8 // The well 3 px under Play (joined), then its line under the chips
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
        ColumnLayout { // The menu: rows, each saying what's inside. Reaching a little wider than Play, so the rows' icons
            id: railRows
            // line up with Play's left edge and their chevrons with its right (the rows keep their own padding for when
            // one's panel is open and it's a tinted card)
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.bottomMargin: 4
            spacing: 2
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
                    Layout.preferredHeight: root._railRowH // One line each, what's inside on the right
                    // On the glass; pointed at, the bar's accent line; its panel open, a tinted card
                    buttonRadius: Appearance.rounding.normal
                    padding: 0
                    activeFocusOnTab: true
                    colBackground: "transparent"
                    colBackgroundHover: "transparent"
                    colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.88)
                    // Pointed at: a soft card fades in behind it. Its panel open: tinted, the icon and label in the accent
                    readonly property bool panelOpen: root.openPanel !== "" && root.openPanel === modelData.type
                        || modelData.type === "web" && webMenu.open
                    readonly property bool lit: hovered || activeFocus
                    readonly property bool isLink: !root.panelTypes.includes(modelData.type) && modelData.type !== "web"
                    buttonColor: panelOpen ? Appearance.colors.colLayer3Accent
                        : lit ? ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.94) : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
                    // News: how many posts are new since its panel was last opened
                    readonly property bool newsLoaded: modelData.type === "news" && GameLauncherService.newsFor === (game?.id ?? "")
                    readonly property int unread: newsLoaded ? GameLauncherService.unreadNews : 0
                    // Achievements: how many of how many, or that the game has none (read, not private or offline:
                    // the panel would say the same)
                    readonly property bool achievementsRead: modelData.type === "achievements" && GameLauncherService.achievementsFor === (game?.id ?? "")
                        && !GameLauncherService.achievementsLoading && GameLauncherService.achievements !== null
                    readonly property var achieved: achievementsRead && (GameLauncherService.achievements.total ?? 0) > 0 ? GameLauncherService.achievements : null
                    readonly property bool noAchievements: achievementsRead && achieved === null
                        && !["private", "offline"].includes(GameLauncherService.achievements.error ?? "")
                    readonly property string tier: modelData.label === "ProtonDB" ? (game?.protondbTier ?? "") : ""
                    // What's inside, on the right: new posts, how many captures, how far, the rating (in its colour), a
                    // Lutris game's size or runner. The details (the headline, the keys for a capture) are in the panels
                    readonly property string value: unread > 0 ? Translation.tr("%1 new").arg(unread > 9 ? "9+" : unread)
                        : modelData.type === "screenshots" ? (root._peekShots + root._peekClips === 0 ? Translation.tr("None yet") : root._capturesLine)
                        : achieved ? `${achieved.unlocked} / ${achieved.total}`
                        : noAchievements ? Translation.tr("None")
                        : tier !== "" ? tier.charAt(0).toUpperCase() + tier.slice(1)
                        : modelData.type === "files" ? (root._installSize === "…" ? "" : root._installSize)
                        : modelData.type === "lutris_app" ? root._runnerLabel
                        : ""
                    readonly property color valueColor: unread > 0 ? Appearance.colors.colPrimary
                        : tier !== "" ? root._tierColor(tier) : Appearance.colors.colSubtextGlass
                    contentItem: Item {
                        implicitHeight: actionBtn.Layout.preferredHeight
                        Rectangle { // The icon in a square: accent for a panel here, grey for the browser. Its panel open (the
                            // row tinted as the square): solid accent, so it still stands out; hovered, a step up
                            id: actionIcon
                            anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                            width: 30; height: 30; radius: 10
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
                        StyledText {
                            anchors { left: actionIcon.right; leftMargin: 12; right: detail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: actionBtn.modelData.label
                            color: actionBtn.panelOpen ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: Font.Medium
                        }
                        Row { // What's inside, and a link out (the browser) says so; a panel's row needs no arrow
                            id: detail
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Rectangle { // New posts: a dot before the count
                                anchors.verticalCenter: parent.verticalCenter
                                visible: actionBtn.unread > 0
                                width: 6; height: 6; radius: 3
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: actionBtn.value !== ""
                                text: actionBtn.value
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({}) // Not Roboto Flex's tuning
                                color: actionBtn.valueColor
                            }
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: actionBtn.isLink
                                text: "open_in_new"
                                iconSize: 15
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
    // and clips (a last "clips" line) the game has, said as the panel's two pages: "3 screenshots  ·  6 clips"
    property int _peekShots: 0
    property int _peekClips: 0
    readonly property string _capturesLine: [
        _peekShots === 1 ? Translation.tr("1 screenshot") : _peekShots > 1 ? Translation.tr("%1 screenshots").arg(_peekShots) : "",
        _peekClips === 1 ? Translation.tr("1 clip") : _peekClips > 1 ? Translation.tr("%1 clips").arg(_peekClips) : ""
    ].filter(t => t !== "").join("  ·  ")
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
                root._peekShots = shots.length;
                root._peekClips = parseInt(clipsLine?.split("\t")[1] ?? "0") || 0;
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
        paneH: Math.min(_metaCol.implicitHeight + 24, sidebarPanel.height - 2 * root._railClear) // Clear of the rail's curves
        anchorCenterY: sidebarPanel.y + sidebarPanel.height / 2
        HoverHandler { id: infoPaneHover; onHoveredChanged: root._syncInfoHover() }
        MenuWell { anchors { fill: infoFlick; margins: -4 } }
        Flickable {
            id: infoFlick
            anchors { fill: parent; margins: 12 }
            contentHeight: _metaCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            // Its edges fade while there's more to scroll to (only then: no layer when it fits)
            layer.enabled: !(atYBeginning && atYEnd)
            layer.effect: ScrollFadeMask { topActive: !infoFlick.atYBeginning; bottomActive: !infoFlick.atYEnd }
            // In the well: the score, then a row each, the description last
            Column {
                id: _metaCol
                width: parent.width
                spacing: 2
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
                        lineHeight: 1.25 // All of it: the drawer scrolls, its edge fading while there's more
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
        // Clear of the rail's curves top and bottom: their 28 px, the menu's own 20 px join, and 14 px of straight edge
        // between them, so the art between reads as a notch, not pinched into a hook. Less only when the menu's too tall
        readonly property real _clear: Math.max(16, Math.min(root._railClear, (height - paneH) / 2))
        readonly property real menuTop: Math.max(_clear, Math.min(anchorCenterY - sidebarPanel.y - paneH / 2, height - paneH - _clear))
        // The joins where it leaves the rail: they shrink as the menu slides in, as the blob's do (full size once it's 40 px out)
        readonly property real joinR: Math.max(0, Math.min(20, _shown / 2))
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
                id: blobLoader
                anchors.fill: parent
                active: sd.visible
                source: Qt.resolvedUrl("../overview/BlobDrawerBackground.qml")
                onLoaded: {
                    item.barBottom = 0;
                    item.barHeight = 40;
                    item.barRadius = 0;
                    // Glass: not drawn at all, the frost (below) is the menu's whole shape: its outline only approximates the
                    // blob's gooey curve, and the blob peeked out along it as a thin dark edge. It still drives the wobble
                    item.fillColor = Appearance.m3colors.m3background;
                    item.fillOpacity = Qt.binding(() => Appearance.colors.glassOn ? 0 : 1.0);
                    // Rotated: the stage's x runs up the screen
                    item.drawerX = Qt.binding(() => stage.along - sd.menuTop - sd.paneH);
                    item.drawerY = Qt.binding(() => sd._y);
                    item.drawerWidth = Qt.binding(() => sd.paneH);
                    item.drawerHeight = Qt.binding(() => sd._len);
                    item.drawerRadius = Qt.binding(() => Math.min(Appearance.rounding.large, sd._shown / 2));
                }
            }
            Item { // The frost wobbles with the blob: its squash and stretch, in the blob's own (rotated) frame
                anchors.fill: parent
                transform: Matrix4x4 { matrix: blobLoader.item?.deformMatrix ?? Qt.matrix4x4() }
                Item { // Turned back upright, laid over the menu as the stage is
                    id: upright
                    x: (stage.width - sd.width) / 2; y: (stage.height - sd.height) / 2
                    width: sd.width; height: sd.height
                    rotation: 90
                    Item { // Glass: the rail's frosted art under its tint, as the rail, cut to the menu's outline (frostShape)
                        id: frost
                        visible: Appearance.colors.glassOn
                        x: -frostShape.bleed; width: sd.width + frostShape.bleed; height: sd.height // Reaching under the rail, see bleed
                        opacity: bannerFrame.opacity
                        layer.enabled: visible
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: frostShape
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0 // Keeps the edge antialiased
                        }
                        // Where it sits on the art, worked out again as the panel moves (mapToItem alone isn't re-run)
                        readonly property point _origin: { void sd.x; void sd.y; void bannerFrame.width; return frost.mapToItem(bannerFrame, 0, 0); }
                        FrostArt { artX: -frost._origin.x; artY: -frost._origin.y }
                    }
                    Shape { // The menu's outline, as the blob draws it: square along the rail, curving in where it leaves it
                        // (the blob's smoothing, 20 px), rounded at its far end
                        id: frostShape
                        visible: false
                        layer.enabled: true
                        x: -frostShape.bleed; width: sd.width + frostShape.bleed; height: sd.height // Reaching under the rail, see bleed
                        preferredRendererType: Shape.CurveRenderer
                        readonly property real r: sd.joinR
                        // Past the rail's edge (clipped there): the cut's soft edge lands under the rail, not as a line on the join,
                        // and the wobble's stretch (about its middle) can't pull it off the rail mid-slide
                        readonly property real bleed: 40
                        readonly property real rr: Math.min(Appearance.rounding.large, sd._shown / 2)
                        readonly property real yTop: sd.menuTop
                        readonly property real yBottom: sd.menuTop + sd.paneH
                        readonly property real len: Math.max(0, sd._shown)
                        ShapePath {
                            fillColor: "white"
                            strokeWidth: -1
                            startX: 0; startY: frostShape.yTop - frostShape.r
                            PathLine { x: frostShape.bleed; y: frostShape.yTop - frostShape.r }
                            PathArc { x: frostShape.bleed + frostShape.r; y: frostShape.yTop; radiusX: frostShape.r; radiusY: frostShape.r; direction: PathArc.Counterclockwise }
                            PathLine { x: frostShape.bleed + frostShape.len - frostShape.rr; y: frostShape.yTop }
                            PathArc { x: frostShape.bleed + frostShape.len; y: frostShape.yTop + frostShape.rr; radiusX: frostShape.rr; radiusY: frostShape.rr }
                            PathLine { x: frostShape.bleed + frostShape.len; y: frostShape.yBottom - frostShape.rr }
                            PathArc { x: frostShape.bleed + frostShape.len - frostShape.rr; y: frostShape.yBottom; radiusX: frostShape.rr; radiusY: frostShape.rr }
                            PathLine { x: frostShape.bleed + frostShape.r; y: frostShape.yBottom }
                            PathArc { x: frostShape.bleed; y: frostShape.yBottom + frostShape.r; radiusX: frostShape.r; radiusY: frostShape.r; direction: PathArc.Counterclockwise }
                            PathLine { x: 0; y: frostShape.yBottom + frostShape.r }
                            PathLine { x: 0; y: frostShape.yTop - frostShape.r }
                        }
                    }
                }
            }
        }
        // The rail's edge light, carried out round the menu from one join to the other (railRim parts for it). Drawn here,
        // outside the wobble, from the outline's points each put through it, so it follows the menu's squash and stretch
        // exactly, but its two ends stay on the rail's edge, where the rail's light meets them (inside the wobble they slid off)
        readonly property var _rim: {
            if (_shown < 1) return root._rimNone; // Tucked away (most of the time): nothing drawn, nothing worked out
            void (blobLoader.item?.deformMatrix); void menuTop; void paneH; void width; void height;
            const k = 0.5523; // A quarter circle as a cubic
            const x0 = 0.5, r = Math.max(0, joinR - 0.5), rr = Math.max(0, Math.min(Appearance.rounding.large, _shown / 2) - 0.5);
            const t = menuTop + 0.5, bt = menuTop + paneH - 0.5, e = Math.max(0.5, _shown - 0.5); // Never past the rail's edge (tucking away, it lies on it)
            const y0 = menuTop - joinR, y1 = menuTop + paneH + joinR;
            const raw = [
                [x0, y0],                                           // 0 start, on the rail
                [x0, y0 + k * r], [x0 + r - k * r, t], [x0 + r, t], // 1-3 the top join
                [e - rr, t],                                        // 4
                [e - rr + k * rr, t], [e, t + rr - k * rr], [e, t + rr], // 5-7 the far top corner
                [e, bt - rr],                                       // 8
                [e, bt - rr + k * rr], [e - rr + k * rr, bt], [e - rr, bt], // 9-11 the far bottom corner
                [x0 + r, bt],                                       // 12
                [x0 + r - k * r, bt], [x0, y1 - k * r], [x0, y1]    // 13-15 the bottom join, back on the rail
            ];
            const pts = raw.map(q => upright.mapToItem(sd, q[0], q[1]));
            for (const n of [0, 1, 14, 15]) pts[n] = Qt.point(0.5, pts[n].y); // The ends pinned to the edge, leaving it square
            return pts;
        }
        Shape {
            anchors.fill: parent
            visible: sd._shown >= 1 // Less, and the rail's own light runs straight past (railRim)
            opacity: bannerFrame.opacity
            preferredRendererType: Shape.CurveRenderer
            RimPath {
                startX: sd._rim[0].x; startY: sd._rim[0].y
                PathCubic { control1X: sd._rim[1].x; control1Y: sd._rim[1].y; control2X: sd._rim[2].x; control2Y: sd._rim[2].y; x: sd._rim[3].x; y: sd._rim[3].y }
                PathLine { x: sd._rim[4].x; y: sd._rim[4].y }
                PathCubic { control1X: sd._rim[5].x; control1Y: sd._rim[5].y; control2X: sd._rim[6].x; control2Y: sd._rim[6].y; x: sd._rim[7].x; y: sd._rim[7].y }
                PathLine { x: sd._rim[8].x; y: sd._rim[8].y }
                PathCubic { control1X: sd._rim[9].x; control1Y: sd._rim[9].y; control2X: sd._rim[10].x; control2Y: sd._rim[10].y; x: sd._rim[11].x; y: sd._rim[11].y }
                PathLine { x: sd._rim[12].x; y: sd._rim[12].y }
                PathCubic { control1X: sd._rim[13].x; control1Y: sd._rim[13].y; control2X: sd._rim[14].x; control2Y: sd._rim[14].y; x: sd._rim[15].x; y: sd._rim[15].y }
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
        colBackground: "transparent" // On the glass: on, an accent squircle round the icon (StripCell)
        colBackgroundHover: "transparent"
        colRipple: Appearance.colors.colLayer3Active
        contentItem: StripCell {
            id: tiCell
            iconName: ti.iconName
            on: ti.on
            hot: ti.hovered || ti.activeFocus
        }
        onClicked: { if (!game) return; ti.flipped(); tiCell.bounce(); focus = false; }
        StyledToolTip { text: ti.tip }
    }
    // A cell of the action row under Play, on the glass: its icon, on an accent squircle (filled) when on, the bar's
    // accent line under it while pointed at, and a small count (Tags)
    component StripCell: Item {
        id: cell
        property string iconName
        property bool on: false
        property bool hot: false
        property int count: 0
        function bounce() { cellBounce.start(); }
        implicitHeight: 38
        Rectangle {
            anchors.centerIn: parent
            width: 34; height: 34
            radius: Appearance.rounding.segment
            color: Appearance.colors.colLayer3Accent
            opacity: cell.on ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        HoverLine { shown: cell.hot && !cell.on; inset: Math.max(8, (cell.width - 22) / 2) }
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
    // The game page's glass (the rail and the menus out of it): the art decoded small and scaled back up, so it comes
    // out frosted (no blur shader: a blur layer on the launcher hung the GPU before), under the rail's tint at 80 %.
    // artX/artY: where the art's frame sits from here, so the frost lines up with the picture
    component FrostArt: Item {
        property real artX: 0
        property real artY: 0
        anchors.fill: parent
        Image {
            x: parent.artX; y: parent.artY
            width: bannerFrame.width
            height: bannerFrame.height
            source: root._bannerSource
            sourceSize.width: 110 // Fixed: small (frosted, but the art's shapes still show), and never decoded again as the page settles
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
        }
        Rectangle { anchors.fill: parent; color: ColorUtils.transparentize(root.railTint, 0.2) } // Glass you can see the art through, not a slab
    }
    // The small dot before a part (the facts, the action strip), centred in the gap before it, as the bar's
    component FactDot: Rectangle {
        anchors { right: parent.left; rightMargin: parent.parent?.spacing !== undefined ? (parent.parent.spacing - 3) / 2 : 0; verticalCenter: parent.verticalCenter }
        width: 3; height: 3; radius: 1.5
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.6)
    }
    // A row of a side menu (⋯, install where, start how): a piece joined to the rows beside it, as the info drawer's,
    // the icon in an accent square (red for a destructive one; solid while it's armed)
    component MoreItem: RippleButton {
        id: mi
        property string iconName
        property string label
        property string detail: "" // A second, smaller line, only for something passing (Uninstall's confirm note)
        property string value: "" // What it is, on the right (Default, a size, the space free), as the rail's rows
        property color valueColor: danger ? Appearance.colors.colError : Appearance.colors.colSubtextGlass
        property bool filled: false // Solid square behind the icon: armed/active
        property bool link: false // Opens the browser: a grey squircle and ↗, as the rail's link rows
        property bool closesMenu: true
        property bool danger: false
        signal triggered()
        readonly property color accent: danger ? Appearance.colors.colError : Appearance.colors.colPrimary
        width: parent ? parent.width : 200
        height: visible ? 46 : 0 // Never changes: a taller item would resize and move the open menu
        readonly property bool settingsRow: true
        // In the menu's well, rounded all round, a soft card fading in when pointed at (red-tinted for a
        // destructive one), as the rail's rows
        buttonRadius: 14
        padding: 0
        colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
        colBackgroundHover: ColorUtils.transparentize(danger ? Appearance.colors.colError : Appearance.colors.colOnLayer3, danger ? 0.9 : 0.94)
        colRipple: ColorUtils.transparentize(accent, 0.8)
        onClicked: { const close = closesMenu; if (game) mi.triggered(); if (close) moreMenu.open = false; }
        contentItem: Item {
            Rectangle {
                id: miIcon
                x: 8; anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 10
                color: mi.filled ? mi.accent : mi.danger ? Appearance.colors.colLayer3Error : mi.link ? Appearance.colors.colLayer4 : Appearance.colors.colLayer3Accent
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                MaterialSymbol {
                    anchors.centerIn: parent; text: mi.iconName; iconSize: 17
                    color: mi.filled ? (mi.danger ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary)
                        : mi.link ? Appearance.colors.colOnLayer3 : mi.accent
                }
            }
            Column {
                anchors { left: miIcon.right; leftMargin: 12; right: miEnd.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                StyledText { width: parent.width; elide: Text.ElideRight; text: mi.label; font.pixelSize: Appearance.font.pixelSize.smallie; color: mi.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer3 }
                StyledText { width: parent.width; elide: Text.ElideRight; visible: mi.detail !== ""; text: mi.detail; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
            }
            Row {
                id: miEnd
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 6
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: mi.value !== ""
                    text: mi.value
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning
                    color: mi.valueColor
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: mi.link
                    text: "open_in_new"; iconSize: 15
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
    // The well a side menu's rows sit in, as the rail's (and the panels' lists)
    component MenuWell: GlassWell {
        radius: 18
        opacity: bannerFrame.opacity
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
        color: "transparent" // Glass: straight on the menu's well
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
        Rectangle { // A grey squircle: a fact, not something to open (as the menus' link rows)
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 10
            color: Appearance.colors.colLayer4
            MaterialSymbol { anchors.centerIn: parent; text: infoRow.iconName; iconSize: 17; color: Appearance.colors.colOnLayer3 }
        }
        StyledText {
            id: infoLabel
            x: 50; anchors.verticalCenter: parent.verticalCenter
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
