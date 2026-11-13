import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Library statistics: a banner of the art of what you've played most lately (else of all time) with the hours you've
// played, the games played and the average as chips, and the installed size, the last two weeks and the library's
// ProtonDB as joined chips on the right. Then four cards, each led by a headline on art with the card's title as chips
// over it and its list joined under: Recently played (the most played lately, then the latest as covers), Most played
// (the top game's share of all your time, then the next ranked), Storage (the drive sliced by game, then what's
// downloading, every install, what uninstalled games left) and Captures (the library's newest screenshot or clip large,
// the next four under it, opening their game's Captures). Every game opens its details.
Item {
    id: root
    signal backPressed()
    signal gameSelected(var game)
    signal capturesSelected(var game, string page) // A capture's game, on its Captures (page: shots or clips)
    property bool animationReady: false
    // Built ahead by the launcher (hidden): the scripts read again each time it's shown, so it's never stale, and
    // a result the same as last time changes nothing
    property bool shown: true
    // How much taller the page is still getting as the drawer eases open: covers are laid out for where it ends,
    // so they don't resize (and change how many fit) every frame on the way
    property real growBy: 0
    onShownChanged: if (shown) refresh()
    function refresh() { _readDiskSizes(); leftoversProc.running = true; capturesProc.running = true; librariesProc.running = true; }
    Component.onCompleted: { _animTimer.start(); refresh(); _recompute(); _syncDownloads(); }
    Timer { id: _animTimer; interval: 50; onTriggered: root.animationReady = true }

    // ─── Helpers ──────────────────────────────────────────────
    function _thousands(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
    function _formatTime(minutes) {
        minutes = Math.round(minutes);
        if (minutes < 60) return minutes + "m";
        const h = Math.floor(minutes / 60);
        if (h >= 100) return _thousands(h) + "h";
        const m = minutes % 60;
        return m > 0 ? h + "h " + m + "m" : h + "h";
    }
    function _formatBytes(b) {
        const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return (i >= 3 ? b.toFixed(1) : Math.round(b)) + " " + u[i];
    }
    function _ago(ms) {
        const d = Math.floor((Date.now() - ms) / 86400000);
        if (d <= 0) return Translation.tr("Today");
        if (d === 1) return Translation.tr("Yesterday");
        if (d < 7) return Translation.tr("%1 days ago").arg(d);
        if (d < 14) return Translation.tr("1 week ago");
        if (d < 60) return Translation.tr("%1 weeks ago").arg(Math.floor(d / 7));
        if (d < 365) return Math.floor(d / 30) === 1 ? Translation.tr("1 month ago") : Translation.tr("%1 months ago").arg(Math.floor(d / 30));
        return Math.floor(d / 365) === 1 ? Translation.tr("1 year ago") : Translation.tr("%1 years ago").arg(Math.floor(d / 365));
    }
    readonly property var _tierColors: ({
        "platinum": "#b4c7dc", "gold": "#cfb53b",
        "silver": "#a6a6a6", "bronze": "#cd7f32", "borked": "#ff4444"
    })

    // ─── Data ─────────────────────────────────────────────────
    // Install sizes: Steam's straight from its manifests (no scanning), other installed games' from their folders
    // (a Flatpak game's app and data); re-read when the library changes
    property var _diskSizes: ({})
    property string _diskText: ""
    Process {
        id: diskProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root._diskText) return;
                root._diskText = text;
                try { root._diskSizes = JSON.parse(text); } catch (e) {}
                _statsDebounce.restart();
            }
        }
    }
    function _readDiskSizes() {
        const others = GameLauncherService.games
            .filter(g => !g.id.startsWith("steam_") && (g.stateFlags || 0) !== 0)
            .map(g => ({ id: g.id, gameDir: g.gameDir || "", flatpakId: g.flatpakId || "" }));
        diskProc.running = false;
        diskProc.command = ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/steam_disk_usage.py"), JSON.stringify(others)];
        diskProc.running = true;
    }
    // Leftovers of uninstalled games: the Proton prefixes uninstalling keeps (saves without Steam Cloud live
    // there) and shader caches, with sizes. Listed and deleted by launch_options.py, re-read after a delete
    readonly property string _helper: Quickshell.shellPath("scripts/game-launcher/launch_options.py")
    property var _leftovers: []
    property string _leftoversText: ""
    readonly property real _leftoverTotal: _leftovers.reduce((t, e) => t + e.size, 0)
    property bool _showLeftovers: false
    Process {
        id: leftoversProc
        command: ["python3", "-I", root._helper, "leftovers"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root._leftoversText) return;
                root._leftoversText = text;
                try { root._leftovers = JSON.parse(text); } catch (e) {}
                if (root._leftovers.length === 0) root._showLeftovers = false; // All deleted: back to storage
            }
        }
    }
    Process {
        id: removeLeftoversProc
        stdout: StdioCollector { id: removeOut }
        onExited: {
            let r = null; try { r = JSON.parse(removeOut.text); } catch (e) {}
            if (r?.freed > 0)
                Quickshell.execDetached(["notify-send", "-a", "Game Launcher", "Game Launcher", Translation.tr("Freed %1").arg(root._formatBytes(r.freed))]);
            if (!r?.ok) console.warn("[GameLauncher] remove-leftovers", removeOut.text.trim());
            leftoversProc.running = true;
        }
    }
    function _removeLeftovers(appids) {
        if (removeLeftoversProc.running || appids.length === 0) return;
        removeLeftoversProc.command = ["python3", "-I", root._helper, "remove-leftovers", ...appids];
        removeLeftoversProc.running = true;
    }
    // The library's own entry for a leftover (cover, details page), or just its name
    function _leftoverGame(e) {
        return GameLauncherService.gamesById["steam_" + e.appid] ?? { name: e.name, _placeholder: true };
    }

    // The library's screenshots and clips (scripts/game-launcher/library_captures.py): counts, room, the newest
    property var _captures: null
    property string _capturesText: ""
    Process {
        id: capturesProc
        command: ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/library_captures.py"),
                  GameClips.clipsDir, `${GameLauncherService.cacheDir}/clip-thumbs`]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root._capturesText) return;
                root._capturesText = text;
                try { root._captures = JSON.parse(text); } catch (e) {}
            }
        }
    }
    // A capture's game, by its folder (the game's name made safe): the library by folder name, made once
    readonly property var _gamesByFolder: {
        const m = {};
        for (const g of GameLauncherService.games) {
            const k = GameClips.safeName(g.name);
            if (!(k in m)) m[k] = g;
        }
        return m;
    }
    function _captureGame(c) { return _gamesByFolder[c.game] ?? null; }
    // Free room on the drives Steam's libraries are on (launch_options.py libraries), each drive once
    property real _freeBytes: -1
    Process {
        id: librariesProc
        command: ["python3", "-I", root._helper, "libraries"]
        stdout: StdioCollector {
            onStreamFinished: {
                let libs = []; try { libs = JSON.parse(text); } catch (e) {}
                const drives = {};
                for (const l of libs) drives[`${l.free}:${l.size}`] = l.free; // Same numbers: the same drive
                const free = Object.values(drives);
                root._freeBytes = free.length > 0 ? free.reduce((t, f) => t + f, 0) : -1;
            }
        }
    }
    // What Steam is downloading for the library's games (the Downloads panel's feed), for Storage's top: which
    // ones, replaced only when that changes (the feed sends new numbers every second while one downloads, and
    // a new list would rebuild every row and reload its cover). Each row reads its live numbers (_downloadItem)
    property var _downloads: [] // [{ appid, game }]
    Connections {
        target: GameLauncherService
        function onActiveDownloadsChanged() { root._syncDownloads(); }
    }
    function _syncDownloads() {
        const next = GameLauncherService.activeDownloads.map(d => ({ appid: d.appid, game: GameLauncherService.gamesById["steam_" + d.appid] ?? null }))
            .filter(d => d.game);
        if (next.map(d => d.appid).join() !== _downloads.map(d => d.appid).join()) _downloads = next;
    }
    function _downloadItem(appid) { return GameLauncherService.activeDownloads.find(d => d.appid === appid) ?? null; }
    function _downloadText(d) {
        const pct = d.progress >= 0 ? ` · ${Math.floor(d.progress * 100)}%` : "";
        const what = d.state === "downloading" ? (d.installing ? Translation.tr("Installing") : Translation.tr("Updating"))
            : ["queued", "scheduled"].includes(d.state) ? Translation.tr("Queued") : Translation.tr("Paused");
        return what + pct;
    }

    // The cards' models: changed only when their list is a new one (see _recompute's keep)
    property var _recentRows: []
    property var _mostRows: []
    property var _storageRows: [] // Downloads ({ appid, game }, with size when installed) first, then the installs ({ game, size })
    // Recently played's headline: the most played in the last two weeks, else the latest. Its covers are the rest
    readonly property var _recentHero: _stats?.lately ?? _stats?.recent?.[0] ?? null
    on_StatsChanged: {
        // Lists without their headline's game: new arrays only when their rows change (see _recompute's keep)
        const same = (a, b, key) => a.length === b.length && a.every((r, i) => key(r) === key(b[i]));
        const heroId = _recentHero?.game.id;
        const recent = (_stats?.recent ?? []).filter(r => r.game.id !== heroId);
        if (!same(recent, _recentRows, r => `${r.game.id}:${r.last}:${r.recentMin}:${r.sessionMin}`)) _recentRows = recent;
        const most = (_stats?.mostPlayed ?? []).slice(1); // The first is the headline
        if (!same(most, _mostRows, r => `${r.game.id}:${r.minutes}`)) _mostRows = most;
        _syncStorage();
    }
    // The drive bar's slices: the four biggest installs, then the rest as one. Each row's bar takes its slice's colour
    readonly property var _driveSlices: {
        const b = _stats?.biggest ?? [];
        const s = b.slice(0, 4).map((r, i) => ({ slice: i, size: r.size }));
        const rest = b.slice(4).reduce((t, r) => t + r.size, 0);
        return rest > 0 ? s.concat([{ slice: 4, size: rest }]) : s;
    }
    readonly property var _sliceOf: { // Game id: its slice
        const m = {};
        (_stats?.biggest ?? []).forEach((r, i) => m[r.game.id] = Math.min(i, 4));
        return m;
    }
    function _sliceColor(i) {
        const c = Appearance.colors, p = c.colPrimary, t = Appearance.m3colors.m3tertiary;
        return [p, ColorUtils.mix(p, t, 0.5), t, ColorUtils.mix(p, Appearance.m3colors.m3secondaryContainer, 0.45), c.colSubtext][Math.min(i, 4)];
    }
    on_DownloadsChanged: _syncStorage()
    property var _storageFor: [null, null] // The two lists _storageRows was made from
    function _syncStorage() {
        const biggest = _stats?.biggest ?? [];
        if (_storageFor[0] === _downloads && _storageFor[1] === biggest) return;
        _storageFor = [_downloads, biggest];
        // A game both installed and updating is one row: the download's, with its size on disk
        const sizes = new Map(biggest.map(b => [b.game.id, b.size]));
        const merged = _downloads.map(d => sizes.has(d.game.id) ? Object.assign({ size: sizes.get(d.game.id) }, d) : d);
        const downloading = new Set(_downloads.map(d => d.game.id));
        _storageRows = merged.concat(biggest.filter(b => !downloading.has(b.game.id)));
    }

    // Everything below comes from one pass over the library, redone (debounced) when anything it reads changes
    property var _stats: null
    Timer { id: _statsDebounce; interval: 80; onTriggered: root._recompute() }
    Connections {
        target: GameLauncherService
        function onGamesChanged() { root._readDiskSizes(); _statsDebounce.restart() } // Installs change sizes too
        function onSessionDataChanged() { _statsDebounce.restart() }
    }
    readonly property real _twoWeeks: 14 * 24 * 3600 * 1000
    function _top(list, key, n) { return list.slice().sort((a, b) => b[key] - a[key]).slice(0, n); }
    function _recompute() {
        const games = GameLauncherService.games;
        const sessions = GameLauncherService.sessionData;
        const now = Date.now();
        let totalMin = 0, installed = 0, played = 0, diskTotal = 0, backlog = 0, tierGames = 0, recentTotalMin = 0, recentGames = 0;
        const rows = [], tiers = {};
        for (let i = 0; i < games.length; i++) {
            const g = games[i];
            // Steam's playtime already includes sessions started from here; other launchers only have ours
            const sd = sessions[g.id];
            const minutes = g.id.startsWith("steam_") ? (g.playtime || 0) : Math.round((sd?.totalTime || 0) / 60000);
            const last = Math.max(g.lastPlayed > 0 && g.lastPlayed <= now ? g.lastPlayed : 0, sd?.lastPlayed || 0);
            const isInstalled = (g.stateFlags || 0) !== 0;
            const size = _diskSizes[g.id] || 0;
            // The launcher's own record of the latest session, when it saw one (games started from here)
            const lastSession = (sd?.sessions ?? []).reduce((a, b) => (!a || b.start > a.start) ? b : a, null);
            // Time played in the last two weeks: Steam's own count (it includes sessions started from here),
            // else the launcher's sessions. Steam's number is from the last scan, so it counts only while the
            // game was played within the two weeks
            const ownRecentMin = Math.round((sd?.sessions ?? []).filter(s => s.start >= now - root._twoWeeks)
                .reduce((t, s) => t + (s.duration || 0), 0) / 60000);
            const steamRecentMin = last >= now - root._twoWeeks ? (g.playtime2Weeks || 0) : 0;
            const recentMin = Math.max(steamRecentMin, ownRecentMin);
            totalMin += minutes;
            if (recentMin > 0) { recentTotalMin += recentMin; recentGames++; }
            if (isInstalled) { installed++; diskTotal += size; if (minutes === 0) backlog++; }
            if (minutes > 0) played++;
            // ProtonDB for the whole library: rated tiers only ("pending" and unrated games aren't counted)
            if (root._tierColors[g.protondbTier]) { tiers[g.protondbTier] = (tiers[g.protondbTier] || 0) + 1; tierGames++; }
            rows.push({ game: g, minutes: minutes, recentMin: recentMin, last: last, size: size,
                        sessionMin: lastSession ? Math.round(lastSession.duration / 60000) : -1 });
        }
        // The lists: the same arrays as last time while their rows are the same (a new one rebuilds every row and
        // reloads its cover, and this runs a few times as the page opens: sizes, sessions, the library)
        const prev = root._stats;
        const keep = (old, next, key) => old && old.length === next.length && old.every((r, i) => key(r) === key(next[i])) ? old : next;
        const mostPlayed = keep(prev?.mostPlayed, _top(rows.filter(r => r.minutes > 0), "minutes", 10), r => `${r.game.id}:${r.minutes}`);
        const recent = keep(prev?.recent, _top(rows.filter(r => r.last > 0), "last", 10), r => `${r.game.id}:${r.last}:${r.recentMin}:${r.sessionMin}`);
        const biggest = keep(prev?.biggest, _top(rows.filter(r => r.size > 0), "size", Infinity), r => `${r.game.id}:${r.size}`); // Every install: Storage scrolls
        const tierTotal = tierGames || 1;
        root._stats = {
            totalMin, total: games.length, installed, played, backlog, diskTotal, tierGames, recentTotalMin, recentGames,
            averageMin: played > 0 ? totalMin / played : 0,
            mostPlayed, maxMinutes: mostPlayed.length ? mostPlayed[0].minutes : 1,
            // The banner's game: the most played lately, else the most played of all
            lately: _top(rows.filter(r => r.recentMin > 0), "recentMin", 1)[0] ?? null,
            recent, biggest, maxSize: biggest.length ? biggest[0].size : 1,
            // Best to worst, the order _tierColors lists them in
            tiers: Object.keys(root._tierColors).filter(k => tiers[k]).map(k => ({ tier: k, count: tiers[k], fraction: tiers[k] / tierTotal }))
        };
    }

    // ─── Layout ───────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        // ── Banner: the art of what you've played most lately, back on it, then the headline numbers ──
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            ArtBanner {
                id: banner
                anchors.fill: parent
                showCover: false // The game is Recently played's headline: here, only its art
                // The most played in the last two weeks (else of all time). Not "top": an Item's own
                game: (root._stats?.lately ?? root._stats?.mostPlayed?.[0])?.game ?? null
                shadeMid: 0.72; shadeEnd: 0.55 // Lighter on the right: the numbers there carry their own card
                opacity: root.animationReady ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                TapHandler { enabled: !!banner.game; onTapped: root.gameSelected(banner.game) }
                HoverHandler { cursorShape: banner.game ? Qt.PointingHandCursor : Qt.ArrowCursor }

                RippleButton { // Back, on the art: solid, as the numbers' chips
                    id: backButton
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    implicitWidth: 36; implicitHeight: 36; padding: 0
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    contentItem: Item { MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 18; color: Appearance.colors.colOnLayer3 } }
                    onClicked: root.backPressed()
                    StyledToolTip { text: Translation.tr("Back") }
                }

                Item { // How much you've played, big, then the games played and the average as joined chips
                    anchors { left: backButton.right; leftMargin: 16; right: facts.left; rightMargin: 16; top: parent.top; bottom: parent.bottom }
                    clip: true // Narrow: the chips go under the facts' edge, never over them
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            StyledText { // Sets the row's height ("played" sits on its baseline)
                                id: hoursText
                                text: root._formatTime(root._stats?.totalMin ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.hugeass; font.weight: Font.Medium
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                anchors.baseline: hoursText.baseline
                                text: Translation.tr("played")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.2)
                            }
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            BannerChip {
                                first: true
                                icon: "sports_esports"
                                text: Translation.tr("%1 of %2 played").arg(root._thousands(root._stats?.played ?? 0)).arg(root._thousands(root._stats?.total ?? 0))
                            }
                            BannerChip {
                                last: true
                                icon: "avg_time"
                                text: Translation.tr("avg %1").arg(root._formatTime(root._stats?.averageMin ?? 0))
                            }
                        }
                    }
                }

                Row { // The other numbers, as joined chips (as the game page's facts)
                    id: facts
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    BannerFact {
                        first: true
                        icon: "download_done"; label: Translation.tr("Installed")
                        value: String(root._stats?.installed ?? 0); note: root._formatBytes(root._stats?.diskTotal ?? 0)
                        tip: (root._stats?.backlog ?? 0) === 1 ? Translation.tr("1 of them never played")
                            : (root._stats?.backlog ?? 0) > 1 ? Translation.tr("%1 of them never played").arg(root._stats.backlog) : ""
                    }
                    BannerFact {
                        icon: "history"; label: Translation.tr("Last 2 weeks")
                        value: root._formatTime(root._stats?.recentTotalMin ?? 0)
                        note: (root._stats?.recentGames ?? 0) === 1 ? Translation.tr("1 game") : Translation.tr("%1 games").arg(root._stats?.recentGames ?? 0)
                    }
                    BannerFact { // The library's ProtonDB: one bar, the counts in its tooltip
                        last: true
                        icon: "verified"; label: Translation.tr("ProtonDB")
                        value: (root._stats?.tierGames ?? 0) > 0 ? root._thousands(root._stats.tierGames) : Translation.tr("None")
                        note: Translation.tr("rated")
                        tip: (root._stats?.tiers ?? []).map(t => t.count + " " + t.tier).join("  ·  ")
                        Item { // Sized here, the Row only fills it (segments sized from a layout-managed Row looped)
                            width: 120; height: 6
                            visible: (root._stats?.tierGames ?? 0) > 0
                            Row {
                                id: tierBar
                                anchors.fill: parent
                                spacing: 2
                                Repeater {
                                    model: root._stats?.tiers ?? []
                                    Rectangle {
                                        required property var modelData
                                        width: Math.max(4, (tierBar.width - 2 * ((root._stats?.tiers?.length ?? 1) - 1)) * modelData.fraction)
                                        height: tierBar.height
                                        radius: 3
                                        color: ColorUtils.mix(root._tierColors[modelData.tier] ?? Appearance.colors.colPrimary, Appearance.colors.colPrimary, 0.5)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Cards: each scrolls inside itself ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            visible: root._stats !== null

            Card { // What you've played most lately on its art, then the latest games as their covers
                order: 1
                weight: 1.15
                iconName: "history"
                title: Translation.tr("Recently played")
                caption: Translation.tr("Last 2 weeks") // What the times under the covers count
                Headline {
                    // The most played in the last two weeks, else just the latest
                    readonly property var row: root._recentHero
                    readonly property bool lately: (root._stats?.lately ?? null) !== null
                    visible: !!row
                    solo: true
                    game: row?.game ?? null
                    name: row?.game?.name ?? ""
                    line: !row ? "" : lately ? Translation.tr("%1 of your last 2 weeks").arg(root._formatTime(row.recentMin))
                        : root._ago(row.last) + (row.sessionMin > 0 ? "  ·  " + root._formatTime(row.sessionMin) : "")
                    share: lately ? row.recentMin / Math.max(1, root._stats.recentTotalMin) : -1
                    chip: share >= 0 ? Math.round(share * 100) + "%" : ""
                }
                StatList {
                    id: recentList
                    visible: count > 0
                    Layout.topMargin: 5
                    orientation: ListView.Horizontal
                    spacing: 8
                    snapMode: ListView.SnapToItem // Scrolled a cover at a time: none left cut off
                    // As many whole covers as fit at about 2:3, widened a little to fill the card exactly. At the height
                    // it ends at (the list clips them until it gets there)
                    readonly property real restingHeight: height + root.growBy
                    readonly property int fits: Math.max(1, Math.floor((width + spacing) / ((restingHeight - 40) * 2 / 3 + spacing)))
                    readonly property real posterWidth: Math.floor((width - spacing * (fits - 1)) / fits)
                    model: root._recentRows
                    delegate: PosterTile {
                        required property var modelData
                        width: recentList.posterWidth
                        height: recentList.restingHeight
                        game: modelData.game
                        // Under the name: when, and the time in the last two weeks (else the last session)
                        detail: root._ago(modelData.last) + (modelData.recentMin > 0 ? "  ·  " + root._formatTime(modelData.recentMin)
                            : modelData.sessionMin > 0 ? "  ·  " + root._formatTime(modelData.sessionMin) : "")
                    }
                }
                Empty { visible: recentList.count === 0 && !root._recentHero; text: Translation.tr("Nothing played yet") }
            }

            Card { // The most played on its art with its share of all your time, then the next ones ranked
                order: 2
                iconName: "emoji_events"
                title: Translation.tr("Most played")
                Headline {
                    readonly property var row: root._stats?.mostPlayed?.[0] ?? null
                    visible: !!row
                    solo: mostList.count === 0
                    game: row?.game ?? null
                    name: row?.game?.name ?? ""
                    share: row ? row.minutes / Math.max(1, root._stats.totalMin) : -1
                    line: !row ? "" : Translation.tr("%1  ·  %2% of all your time").arg(root._formatTime(row.minutes)).arg(Math.round(share * 100))
                    chip: "1"
                }
                StatList {
                    id: mostList
                    visible: count > 0
                    model: root._mostRows
                    delegate: GameRow {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        last: index === ListView.view.count - 1
                        game: modelData.game
                        rank: index + 2 // The first is the headline
                        trailing: root._formatTime(modelData.minutes)
                        fraction: modelData.minutes / root._stats.maxMinutes
                    }
                }
                Empty { visible: !root._stats?.mostPlayed?.length; text: Translation.tr("Nothing played yet") }
            }

            // What's downloading, then every install, biggest first; or (Review) what uninstalled games left behind
            Card {
                order: 3
                iconName: "hard_drive"
                title: root._showLeftovers ? Translation.tr("Left behind") : Translation.tr("Storage")
                caption: !root._showLeftovers && root._freeBytes >= 0 ? Translation.tr("%1 free").arg(root._formatBytes(root._freeBytes)) : ""
                Headline { // The drive: what the games take and what's free, one bar of it sliced by game, on the biggest's art
                    id: drive
                    visible: (root._stats?.biggest?.length ?? 0) > 0
                    solo: false
                    clickable: false
                    game: root._stats?.biggest?.[0]?.game ?? null
                    shadeMid: 0.82; shadeEnd: 0.72 // The bar runs the whole width
                    readonly property real games: root._stats?.diskTotal ?? 0
                    readonly property real whole: Math.max(1, games + Math.max(0, root._freeBytes))
                    Column {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                        spacing: 8
                        Row {
                            spacing: 6
                            StyledText {
                                id: gamesSize
                                text: root._formatBytes(drive.games)
                                font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Medium
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({}) // Not Roboto Flex's tuning
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                anchors.baseline: gamesSize.baseline
                                text: root._freeBytes >= 0 ? Translation.tr("of games  ·  %1 free").arg(root._formatBytes(root._freeBytes)) : Translation.tr("of games")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
                            }
                        }
                        Item { // Sized here, the Row only fills it
                            id: driveBar
                            width: parent.width; height: 10
                            Rectangle { anchors.fill: parent; radius: 5; color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88) }
                            Row {
                                height: parent.height
                                spacing: 2
                                Repeater {
                                    model: root._driveSlices
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        height: driveBar.height
                                        width: Math.max(4, driveBar.width * modelData.size / drive.whole) * (root.animationReady ? 1 : 0)
                                        color: root._sliceColor(modelData.slice)
                                        topLeftRadius: index === 0 ? 5 : 2; bottomLeftRadius: topLeftRadius
                                        topRightRadius: 2; bottomRightRadius: 2
                                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }
                StatList {
                    id: storageList
                    visible: !root._showLeftovers && count > 0
                    // Downloads ({ item, game }) first, then the installs ({ game, size })
                    model: root._showLeftovers ? [] : root._storageRows
                    delegate: GameRow {
                        required property var modelData
                        required property int index
                        readonly property var item: modelData.appid ? root._downloadItem(modelData.appid) : null // Live
                        width: ListView.view.width
                        last: index === ListView.view.count - 1 && !leftoversButton.visible
                        // Its slice of the drive's colour (a download not yet installed: the accent)
                        barColor: modelData.size ? root._sliceColor(root._sliceOf[modelData.game.id] ?? 4) : Appearance.colors.colPrimary
                        game: modelData.game
                        // Installed and updating: its size, the update under the name (with what's left of it)
                        subtitle: !item ? "" : modelData.size ? root._downloadText(item) + "  ·  " + Translation.tr("%1 left").arg(root._formatBytes(item.toDownload))
                            : root._downloadText(item)
                        trailing: modelData.size ? root._formatBytes(modelData.size) : item ? root._formatBytes(item.toDownload) : ""
                        fraction: modelData.appid ? Math.max(0, item?.progress ?? 0) : modelData.size / root._stats.maxSize
                    }
                }
                Empty { visible: storageList.count === 0 && !root._showLeftovers; text: Translation.tr("No install sizes found") }
                RippleButton { // "Left by N uninstalled games · size  Review": the group's last piece
                    id: leftoversButton
                    Layout.fillWidth: true
                    implicitHeight: 36
                    visible: !root._showLeftovers && root._leftovers.length > 0
                    buttonRadiusTop: Appearance.rounding.joined
                    buttonRadiusBottom: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: root._showLeftovers = true
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        MaterialSymbol { text: "cleaning_services"; iconSize: 16; color: Appearance.colors.colSubtext }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            text: Translation.tr("Left by %1 uninstalled games · %2").arg(root._leftovers.length).arg(root._formatBytes(root._leftoverTotal))
                        }
                        StyledText { text: Translation.tr("Review"); font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium; color: Appearance.colors.colPrimary }
                    }
                }
                // ── Review: one row per game, with what it left and a delete (click twice) ──
                Rectangle { // A joined piece under the drive, as the rows under it
                    Layout.fillWidth: true
                    implicitHeight: 40
                    visible: root._showLeftovers
                    radius: Appearance.rounding.joined
                    color: Appearance.colors.colLayer3
                    RowLayout {
                        anchors { fill: parent; leftMargin: 5; rightMargin: 6 }
                        spacing: 6
                        RippleButton {
                            implicitWidth: 30; implicitHeight: 30
                            buttonRadius: Appearance.rounding.segment
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            onClicked: root._showLeftovers = false
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 16; color: Appearance.colors.colOnLayer3 }
                            StyledToolTip { text: Translation.tr("Back to storage") }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Saves not in Steam Cloud go too")
                        }
                        DeleteButton {
                            label: armed ? Translation.tr("Delete all?") : Translation.tr("Delete all")
                            onConfirmed: root._removeLeftovers(root._leftovers.map(e => e.appid))
                        }
                    }
                }
                StatList {
                    visible: root._showLeftovers
                    model: root._leftovers
                    delegate: RowLayout {
                        id: leftoverRow
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        spacing: 4
                        GameRow {
                            last: leftoverRow.index === leftoverRow.ListView.view.count - 1
                            game: root._leftoverGame(modelData)
                            subtitle: Translation.tr("Last used %1").arg(root._ago(modelData.modified * 1000).toLowerCase())
                            trailing: root._formatBytes(modelData.size)
                        }
                        DeleteButton { onConfirmed: root._removeLeftovers([modelData.appid]) }
                    }
                }
            }

            Card { // The library's captures: the newest large, the next four under it, the totals as the caption
                order: 4
                iconName: "perm_media"
                title: Translation.tr("Captures")
                caption: root._captures ? [
                    root._captures.shots === 1 ? Translation.tr("1 shot") : Translation.tr("%1 shots").arg(root._captures.shots),
                    root._captures.clips === 1 ? Translation.tr("1 clip") : Translation.tr("%1 clips").arg(root._captures.clips),
                    root._formatBytes(root._captures.shotBytes + root._captures.clipBytes)
                ].join("  ·  ") : ""
                Item { // Sized by the card: the newest fills what the strip leaves
                    id: capturesArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: (root._captures?.latest?.length ?? 0) > 0
                    readonly property var latest: root._captures?.latest ?? []
                    readonly property int gap: 6
                    readonly property real stripHeight: latest.length > 1 ? Math.round((width - 3 * gap) / 4 * 9 / 16) : 0
                    CaptureThumb { // The card's title rides on its top; joined to the strip under it
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: strip.top
                                  bottomMargin: capturesArea.stripHeight > 0 ? capturesArea.gap : 0 }
                        capture: capturesArea.latest[0] ?? ({})
                        large: true
                        bottomLeftRadius: capturesArea.stripHeight > 0 ? Appearance.rounding.joined : Appearance.rounding.small
                        bottomRightRadius: bottomLeftRadius
                    }
                    Row {
                        id: strip
                        anchors { left: parent.left; bottom: parent.bottom }
                        height: capturesArea.stripHeight
                        spacing: capturesArea.gap
                        Repeater {
                            model: capturesArea.latest.slice(1, 5)
                            CaptureThumb {
                                required property var modelData
                                required property int index
                                width: (capturesArea.width - 3 * capturesArea.gap) / 4
                                height: strip.height
                                capture: modelData
                                // Joined: round only at the group's bottom corners
                                topLeftRadius: Appearance.rounding.joined; topRightRadius: Appearance.rounding.joined
                                bottomLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.joined
                                bottomRightRadius: index === capturesArea.latest.slice(1, 5).length - 1 ? Appearance.rounding.small : Appearance.rounding.joined
                            }
                        }
                    }
                }
                Empty {
                    visible: root._captures !== null && (root._captures.latest?.length ?? 0) === 0
                    text: Translation.tr("No screenshots or clips yet")
                }
            }
        }
    }

    // ─── Components ───────────────────────────────────────────
    // Tiles and cards fade in one after another
    component Surface: Rectangle {
        property int order: 0
        property real weight: 1
        Layout.fillWidth: true
        Layout.preferredWidth: 100 * weight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1 // Under its joined pieces (colLayer3)
        opacity: root.animationReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260 + order * 50; easing.type: Easing.OutCubic } }
    }

    // A number on the banner: a chip of the joined row, its icon in an accent square, a small name over the value
    // (bright, in the numbers' font) and a quieter note beside it. Anything added goes under them (ProtonDB's bar)
    component BannerFact: Rectangle {
        id: fact
        property string icon
        property string label
        property string value
        property string note: ""
        property string tip: ""
        property bool first: false
        property bool last: false
        default property alias content: factCol.data
        implicitWidth: factInner.implicitWidth + 22
        implicitHeight: 50
        color: Appearance.colors.colLayer3
        topLeftRadius: first ? Appearance.rounding.small : Appearance.rounding.joined
        bottomLeftRadius: topLeftRadius
        topRightRadius: last ? Appearance.rounding.small : Appearance.rounding.joined
        bottomRightRadius: topRightRadius
        Row {
            id: factInner
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 9
                color: Appearance.colors.colLayer3Accent
                MaterialSymbol { anchors.centerIn: parent; text: fact.icon; iconSize: 18; color: Appearance.colors.colPrimary }
            }
            Column {
                id: factCol
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                StyledText {
                    text: fact.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Row {
                    spacing: 6
                    StyledText {
                        text: fact.value
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({}) // Not Roboto Flex's tuning
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        visible: fact.note !== ""
                        text: fact.note
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
        HoverHandler { id: factHover }
        StyledToolTip { text: fact.tip; visible: fact.tip !== "" && factHover.hovered }
    }

    // A recently played game: its cover, the name and a line under it. Opens its details
    component PosterTile: RippleButton { // Its width is the list's (a whole number of them fill it)
        id: poster
        property var game
        property string detail
        readonly property string art: GameLauncherService.localArt(game, "boxArt")
        padding: 0
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colRipple: "transparent"
        onClicked: if (poster.game) root.gameSelected(poster.game)
        contentItem: Item {
            ClippingRectangle {
                id: posterArt
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: parent.height - 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer4
                Image {
                    anchors.fill: parent
                    source: poster.art
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // One fixed size: the cover's own follows the page's height, which eases as it opens, and a
                    // changing sourceSize decodes it again each frame (it flickered, as the grid's once did)
                    sourceSize.width: 400
                    scale: poster.hovered ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: poster.art === ""
                    text: "sports_esports"; iconSize: 24
                    color: Appearance.colors.colSubtext
                }
                Rectangle { // Hover edge (the clip's own radius: its parent here is its content item)
                    anchors.fill: parent
                    radius: posterArt.radius
                    color: "transparent"
                    border.width: poster.hovered ? 2 : 1
                    border.color: poster.hovered ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                }
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: posterArt.bottom; topMargin: 6 }
                spacing: 1
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: poster.game?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: poster.detail
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // One of the newest captures: its picture (a play mark on clips); opens its game's Captures on it. Large: the
    // card's newest, its full picture with the game and when over it
    component CaptureThumb: ClippingRectangle {
        id: thumb
        property var capture
        property bool large: false
        readonly property var game: capture?.kind ? root._captureGame(capture) : null
        readonly property bool lit: thumbHover.hovered && !!thumb.game
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer4
        Image {
            anchors.fill: parent
            readonly property string file: (thumb.large ? thumb.capture?.full : thumb.capture?.image) ?? ""
            source: file ? "file://" + file : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // By width only, in steps (a fixed one for the small ones): the card's height eases as the page opens,
            // and a changing sourceSize decodes it again each frame, which flickers
            sourceSize.width: thumb.large ? Math.ceil(thumb.width * 1.5 / 256) * 256 : 320
            scale: thumb.lit ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        Rectangle { // Large: shade under the caption
            visible: thumb.large
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.min(parent.height, 64)
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: ColorUtils.transparentize("black", 0.35) }
            }
        }
        Row { // Large: what it is, from what game, when
            visible: thumb.large
            anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 10 }
            spacing: 8
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: thumb.capture?.kind === "clip"
                text: "play_circle"; iconSize: 20; fill: 1
                color: "white"
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                StyledText {
                    text: thumb.game?.name ?? thumb.capture?.game ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold
                    color: "white"
                }
                StyledText {
                    text: (thumb.capture?.time ?? 0) > 0 ? root._ago(thumb.capture.time * 1000) + "  ·  "
                        + new Date(thumb.capture.time * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : ""
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: ColorUtils.transparentize("white", 0.25)
                }
            }
        }
        MaterialSymbol { // Small: the play mark
            anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
            visible: !thumb.large && thumb.capture?.kind === "clip"
            text: "play_circle"; iconSize: 16; fill: 1
            color: "white"
        }
        Rectangle { // Hover edge (the clip's own corners: its parent here is its content item)
            anchors.fill: parent
            topLeftRadius: thumb.topLeftRadius; topRightRadius: thumb.topRightRadius
            bottomLeftRadius: thumb.bottomLeftRadius; bottomRightRadius: thumb.bottomRightRadius
            color: "transparent"
            border.width: thumb.lit ? 2 : 1
            border.color: thumb.lit ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
        }
        HoverHandler { id: thumbHover; cursorShape: thumb.game ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: !!thumb.game; onTapped: root.capturesSelected(thumb.game, thumb.capture.kind === "clip" ? "clips" : "shots") }
        StyledToolTip { text: thumb.game?.name ?? ""; visible: !thumb.large && thumbHover.hovered && text !== "" }
    }

    // A card's list: fills what the card leaves, scrolls inside it
    component StatList: StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        animateAppearance: false // Rows would pop in again whenever a list changes
    }

    // A card: its pieces joined in a column (a headline on art first), the title and caption as chips over its top
    component Card: Surface {
        id: card
        property string iconName
        property string title
        property string caption // Small, on the right
        default property alias content: cardCol.data
        Layout.fillHeight: true
        ColumnLayout {
            id: cardCol
            anchors { fill: parent; margins: 8 }
            spacing: 3
        }
        Rectangle { // The title: icon in a tinted square, the name
            x: 16; y: 16
            width: titleRow.implicitWidth + 16; height: 32
            radius: Appearance.rounding.small - 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.22)
            Row {
                id: titleRow
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle {
                    width: 24; height: 24; radius: 7
                    color: Appearance.colors.colLayer3Accent
                    MaterialSymbol { anchors.centerIn: parent; text: card.iconName; iconSize: 15; color: Appearance.colors.colPrimary }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.title
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
            }
        }
        Rectangle { // The caption
            visible: card.caption.length > 0
            anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: 16 }
            width: captionText.implicitWidth + 20; height: 32
            radius: Appearance.rounding.small - 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.22)
            StyledText {
                id: captionText
                anchors.centerIn: parent
                text: card.caption
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.15)
            }
        }
    }

    // A list's headline: a game on its art (the card's title chips over its top), its name and a line at the bottom
    // left, a value in an accent chip on the right (a share, the rank) and the share as a bar along the bottom.
    // Opens the game. Anything added goes over the art (Storage's drive)
    component Headline: ArtBanner {
        id: headline
        property string name
        property string line
        property string chip: ""
        property real share: -1 // < 0: no bar
        property bool solo: false // Nothing joined under it: rounded at the bottom too
        property bool clickable: true
        Layout.fillWidth: true
        Layout.preferredHeight: 106
        showCover: false
        shadeMid: 0.5; shadeEnd: 0.15 // The text is on the left: the art shows on the right
        topLeftRadius: Appearance.rounding.small; topRightRadius: Appearance.rounding.small
        bottomLeftRadius: solo ? Appearance.rounding.small : Appearance.rounding.joined
        bottomRightRadius: bottomLeftRadius
        TapHandler { enabled: headline.clickable && !!headline.game; onTapped: root.gameSelected(headline.game) }
        HoverHandler { cursorShape: headline.clickable && headline.game ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Column {
            visible: headline.name !== ""
            anchors { left: parent.left; leftMargin: 12; right: headChip.left; rightMargin: 12; bottom: parent.bottom; bottomMargin: headline.share >= 0 ? 16 : 12 }
            spacing: 1
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: headline.name
                font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: headline.line
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.22)
            }
        }
        Rectangle { // Under the card's caption chip
            id: headChip
            visible: headline.chip !== ""
            anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 46 }
            width: Math.max(28, headChipText.implicitWidth + 16); height: 28
            radius: 8
            color: Appearance.colors.colLayer3Accent
            StyledText {
                id: headChipText
                anchors.centerIn: parent
                text: headline.chip
                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({}) // Not Roboto Flex's tuning
                color: Appearance.colors.colPrimary
            }
        }
        Item { // The share
            visible: headline.share >= 0
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 7 }
            height: 4
            Rectangle { anchors.fill: parent; radius: 2; color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85) }
            Rectangle {
                width: parent.width * Math.max(0.02, Math.min(1, headline.share)) * (root.animationReady ? 1 : 0)
                height: parent.height
                radius: 2
                color: Appearance.colors.colPrimary
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            }
        }
    }

    // A chip of the banner's joined pair: icon and text
    component BannerChip: Rectangle {
        id: bchip
        property string icon
        property string text
        property bool first: false
        property bool last: false
        width: bchipRow.implicitWidth + 20; height: 30
        color: Appearance.colors.colLayer3
        topLeftRadius: first ? Appearance.rounding.small - 2 : Appearance.rounding.joined
        bottomLeftRadius: topLeftRadius
        topRightRadius: last ? Appearance.rounding.small - 2 : Appearance.rounding.joined
        bottomRightRadius: topRightRadius
        Row {
            id: bchipRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: bchip.icon; iconSize: 15; color: Appearance.colors.colPrimary }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: bchip.text
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer3
            }
        }
    }

    // A game: box art, name (+ subtitle or a bar), value on the right. Opens its details. A joined piece under
    // its card's headline: rounded only at the group's bottom (last)
    component GameRow: RippleButton {
        id: row
        property var game
        property int rank: 0
        property string subtitle
        property string trailing
        property real fraction: -1 // < 0: no bar
        property color barColor: Appearance.colors.colPrimary
        property bool last: false
        Layout.fillWidth: true
        implicitHeight: 44
        buttonRadiusTop: Appearance.rounding.joined
        buttonRadiusBottom: last ? Appearance.rounding.small : Appearance.rounding.joined
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        onClicked: if (row.game && !row.game._placeholder) root.gameSelected(row.game)
        contentItem: RowLayout {
            anchors { fill: parent; leftMargin: 6; rightMargin: 10 }
            spacing: 10
            StyledText {
                visible: row.rank > 0
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: row.rank
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }
            Item {
                implicitWidth: 26; implicitHeight: 34
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.chip
                    color: Appearance.colors.colLayer4
                    visible: thumb.status !== Image.Ready
                    MaterialSymbol { anchors.centerIn: parent; text: "sports_esports"; iconSize: 14; color: Appearance.colors.colSubtext }
                }
                ClippingRectangle { // Rounded without an offscreen layer per row
                    anchors.fill: parent
                    radius: Appearance.rounding.chip
                    color: thumb.box ? "transparent" : Appearance.colors.colLayer4
                    visible: thumb.status === Image.Ready
                    Image {
                        id: thumb
                        anchors.fill: parent
                        // Your own cover if you set one (as the grid), else the game's, else its logo or icon (fitted)
                        readonly property string box: GameLauncherService.localArt(row.game, "boxArt")
                        readonly property string art: box || GameLauncherService.logoArt(row.game)
                        source: art ? "file://" + art : ""
                        fillMode: box ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize: Qt.size(56, 76)
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.game?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    visible: row.subtitle !== ""
                    text: row.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Rectangle { // Bar, relative to the top entry
                    visible: row.fraction >= 0
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Appearance.colors.colLayer4
                    Rectangle {
                        width: parent.width * Math.max(0.03, Math.min(1, row.fraction)) * (root.animationReady ? 1 : 0)
                        height: parent.height
                        radius: 2
                        color: row.barColor
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                    }
                }
            }
            StyledText {
                visible: row.trailing !== ""
                text: row.trailing
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    // Delete, in two clicks: the first arms it (solid red) for a few seconds, the second confirms
    component DeleteButton: RippleButton {
        id: del
        property bool armed: false
        property string label: "" // Text instead of the icon (text is the button's own, final)
        signal confirmed()
        implicitHeight: 28
        implicitWidth: label !== "" ? delLabel.implicitWidth + 20 : 28
        buttonRadius: Appearance.rounding.chip
        colBackground: armed ? Appearance.colors.colError : "transparent"
        colBackgroundHover: armed ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colError, 0.88)
        colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
        onClicked: {
            if (!armed) { armed = true; disarm.restart(); return; }
            armed = false;
            confirmed();
        }
        Timer { id: disarm; interval: 4000; onTriggered: del.armed = false }
        contentItem: Item {
            MaterialSymbol {
                visible: del.label === ""
                anchors.centerIn: parent
                text: del.armed ? "check" : "delete"; iconSize: 16
                color: del.armed ? Appearance.m3colors.m3onError : Appearance.colors.colError
            }
            StyledText {
                id: delLabel
                visible: del.label !== ""
                anchors.centerIn: parent
                text: del.label
                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                color: del.armed ? Appearance.m3colors.m3onError : Appearance.colors.colError
            }
        }
        StyledToolTip { text: del.armed ? Translation.tr("Click again to delete") : Translation.tr("Delete") }
    }

    component Empty: StyledText { // Fills the space its hidden list leaves
        Layout.fillWidth: true
        Layout.fillHeight: true
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
