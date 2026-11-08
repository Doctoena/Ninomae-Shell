import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Library statistics: a banner of the art of what you've played most lately (else of all time) with the hours you've played (and the
// installed size, the last two weeks and the library's ProtonDB on a card over it), then four cards that
// scroll inside the launcher's short, wide panel: Recently played as covers, Most played, Storage (what's
// downloading, every install, the drives' free room, what uninstalled games left) and Captures (the
// library's newest screenshot or clip large, the next four under it, opening their game's Captures).
// Every game opens its details.
Item {
    id: root
    signal backPressed()
    signal gameSelected(var game)
    signal capturesSelected(var game, string page) // A capture's game, on its Captures (page: shots or clips)
    property bool animationReady: false
    // Built ahead by the launcher (hidden): the scripts read again each time it's shown, so it's never stale, and
    // a result the same as last time changes nothing
    property bool shown: true
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
    property var _storageRows: [] // Downloads ({ appid, game }) first, then the installs ({ game, size })
    on_StatsChanged: {
        if (_recentRows !== (_stats?.recent ?? _recentRows)) _recentRows = _stats.recent;
        if (_mostRows !== (_stats?.mostPlayed ?? _mostRows)) _mostRows = _stats.mostPlayed;
        _syncStorage();
    }
    on_DownloadsChanged: _syncStorage()
    property var _storageFor: [null, null] // The two lists _storageRows was made from
    function _syncStorage() {
        const biggest = _stats?.biggest ?? [];
        if (_storageFor[0] === _downloads && _storageFor[1] === biggest) return;
        _storageFor = [_downloads, biggest];
        _storageRows = _downloads.concat(biggest);
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
                coverInset: 36 + 10 // The back button, then the cover
                // The most played in the last two weeks (else of all time). Not "top": an Item's own
                readonly property var topGame: root._stats?.lately ?? root._stats?.mostPlayed?.[0] ?? null
                readonly property bool lately: (root._stats?.lately ?? null) !== null
                game: topGame?.game ?? null
                coverIcon: "insights"
                shadeMid: 0.72; shadeEnd: 0.55 // Lighter on the right: the numbers there carry their own card
                opacity: root.animationReady ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                TapHandler { enabled: !!banner.game; onTapped: root.gameSelected(banner.game) }
                HoverHandler { cursorShape: banner.game ? Qt.PointingHandCursor : Qt.ArrowCursor }

                RippleButton { // Back, on the art: see-through as the numbers' card
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    implicitWidth: 36; implicitHeight: 36; padding: 0
                    buttonRadius: Appearance.rounding.container
                    colBackground: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.1)
                    colRipple: Appearance.colors.colLayer2Active
                    contentItem: Item { MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 18; color: Appearance.colors.colOnLayer0 } }
                    onClicked: root.backPressed()
                    StyledToolTip { text: Translation.tr("Back") }
                    Rectangle { // Hairline edge
                        anchors.fill: parent
                        radius: Appearance.rounding.container
                        color: "transparent"
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                    }
                }

                Column { // How much you've played, and what most of it was
                    anchors { left: banner.coverItem.right; leftMargin: 16; right: facts.left; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Row {
                        spacing: 8
                        StyledText {
                            anchors.baseline: playedWord.baseline
                            text: root._formatTime(root._stats?.totalMin ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.title; font.weight: Font.DemiBold
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            id: playedWord
                            text: Translation.tr("played")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.2)
                        }
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: [Translation.tr("%1 of %2 games played").arg(root._thousands(root._stats?.played ?? 0)).arg(root._thousands(root._stats?.total ?? 0)),
                               Translation.tr("avg %1").arg(root._formatTime(root._stats?.averageMin ?? 0)),
                               !banner.topGame ? ""
                                 : banner.lately ? Translation.tr("lately %1, %2").arg(banner.topGame.game.name).arg(root._formatTime(banner.topGame.recentMin))
                                 : Translation.tr("most %1").arg(banner.topGame.game.name)]
                            .filter(t => t !== "").join("  ·  ")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
                    }
                }

                Rectangle { // The other numbers, on a see-through card with a hairline edge (as Achievements' highlights)
                    id: facts
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: factRow.implicitWidth + 6
                    height: factRow.implicitHeight + 6
                    radius: Appearance.rounding.normal
                    color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                    Row {
                        id: factRow
                        anchors.centerIn: parent
                        BannerFact {
                            icon: "download_done"; label: Translation.tr("Installed")
                            value: Translation.tr("%1  ·  %2").arg(root._stats?.installed ?? 0).arg(root._formatBytes(root._stats?.diskTotal ?? 0))
                            tip: (root._stats?.backlog ?? 0) === 1 ? Translation.tr("1 of them never played")
                                : (root._stats?.backlog ?? 0) > 1 ? Translation.tr("%1 of them never played").arg(root._stats.backlog) : ""
                        }
                        BannerFact {
                            divider: true
                            icon: "history"; label: Translation.tr("Last 2 weeks")
                            value: (root._stats?.recentGames ?? 0) === 1 ? Translation.tr("%1  ·  1 game").arg(root._formatTime(root._stats.recentTotalMin))
                                : Translation.tr("%1  ·  %2 games").arg(root._formatTime(root._stats?.recentTotalMin ?? 0)).arg(root._stats?.recentGames ?? 0)
                        }
                        BannerFact { // The library's ProtonDB: one bar, the counts in its tooltip
                            divider: true
                            icon: "verified"; label: Translation.tr("ProtonDB")
                            value: (root._stats?.tierGames ?? 0) > 0 ? Translation.tr("%1 rated").arg(root._thousands(root._stats.tierGames)) : Translation.tr("None rated")
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
        }

        // ── Cards: each scrolls inside itself ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            visible: root._stats !== null

            Card { // The latest games, as their covers
                order: 1
                weight: 1.3
                iconName: "history"
                title: Translation.tr("Recently played")
                caption: Translation.tr("Last 2 weeks") // What the times under the covers count
                StatList {
                    id: recentList
                    visible: count > 0
                    orientation: ListView.Horizontal
                    spacing: 10
                    snapMode: ListView.SnapToItem // Scrolled a cover at a time: none left cut off
                    // As many whole covers as fit at about 2:3, widened a little to fill the card exactly
                    readonly property int fits: Math.max(1, Math.floor((width + spacing) / ((height - 40) * 2 / 3 + spacing)))
                    readonly property real posterWidth: Math.floor((width - spacing * (fits - 1)) / fits)
                    model: root._recentRows
                    delegate: PosterTile {
                        required property var modelData
                        width: recentList.posterWidth
                        height: ListView.view.height
                        game: modelData.game
                        // Under the name: when, and the time in the last two weeks (else the last session)
                        detail: root._ago(modelData.last) + (modelData.recentMin > 0 ? "  ·  " + root._formatTime(modelData.recentMin)
                            : modelData.sessionMin > 0 ? "  ·  " + root._formatTime(modelData.sessionMin) : "")
                    }
                }
                Empty { visible: recentList.count === 0; text: Translation.tr("Nothing played yet") }
            }

            Card {
                order: 2
                iconName: "emoji_events"
                title: Translation.tr("Most played")
                StatList {
                    id: mostList
                    visible: count > 0
                    model: root._mostRows
                    delegate: GameRow {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        game: modelData.game
                        rank: index + 1
                        trailing: root._formatTime(modelData.minutes)
                        fraction: modelData.minutes / root._stats.maxMinutes
                    }
                }
                Empty { visible: mostList.count === 0; text: Translation.tr("Nothing played yet") }
            }

            // What's downloading, then every install, biggest first; or (Review) what uninstalled games left behind
            Card {
                order: 3
                iconName: "hard_drive"
                title: root._showLeftovers ? Translation.tr("Left behind") : Translation.tr("Storage")
                caption: !root._showLeftovers && root._freeBytes >= 0 ? Translation.tr("%1 free").arg(root._formatBytes(root._freeBytes)) : ""
                StatList {
                    id: storageList
                    visible: !root._showLeftovers && count > 0
                    // Downloads ({ item, game }) first, then the installs ({ game, size })
                    model: root._showLeftovers ? [] : root._storageRows
                    delegate: GameRow {
                        required property var modelData
                        readonly property var item: modelData.appid ? root._downloadItem(modelData.appid) : null // Live
                        width: ListView.view.width
                        game: modelData.game
                        subtitle: item ? root._downloadText(item) : ""
                        trailing: item ? root._formatBytes(item.toDownload) : modelData.appid ? "" : root._formatBytes(modelData.size)
                        fraction: modelData.appid ? Math.max(0, item?.progress ?? 0) : modelData.size / root._stats.maxSize
                    }
                }
                Empty { visible: storageList.count === 0 && !root._showLeftovers; text: Translation.tr("No install sizes found") }
                RippleButton { // "Left by N uninstalled games · size  Review"
                    Layout.fillWidth: true
                    implicitHeight: 36
                    visible: !root._showLeftovers && root._leftovers.length > 0
                    buttonRadius: Appearance.rounding.container
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
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
                RowLayout {
                    Layout.fillWidth: true
                    visible: root._showLeftovers
                    spacing: 6
                    RippleButton {
                        implicitWidth: 30; implicitHeight: 30
                        buttonRadius: Appearance.rounding.segment
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root._showLeftovers = false
                        contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 16; color: Appearance.colors.colOnLayer2 }
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
                        required property var modelData
                        width: ListView.view.width
                        spacing: 4
                        GameRow {
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
                    CaptureThumb {
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: strip.top
                                  bottomMargin: capturesArea.stripHeight > 0 ? capturesArea.gap : 0 }
                        capture: capturesArea.latest[0] ?? ({})
                        large: true
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
                                width: (capturesArea.width - 3 * capturesArea.gap) / 4
                                height: strip.height
                                capture: modelData
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
        color: Appearance.colors.colLayer2
        opacity: root.animationReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260 + order * 50; easing.type: Easing.OutCubic } }
    }

    // One of the banner's numbers: a tinted squircle, a small label and the value (extra content under them)
    component BannerFact: Row {
        id: fact
        property string icon
        property string label
        property string value
        property string tip: ""
        property bool divider: false
        default property alias content: factCol.data
        height: 48
        Rectangle {
            visible: fact.divider
            width: 1; height: 22
            anchors.verticalCenter: parent.verticalCenter
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
        }
        Item {
            width: factInner.implicitWidth + 22
            height: parent.height
            Row {
                id: factInner
                anchors.centerIn: parent
                spacing: 9
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 9
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                    MaterialSymbol { anchors.centerIn: parent; text: fact.icon; iconSize: 16; fill: 1; color: Appearance.colors.colPrimary }
                }
                Column {
                    id: factCol
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    StyledText {
                        text: fact.label
                        font.pixelSize: 10; font.weight: Font.Medium
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: fact.value
                        font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
            HoverHandler { id: factHover }
            StyledToolTip { text: fact.tip; visible: fact.tip !== "" && factHover.hovered }
        }
    }

    // A recently played game: its cover, the name and a line under it. Opens its details
    component PosterTile: RippleButton { // Its width is the list's (a whole number of them fill it)
        id: poster
        property var game
        property string detail
        readonly property string art: GameLauncherService.localArt(game, "boxArt")
        padding: 0
        buttonRadius: Appearance.rounding.normal
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colRipple: "transparent"
        onClicked: if (poster.game) root.gameSelected(poster.game)
        contentItem: Item {
            ClippingRectangle {
                id: posterArt
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: parent.height - 40
                radius: Appearance.rounding.normal
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
        radius: large ? Appearance.rounding.normal : Appearance.rounding.small
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
        Rectangle { // Hover edge (the clip's own radius: its parent here is its content item)
            anchors.fill: parent
            radius: thumb.radius
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

    // A titled card holding one list
    component Card: Surface {
        id: card
        property string iconName
        property string title
        property string caption // Small, on the right of the title
        default property alias content: cardCol.data
        Layout.fillHeight: true
        ColumnLayout {
            id: cardCol
            anchors { fill: parent; margins: 8 }
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.leftMargin: 4
                spacing: 10
                QuickDialogIcon { implicitWidth: 28; implicitHeight: 28; radius: Appearance.rounding.segment; icon: card.iconName; active: true }
                StyledText {
                    text: card.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    visible: card.caption.length > 0
                    Layout.rightMargin: 6
                    text: card.caption
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // A game: box art, name (+ subtitle or a bar), value on the right. Opens its details
    component GameRow: RippleButton {
        id: row
        property var game
        property int rank: 0
        property string subtitle
        property string trailing
        property real fraction: -1 // < 0: no bar
        Layout.fillWidth: true
        implicitHeight: 46
        buttonRadius: Appearance.rounding.container
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
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
                implicitWidth: 28; implicitHeight: 38
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
                    color: "transparent"
                    visible: thumb.status === Image.Ready
                    Image {
                        id: thumb
                        anchors.fill: parent
                        source: row.game?.boxArt ? "file://" + row.game.boxArt : ""
                        fillMode: Image.PreserveAspectCrop
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
                        color: Appearance.colors.colPrimary
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
