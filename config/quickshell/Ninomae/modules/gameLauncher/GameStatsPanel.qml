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
    property var _storageRows: [] // Downloads ({ appid, game }, with size when installed) first, then the installs ({ game, size })
    // Recently played's hero: the most played in the last two weeks, else the latest. Its covers are the rest
    readonly property var _recentHero: _stats?.lately ?? _stats?.recent?.[0] ?? null
    on_StatsChanged: {
        // Lists without their headline's game: new arrays only when their rows change (see _recompute's keep)
        const same = (a, b, key) => a.length === b.length && a.every((r, i) => key(r) === key(b[i]));
        const heroId = _recentHero?.game.id;
        const recent = (_stats?.recent ?? []).filter(r => r.game.id !== heroId);
        if (!same(recent, _recentRows, r => `${r.game.id}:${r.last}:${r.recentMin}:${r.sessionMin}`)) _recentRows = recent;
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
    // T1b: one object, as the home's toolbar and well: a header strip (back, your hours, the rest as one line of facts)
    // joined over a block holding Recently played as the hero on the left, and Most played, Storage and Captures
    // stacked on the right, each its art as a tile beside a well. The fine edge light runs round the whole of it
    readonly property color _wellColor: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45)
    ColumnLayout {
        id: page
        anchors { fill: parent; margins: 16 }
        spacing: 3 // The header joined to the block
        opacity: root.animationReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        // ── Header: back, the hours, the rest as one line with dots ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            topLeftRadius: Appearance.rounding.normal; topRightRadius: Appearance.rounding.normal
            bottomLeftRadius: Appearance.rounding.joined; bottomRightRadius: Appearance.rounding.joined
            color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerHigh, 0.3)
            RippleButton {
                id: backButton
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                implicitWidth: 40; implicitHeight: 40; padding: 0
                buttonRadius: 12
                colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.85)
                contentItem: Item { MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 20; color: Appearance.colors.colOnLayer0 } }
                onClicked: root.backPressed()
                StyledToolTip { text: Translation.tr("Back") }
            }
            Row {
                anchors { left: backButton.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 8
                StyledText {
                    id: hoursText
                    text: root._formatTime(root._stats?.totalMin ?? 0)
                    font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.Medium
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.baseline: hoursText.baseline
                    text: Translation.tr("played")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtextGlass
                }
            }
            Row { // The rest, as the bar's parts: dots between
                id: facts
                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 12
                Repeater {
                    // Each with what it doesn't say in its tooltip: the installs never played, ProtonDB's tiers
                    model: [
                        { text: Translation.tr("%1 of %2 played").arg(root._thousands(root._stats?.played ?? 0)).arg(root._thousands(root._stats?.total ?? 0)) },
                        { text: Translation.tr("avg %1").arg(root._formatTime(root._stats?.averageMin ?? 0)) },
                        { text: Translation.tr("%1 installed · %2").arg(root._stats?.installed ?? 0).arg(root._formatBytes(root._stats?.diskTotal ?? 0)),
                          tip: (root._stats?.backlog ?? 0) === 1 ? Translation.tr("1 of them never played")
                              : (root._stats?.backlog ?? 0) > 1 ? Translation.tr("%1 of them never played").arg(root._stats.backlog) : "" },
                        { text: Translation.tr("%1 in 2 weeks").arg(root._formatTime(root._stats?.recentTotalMin ?? 0)) },
                        { text: (root._stats?.tierGames ?? 0) > 0 ? Translation.tr("%1 rated on ProtonDB").arg(root._thousands(root._stats.tierGames)) : "",
                          tip: (root._stats?.tiers ?? []).map(t => t.count + " " + t.tier).join("  ·  ") }
                    ].filter(f => f.text !== "")
                    Row {
                        required property var modelData
                        required property int index
                        spacing: 12
                        Rectangle { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 3; radius: 1.5
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.6) }
                        StyledText {
                            text: modelData.text
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: Appearance.colors.colOnLayer0
                            HoverHandler { id: factHover }
                            StyledToolTip { text: modelData.tip ?? ""; visible: text !== "" && factHover.hovered }
                        }
                    }
                }
            }
        }

        // ── The block: the hero, then the column ──
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            topLeftRadius: Appearance.rounding.joined; topRightRadius: Appearance.rounding.joined
            bottomLeftRadius: Appearance.rounding.normal; bottomRightRadius: Appearance.rounding.normal
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.55)
            RowLayout {
                anchors { fill: parent; margins: 8 }
                spacing: 8
                visible: root._stats !== null

                // Recently played: what you've played most lately big on its art, the rest of the latest as covers
                ColumnLayout {
                    id: hero
                    Layout.preferredWidth: parent.width * 0.42
                    Layout.maximumWidth: parent.width * 0.42
                    Layout.fillHeight: true
                    spacing: 3
                    Headline {
                        readonly property var row: root._recentHero
                        readonly property bool lately: (root._stats?.lately ?? null) !== null
                        // From the row's height (its anchors'), not the column's: that's the layout's own, a loop
                        Layout.preferredHeight: Math.round(hero.parent.height * 0.46)
                        solo: recentList.count === 0
                        topLeftRadius: Appearance.rounding.normal; topRightRadius: Appearance.rounding.normal
                        game: row?.game ?? null
                        name: row?.game?.name ?? ""
                        nameSize: Appearance.font.pixelSize.huge
                        line: !row ? "" : lately ? Translation.tr("%1 of your last 2 weeks").arg(root._formatTime(row.recentMin))
                            : GameLauncherService.agoText(row.last) + (row.sessionMin > 0 ? "  ·  " + root._formatTime(row.sessionMin) : "")
                        share: lately ? row.recentMin / Math.max(1, root._stats.recentTotalMin) : -1
                        chip: share >= 0 ? Math.round(share * 100) + "%" : ""
                        CardTitle { iconName: "history"; title: Translation.tr("Recently played") }
                    }
                    Well {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: recentList.count > 0
                        topLeftRadius: Appearance.rounding.joined; topRightRadius: Appearance.rounding.joined
                        StatList {
                            id: recentList
                            anchors { fill: parent; margins: 10 }
                            orientation: ListView.Horizontal
                            spacing: 10
                            snapMode: ListView.SnapToItem // Scrolled a cover at a time: none left cut off
                            // As many whole covers as fit at about 2:3, widened a little to fill the well exactly. At the
                            // height it ends at (the list clips them until it gets there)
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
                                detail: GameLauncherService.agoText(modelData.last) + (modelData.recentMin > 0 ? "  ·  " + root._formatTime(modelData.recentMin)
                                    : modelData.sessionMin > 0 ? "  ·  " + root._formatTime(modelData.sessionMin) : "")
                            }
                        }
                    }
                    Empty { visible: recentList.count === 0 && !root._recentHero; text: Translation.tr("Nothing played yet") }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    SideCard { // Every game you've played, most first
                        iconName: "emoji_events"
                        title: Translation.tr("Most played")
                        game: root._stats?.mostPlayed?.[0]?.game ?? null
                        value: root._stats?.mostPlayed?.[0] ? root._formatTime(root._stats.mostPlayed[0].minutes) : ""
                        GameGrid {
                            id: mostList
                            anchors { fill: parent; margins: 4 }
                            model: root._stats?.mostPlayed ?? []
                            delegate: GameRow {
                                required property var modelData
                                required property int index
                                width: mostList.cellWidth - 4; height: mostList.cellHeight
                                game: modelData.game
                                rank: index + 1
                                trailing: root._formatTime(modelData.minutes)
                                fraction: modelData.minutes / root._stats.maxMinutes
                            }
                        }
                        Empty { anchors.fill: parent; visible: mostList.count === 0; text: Translation.tr("Nothing played yet") }
                    }

                    SideCard { // The drive sliced by game, then what's downloading and every install; or what uninstalled games left
                        id: storageCard
                        iconName: "hard_drive"
                        title: root._showLeftovers ? Translation.tr("Left behind") : Translation.tr("Storage")
                        game: root._stats?.biggest?.[0]?.game ?? null
                        value: root._freeBytes >= 0 ? Translation.tr("%1 free").arg(root._formatBytes(root._freeBytes)) : ""
                        readonly property real games: root._stats?.diskTotal ?? 0
                        readonly property real whole: Math.max(1, games + Math.max(0, root._freeBytes))
                        under: Item { // On the tile, under what's free: the drive, each of the four biggest a slice, the rest one
                            id: driveBar
                            width: parent?.width ?? 0
                            height: 6
                            visible: !root._showLeftovers && (root._stats?.biggest?.length ?? 0) > 0
                            Rectangle { anchors.fill: parent; radius: 3; color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.8) }
                            Row {
                                height: parent.height
                                spacing: 1
                                Repeater {
                                    model: root._driveSlices
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        height: driveBar.height
                                        width: Math.max(3, driveBar.width * modelData.size / storageCard.whole) * (root.animationReady ? 1 : 0)
                                        color: root._sliceColor(modelData.slice)
                                        topLeftRadius: index === 0 ? 3 : 1; bottomLeftRadius: topLeftRadius
                                        topRightRadius: 1; bottomRightRadius: 1
                                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            anchors { fill: parent; margins: 4 }
                            spacing: 2
                            GameGrid {
                                id: storageList
                                visible: !root._showLeftovers && count > 0
                                // Downloads ({ appid, game }) first, then the installs ({ game, size })
                                model: root._showLeftovers ? [] : root._storageRows
                                delegate: GameRow {
                                    required property var modelData
                                    readonly property var item: modelData.appid ? root._downloadItem(modelData.appid) : null // Live
                                    width: storageList.cellWidth - 4; height: storageList.cellHeight
                                    // Its slice of the drive's colour (a download not yet installed: the accent)
                                    barColor: modelData.size ? root._sliceColor(root._sliceOf[modelData.game.id] ?? 4) : Appearance.colors.colPrimary
                                    game: modelData.game
                                    subtitle: !item ? "" : modelData.size ? root._downloadText(item) + "  ·  " + Translation.tr("%1 left").arg(root._formatBytes(item.toDownload))
                                        : root._downloadText(item)
                                    trailing: modelData.size ? root._formatBytes(modelData.size) : item ? root._formatBytes(item.toDownload) : ""
                                    fraction: modelData.appid ? Math.max(0, item?.progress ?? 0) : modelData.size / root._stats.maxSize
                                }
                            }
                            Empty { visible: storageList.count === 0 && !root._showLeftovers; text: Translation.tr("No install sizes found") }
                            RippleButton { // "Left by N uninstalled games · size  Review"
                                Layout.fillWidth: true
                                implicitHeight: 32
                                visible: !root._showLeftovers && root._leftovers.length > 0
                                buttonRadius: 12
                                colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
                                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
                                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.85)
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
                            // ── Review: back, a note, delete all; then one row per game with a delete (click twice) ──
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root._showLeftovers
                                spacing: 6
                                RippleButton {
                                    implicitWidth: 30; implicitHeight: 30
                                    buttonRadius: Appearance.rounding.segment
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
                                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
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
                            StatList {
                                visible: root._showLeftovers
                                model: root._leftovers
                                delegate: RowLayout {
                                    id: leftoverRow
                                    required property var modelData
                                    width: ListView.view.width
                                    spacing: 4
                                    GameRow {
                                        game: root._leftoverGame(modelData)
                                        subtitle: Translation.tr("Last used %1").arg(GameLauncherService.agoText(modelData.modified * 1000).toLowerCase())
                                        trailing: root._formatBytes(modelData.size)
                                    }
                                    DeleteButton { onConfirmed: root._removeLeftovers([modelData.appid]) }
                                }
                            }
                        }
                    }

                    SideCard { // The newest screenshots and clips, as many as fit; the totals on the tile
                        id: capturesCard
                        readonly property var latest: root._captures?.latest ?? []
                        iconName: "perm_media"
                        title: Translation.tr("Captures")
                        art: latest[0]?.full ? "file://" + latest[0].full : ""
                        value: root._captures ? [
                            root._captures.shots === 1 ? Translation.tr("1 shot") : Translation.tr("%1 shots").arg(root._captures.shots),
                            root._captures.clips === 1 ? Translation.tr("1 clip") : Translation.tr("%1 clips").arg(root._captures.clips)
                        ].join("  ·  ") : ""
                        Row {
                            id: capturesRow
                            anchors { fill: parent; margins: 8 }
                            spacing: 6
                            clip: true
                            // As many as fit at about 16:9, widened a little to fill the well exactly
                            readonly property int fits: Math.max(1, Math.floor((width + spacing) / (height * 16 / 9 + spacing)))
                            readonly property real thumbW: Math.floor((width - spacing * (fits - 1)) / fits)
                            Repeater {
                                model: capturesCard.latest.slice(0, capturesRow.fits)
                                CaptureThumb {
                                    required property var modelData
                                    width: capturesRow.thumbW
                                    height: capturesRow.height
                                    capture: modelData
                                }
                            }
                        }
                        Empty { anchors.fill: parent; visible: root._captures !== null && capturesCard.latest.length === 0; text: Translation.tr("No screenshots or clips yet") }
                    }
                }
            }
        }
    }
    Rectangle { // The fine edge light round the whole page (the header and the block as one object), and along its top
        anchors.fill: page
        radius: Appearance.rounding.normal
        color: "transparent"
        opacity: page.opacity
        border { width: 1; color: ColorUtils.transparentize("white", 0.84) }
        EdgeLight {
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 40; rightMargin: 40 }
            strength: 0.3
        }
    }

    // ─── Components ───────────────────────────────────────────
    // A well things sit in (as the game page's): darker than the block, a fine rim
    component Well: Rectangle {
        radius: Appearance.rounding.normal
        color: root._wellColor
        border { width: 1; color: ColorUtils.transparentize("white", 0.9) }
    }
    // A card's name on its art: the icon in a tinted square, the name, on a glass piece
    component CardTitle: Rectangle {
        property string iconName
        property string title
        x: 12; y: 12
        width: ctRow.implicitWidth + 16; height: 30
        radius: 11
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.4)
        border { width: 1; color: ColorUtils.transparentize("white", 0.9) }
        Row {
            id: ctRow
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.iconName; iconSize: 16; fill: 1; color: Appearance.colors.colPrimary }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.title
                font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
        }
    }
    // A card of the right column: its art as a tile on the left (the name and its number on it), a well beside it
    // joined to it (small inner corners) holding what's inside
    component SideCard: Item {
        id: side
        property string iconName
        property string title
        property string value
        property var game: null
        property string art: ""
        property Component under: null // Anything under the number on the tile (Storage's drive)
        default property alias content: sideWell.data
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 1 // The three share the column evenly
        ArtBanner {
            id: sideTile
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Math.min(170, side.width * 0.26)
            game: side.game
            art: side.art
            showCover: false
            shadeMid: 0.6; shadeEnd: 0.5
            topLeftRadius: Appearance.rounding.normal; bottomLeftRadius: Appearance.rounding.normal
            topRightRadius: Appearance.rounding.joined; bottomRightRadius: Appearance.rounding.joined
            Column {
                anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 10 }
                spacing: 2
                Row {
                    spacing: 7
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: side.iconName; iconSize: 16; fill: 1; color: Appearance.colors.colPrimary }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: side.title
                        font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: side.value
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({})
                    color: Appearance.colors.colOnLayer0
                }
                Item { width: 1; height: 4; visible: side.under !== null }
                Loader { width: parent.width; sourceComponent: side.under; visible: side.under !== null }
            }
        }
        Well {
            id: sideWell
            anchors { left: sideTile.right; leftMargin: 3; right: parent.right; top: parent.top; bottom: parent.bottom }
            topLeftRadius: Appearance.rounding.joined; bottomLeftRadius: Appearance.rounding.joined
            clip: true
        }
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
                    text: (thumb.capture?.time ?? 0) > 0 ? GameLauncherService.agoText(thumb.capture.time * 1000) + "  ·  "
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

    // Rows in a short, wide well: as many rows as fit, in columns about 240 px wide that fill it exactly, the rest
    // scrolling sideways (one long row each stretched the bars across the whole well, and showed two games)
    component GameGrid: GridView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        flow: GridView.FlowTopToBottom
        boundsBehavior: Flickable.StopAtBounds
        readonly property int rows: Math.max(1, Math.floor(height / 42))
        readonly property int columns: Math.max(1, Math.floor(width / 240))
        cellHeight: Math.floor(height / rows)
        cellWidth: Math.floor(width / columns)
        snapMode: GridView.SnapToRow // A column at a time
    }
    // A list: fills what it's given, scrolls inside it
    component StatList: StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        animateAppearance: false // Rows would pop in again whenever a list changes
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
        property int nameSize: Appearance.font.pixelSize.large
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
                font.pixelSize: headline.nameSize; font.weight: Font.DemiBold
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
        Rectangle { // Top right, level with the card's title
            id: headChip
            visible: headline.chip !== ""
            anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 13 }
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

    // A game: box art, name (+ subtitle or a bar), value on the right. Opens its details. In a card's well: straight
    // on it, a soft card when pointed at (as the game page's rows)
    component GameRow: GlassRow {
        id: row
        property var game
        property int rank: 0
        property string subtitle
        property string trailing
        property real fraction: -1 // < 0: no bar
        property color barColor: Appearance.colors.colPrimary
        Layout.fillWidth: true
        implicitHeight: 44
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
