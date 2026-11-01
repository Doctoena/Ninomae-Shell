pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick
/**
 * Game launcher service - detects games from various sources
 * Steam and Lutris
 */
Singleton {
    id: root
    property var games: []
    property bool loading: true
    property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/game-launcher`)
    property string boxArtDir: `${cacheDir}/box-art`
    // ── Public aliases for store data (preserves external API) ──
    readonly property alias accessData: _accessStore.value
    readonly property alias favorites: _favoritesStore.value
    readonly property alias customArt: _customArtStore.value
    readonly property alias completedGames: _completedStore.value
    readonly property alias sessionData: _sessionStore.value
    readonly property alias tagsData: _tagsStore.value
    readonly property alias particleOverrides: _particleOverrideStore.value
    readonly property alias customGames: _customGamesStore.value // Games added by hand (addCustomGame)
    // Revision counters — subscribe to these for reactive updates
    property real lastAccessTime: _accessStore.revision
    readonly property alias favoritesRevision: _favoritesStore.revision
    readonly property alias customArtRevision: _customArtStore.revision
    readonly property alias completedGamesRevision: _completedStore.revision
    readonly property alias sessionDataRevision: _sessionStore.revision
    readonly property alias tagsRevision: _tagsStore.revision
    readonly property alias particleOverridesRevision: _particleOverrideStore.revision
    // Optimization: Pre-computed Set of favorite IDs for O(1) lookup
    readonly property var favoritesSet: {
        const _ = root.favoritesRevision;
        return new Set(Object.keys(root.favorites));
    }
    property string sortOrder: Config.options?.gameLauncher?.sortOrder ?? "recency"
    property bool fallbackToIcons: Config.options?.gameLauncher?.fallbackToIcons ?? true
    property bool hideWithoutBoxArt: Config.options?.gameLauncher?.hideWithoutBoxArt ?? true
    property bool hidePartialBoxArt: Config.options?.gameLauncher?.hidePartialBoxArt ?? true
    // API keys live in the system keyring (KeyringStorage), not config.json, so they never end up in
    // the dotfiles repo. A key still in config.json (older setups) is used until it has been moved over
    readonly property string steamApiKey: KeyringStorage.get("gameLauncher", "steamApiKey") || (Config.options?.gameLauncher?.steamApiKey ?? "")
    readonly property string steamGridDbApiKey: KeyringStorage.get("gameLauncher", "steamGridDbApiKey") || (Config.options?.gameLauncher?.steamGridDbApiKey ?? "")
    // Immich's server URL too: it's the address of someone's home server
    readonly property string immichUrl: (KeyringStorage.get("gameLauncher", "immichUrl") || (Config.options?.gameLauncher?.immichUrl ?? "")).trim().replace(/\/+$/, "")
    readonly property string immichApiKey: KeyringStorage.get("gameLauncher", "immichApiKey")
    readonly property bool immichReady: (Config.options?.gameLauncher?.immichEnabled ?? false) && immichUrl.length > 0 && immichApiKey.length > 0
    // Screenshots to Immich (scripts/game-launcher/immich_upload.py), into the game's album. Here rather
    // than in the Screenshots panel so closing it (or the launcher) doesn't cut an upload short.
    // immichUploadState: "", "uploading", then "done" / "failed" for a moment; a notification says how it went
    property string immichUploadState: ""
    signal immichUploadFinished(string album) // The Screenshots panel shows the album: it looks again
    // What the Screenshots panel last found per game (gameId → { local, remote, albumId, fetched }). The panel
    // is made anew each time it opens: with this it opens already filled in, instead of its shots and
    // buttons popping in partway through its slide, and looks again behind that. For this session only
    property var screenshotsCache: ({})
    property var clipsCache: ({}) // The same for the Clips page: gameId → its clips list

    property string _immichAlbum: ""
    function uploadToImmich(files, album) {
        if (immichUploader.running || files.length === 0 || !immichReady) return;
        _immichAlbum = album;
        immichUploader.command = [Quickshell.shellPath("scripts/game-launcher/immich_upload.py"), immichUrl, album, ...files];
        immichUploadState = "uploading";
        immichUploader.running = true;
    }
    Timer { id: immichUploadStateTimer; interval: 2500; onTriggered: root.immichUploadState = "" }
    Process {
        id: immichUploader
        environment: ({ IMMICH_API_KEY: root.immichApiKey }) // Not an argument: any process can read those (ps)
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { uploaded: 0, duplicates: 0, failed: 1, error: text.trim() || "No answer" }; }
                root.immichUploadState = r.failed > 0 ? "failed" : "done";
                immichUploadStateTimer.restart();
                const parts = [];
                if (r.uploaded > 0) parts.push(Translation.tr("%1 uploaded").arg(r.uploaded));
                if (r.duplicates > 0) parts.push(Translation.tr("%1 already there").arg(r.duplicates));
                if (r.failed > 0) parts.push(Translation.tr("%1 failed").arg(r.failed));
                const body = [parts.join(" · "), r.album ? Translation.tr("In the album “%1”").arg(root._immichAlbum) : "", r.error ?? ""]
                    .filter(l => l !== "").join("\n");
                Quickshell.execDetached(["notify-send", "-a", "Immich", ...(r.failed > 0 ? ["-u", "critical"] : []),
                    r.failed > 0 ? Translation.tr("Upload to Immich failed") : Translation.tr("Backed up to Immich"), body]);
                root.immichUploadFinished(root._immichAlbum);
            }
        }
    }
    property var _keysMoving: null
    function moveApiKeysToKeyring() {
        if (!KeyringStorage.loaded || root._keysMoving || !Config.ready) return;
        const cfg = Config.options.gameLauncher;
        const moving = ["steamApiKey", "steamGridDbApiKey", "immichUrl"].filter(k => (cfg[k] ?? "").length > 0);
        if (moving.length === 0) return;
        root._keysMoving = moving;
        const data = Object.assign({}, KeyringStorage.keyringData);
        data.gameLauncher = Object.assign({}, data.gameLauncher ?? {});
        for (const k of moving) data.gameLauncher[k] = cfg[k];
        KeyringStorage.keyringData = data;
        KeyringStorage.saveKeyringData();
    }
    Connections {
        target: KeyringStorage
        function onLoadedChanged() { root.moveApiKeysToKeyring(); }
        function onSaved(ok) { // Only blank config.json once the keyring really has them
            if (!root._keysMoving) return;
            if (ok) for (const k of root._keysMoving) Config.options.gameLauncher[k] = "";
            else console.warn("[GameLauncher] Couldn't save the API keys to the keyring; they stay in config.json for now");
            root._keysMoving = null;
        }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.moveApiKeysToKeyring(); }
    }
    Connections { // Keys edited in the Settings app (its own process) are picked up next time the launcher opens
        target: GlobalStates
        function onGameLauncherOpenChanged() { if (GlobalStates.gameLauncherOpen) KeyringStorage.fetchKeyringData(); }
    }
    // Filtering state (consumed by UI)
    property string searchQuery: ""
    property string selectedLauncher: "all"
    property string selectedTag: ""
    property var filteredGames: []
    // Precomputed map of installed games by ID for O(1) lookups
    readonly property var _installedGamesMap: {
        const map = {};
        for (let i = 0; i < root.games.length; i++) {
            map[root.games[i].id] = root.games[i];
        }
        return map;
    }
    // Tags: computed in a single pass for both unique list and counts
    readonly property var _tagInfo: {
        const _ = root.tagsRevision;
        const counts = {};
        const data = root.tagsData;
        const inLibrary = root._installedGamesMap; // Every game in the library, installed or not
        const anyGames = root.games.length > 0; // Before the first scan: count them all
        if (data) {
            const ids = Object.keys(data);
            for (let i = 0; i < ids.length; i++) {
                if (anyGames && !inLibrary[ids[i]]) continue; // A game that's gone from the library
                const tags = data[ids[i]];
                if (Array.isArray(tags)) {
                    for (let j = 0; j < tags.length; j++)
                        counts[tags[j]] = (counts[tags[j]] || 0) + 1;
                }
            }
        }
        return { tags: Object.keys(counts).sort(root._tagOrder), counts: counts };
    }
    readonly property var allTags: _tagInfo.tags
    readonly property var tagCounts: _tagInfo.counts
    // Count of games that have box art (the actual displayable pool)
    readonly property int displayableCount: {
        if (!root.hideWithoutBoxArt) return root.games.length;
        let count = 0;
        for (let i = 0; i < root.games.length; i++) {
            if (root.games[i].boxArt) count++;
        }
        return count;
    }
    // Deep-clone helper for immutable store updates
    function _clone(obj) { return JSON.parse(JSON.stringify(obj)); }
    Component.onCompleted: {
        _gamesCacheStore.load();
    }
    // ── Persistent data stores ──────────────────────────────────
    JsonStore {
        id: _accessStore
        filePath: `${root.cacheDir}/access_data.json`
    }
    JsonStore {
        id: _favoritesStore
        filePath: `${root.cacheDir}/favorites.json`
    }
    JsonStore {
        id: _customArtStore
        filePath: `${root.cacheDir}/custom_art.json`
        onLoaded: root._rebaseCachePaths(_customArtStore)
    }
    JsonStore {
        id: _completedStore
        filePath: `${root.cacheDir}/completed_games.json`
        onLoaded: root._rebaseCachePaths(_completedStore)
    }
    // These stores keep absolute paths to art in the cache. When the cache folder moves (the Quickshell
    // build's name decides it: ~/.cache/noctalia-qs became ~/.cache/quickshell), point them at this one
    readonly property var _foreignCachePath: /^.*\/\.cache\/[^\/]+\/game-launcher\//
    function _rebaseCachePaths(store) {
        let changed = false;
        const rebase = v => {
            if (typeof v === "string") {
                if (!v.startsWith(root.cacheDir + "/") && root._foreignCachePath.test(v)) {
                    changed = true;
                    return v.replace(root._foreignCachePath, root.cacheDir + "/");
                }
                return v;
            }
            if (Array.isArray(v)) return v.map(rebase);
            if (v && typeof v === "object") {
                const out = {};
                for (const k in v) out[k] = rebase(v[k]);
                return out;
            }
            return v;
        };
        const fixed = rebase(store.value);
        if (changed) Qt.callLater(() => store.commit(fixed)); // After the load finishes, not inside it
    }
    JsonStore {
        id: _sessionStore
        filePath: `${root.cacheDir}/session_data.json`
        onLoaded: root._resumeSessions()
    }
    JsonStore {
        id: _tagsStore
        filePath: `${root.cacheDir}/tags_data.json`
    }
    JsonStore {
        id: _particleOverrideStore
        filePath: `${root.cacheDir}/particle_overrides.json`
    }
    JsonStore {
        id: _seenBuildsStore
        filePath: `${root.cacheDir}/seen_builds.json`
        property bool loadedOnce: false
        onLoaded: { loadedOnce = true; root._noteNewBuilds(); }
    }
    JsonStore { // Read by detect_games.sh too, which puts them in the library
        id: _customGamesStore
        filePath: `${root.cacheDir}/custom_games.json`
        defaultValue: []
    }
    JsonStore {
        id: _newsSeenStore
        filePath: `${root.cacheDir}/news_seen.json`
    }
    JsonStore {
        id: _metadataStore
        filePath: `${root.cacheDir}/metadata_cache.json`
    }
    readonly property alias metadataCache: _metadataStore.value
    readonly property alias metadataCacheRevision: _metadataStore.revision
    // ── SteamGridDB art browser state ──────────────────────────
    property var sgdbResults: []
    property bool sgdbLoading: false
    property string sgdbArtType: "grid" // grid, hero, logo
    property int _sgdbGeneration: 0
    property string screenshotsPage: "shots" // The Screenshots sheet's last page ("shots"/"clips"), for the session
    function fetchSteamGridDbArt(game, artType) {
        if (!game || root.steamGridDbApiKey.length === 0) return;
        // Bump generation to invalidate any in-flight requests
        root._sgdbGeneration++;
        const gen = root._sgdbGeneration;
        root.sgdbArtType = artType || "grid";
        root.sgdbResults = [];
        root.sgdbLoading = true;
        root._sgdbPendingGame = game;
        // Kill any in-flight processes so they don't clobber us
        if (_sgdbSearchProc.running) _sgdbSearchProc.running = false;
        if (_sgdbFetchProc.running) _sgdbFetchProc.running = false;
        _sgdbSearchProc._generation = gen;
        _sgdbFetchProc._generation = gen;
        const appid = game.id.startsWith("steam_") ? game.id.substring(6) : "";
        if (appid.length > 0) {
            // Steam game: query directly by appid
            _sgdbFetchByType(appid, "steam");
        } else {
            // Non-Steam: search by name first to get SGDB game ID
            const term = encodeURIComponent(game.name || "");
            if (term.length === 0) { root.sgdbLoading = false; return; }
            _sgdbSearchProc.command = ["curl", "-sL", "--max-time", "10",
                "--variable", "%SGDB_KEY", "--expand-header", "Authorization: Bearer {{SGDB_KEY}}",
                "https://www.steamgriddb.com/api/v2/search/autocomplete/" + term];
            _sgdbSearchProc._started++;
            _sgdbSearchProc.running = true;
        }
    }
    property var _sgdbPendingGame: null
    function _sgdbFetchByType(gameId, idType) {
        const endpoint = root.sgdbArtType === "hero" ? "heroes" : root.sgdbArtType === "logo" ? "logos" : "grids";
        const dims = root.sgdbArtType === "grid" ? "&dimensions=600x900" : "";
        const prefix = idType === "steam" ? "steam/" : "game/";
        if (_sgdbFetchProc.running) _sgdbFetchProc.running = false;
        _sgdbFetchProc._generation = root._sgdbGeneration;
        _sgdbFetchProc.command = ["curl", "-sL", "--max-time", "10",
            "--variable", "%SGDB_KEY", "--expand-header", "Authorization: Bearer {{SGDB_KEY}}",
            "https://www.steamgriddb.com/api/v2/" + endpoint + "/" + prefix + gameId + "?limit=24" + dims];
        _sgdbFetchProc._started++;
        _sgdbFetchProc.running = true;
    }
    Process {
        id: _sgdbSearchProc
        running: false
        environment: ({ SGDB_KEY: root.steamGridDbApiKey }) // curl reads the key from here: not in its arguments, which ps shows
        property int _generation: 0
        // Every start ends in one finish, in order. One that finishes while a later one has started is a
        // request cut off by a newer one (switching tabs): its empty output isn't an error
        property int _started: 0
        property int _finished: 0
        stdout: StdioCollector {
            onStreamFinished: {
                _sgdbSearchProc._finished++;
                if (_sgdbSearchProc._finished < _sgdbSearchProc._started) return;
                if (_sgdbSearchProc._generation !== root._sgdbGeneration) return;
                try {
                    const resp = JSON.parse(text);
                    if (resp.success && Array.isArray(resp.data) && resp.data.length > 0) {
                        root._sgdbFetchByType(resp.data[0].id, "game");
                        return;
                    }
                } catch(e) { console.error("SGDB search error:", e); }
                root.sgdbLoading = false;
                root.sgdbResults = [];
            }
        }
    }
    Process {
        id: _sgdbFetchProc
        running: false
        environment: ({ SGDB_KEY: root.steamGridDbApiKey }) // curl reads the key from here: not in its arguments, which ps shows
        property int _generation: 0
        // Every start ends in one finish, in order. One that finishes while a later one has started is a
        // request cut off by a newer one (switching tabs): its empty output isn't an error
        property int _started: 0
        property int _finished: 0
        stdout: StdioCollector {
            onStreamFinished: {
                _sgdbFetchProc._finished++;
                if (_sgdbFetchProc._finished < _sgdbFetchProc._started) return;
                if (_sgdbFetchProc._generation !== root._sgdbGeneration) return;
                root.sgdbLoading = false;
                try {
                    const resp = JSON.parse(text);
                    if (resp.success && Array.isArray(resp.data)) {
                        root.sgdbResults = resp.data.map(item => ({
                            id: item.id,
                            url: item.url,
                            thumb: item.thumb,
                            width: item.width,
                            height: item.height,
                            author: item.author?.name || "",
                            style: item.style || ""
                        }));
                    }
                } catch(e) { console.error("SteamGridDB parse error:", e); }
            }
        }
    }
    function applySteamGridDbArt(game, artUrl, artType) {
        if (!game || !artUrl) return;
        const suffix = artType === "hero" ? "_sgdb_hero" : artType === "logo" ? "_sgdb_logo" : "_sgdb_grid";
        const ext = artUrl.includes(".png") ? ".png" : artUrl.includes(".webp") ? ".webp" : ".jpg";
        const safeId = game.id.replace(/[^a-zA-Z0-9_-]/g, "_");
        const destName = safeId + suffix + "_" + Date.now() + ext;
        const destPath = root.cacheDir + "/custom-art/" + destName;
        const oldPrefix = safeId + suffix + "_";
        _sgdbDownloadProc._gameId = game.id;
        _sgdbDownloadProc._artType = artType;
        _sgdbDownloadProc._destPath = destPath;
        // Values as arguments, not script text. The old art's glob is outside the quotes so it
        // expands (inside them it never matched, and replaced art piled up)
        _sgdbDownloadProc.command = ["sh", "-c",
            'mkdir -p -- "$1" && rm -f -- "$1/$2"* && curl -sL --max-time 30 -o "$4" -- "$3"',
            "sgdb-download", root.cacheDir + "/custom-art", oldPrefix, artUrl, destPath];
        _sgdbDownloadProc.running = true;
    }
    Process {
        id: _sgdbDownloadProc
        running: false
        property string _gameId: ""
        property string _artType: ""
        property string _destPath: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && _destPath.length > 0 && _gameId.length > 0) {
                if (_artType === "hero")
                    root.setCustomHeroArt(_gameId, _destPath);
                else if (_artType === "logo")
                    root.setCustomLogo(_gameId, _destPath);
                else {
                    // Grid = box art (cover image in the grid)
                    root.setCustomBoxArt(_gameId, _destPath);
                }
            }
            _destPath = ""; _gameId = ""; _artType = "";
        }
    }
    // ── Steam Store metadata fetching ──────────────────────────
    function fetchMetadata(game) {
        if (!game?.id?.startsWith("steam_")) return;
        // Cached for 7 days (a game with no store page too, so it isn't asked again on every visit)
        const cached = root.metadataCache[game.id];
        if (cached && cached._fetchedAt && (Date.now() - cached._fetchedAt) < 604800000) return;
        root._queueMeta(game, "steam");
    }

    // ── Store info fetches (Steam store, Lutris), one at a time ──
    // Each job carries its game, so an answer is always stored under the game that asked (one shared
    // "pending game" slot let a second page's request take over the first's). An empty or broken answer
    // (timeout, rate limit) is tried again 30 s later, twice at most
    property var _metaQueue: []    // [{ game, kind: "steam" | "lutrisCache" | "lutris" }]
    property var _metaJob: null    // The one running
    property var _metaRetries: []  // Jobs waiting for metaRetryTimer
    property var _metaTries: ({})  // game id → retries used
    function _queueMeta(game, kind, first) {
        const busy = j => j.game.id === game.id;
        if ((root._metaJob && busy(root._metaJob)) || root._metaQueue.some(busy) || root._metaRetries.some(busy)) return;
        const job = { game: game, kind: kind };
        root._metaQueue = first ? [job, ...root._metaQueue] : [...root._metaQueue, job];
        root._pumpMeta();
    }
    function _pumpMeta() {
        if (root._metaJob || root._metaQueue.length === 0) return;
        const job = root._metaQueue[0];
        root._metaQueue = root._metaQueue.slice(1);
        root._metaJob = job;
        const id = job.game.id;
        _metaProc.command = job.kind === "steam" ? ["curl", "-sL", "--max-time", "10", "https://store.steampowered.com/api/appdetails?appids=" + id.substring(6)]
            : job.kind === "lutrisCache" ? ["cat", root.boxArtDir + "/" + id + "_api.json"] // Pre-fetched by the library scan
            : ["curl", "-sL", "--max-time", "10", "https://lutris.net/api/games/" + id.substring(7)];
        _metaProc.running = true;
    }
    function _retryMeta(job) {
        const used = root._metaTries[job.game.id] ?? 0;
        if (used >= 2) return;
        root._metaTries = Object.assign({}, root._metaTries, { [job.game.id]: used + 1 });
        root._metaRetries = [...root._metaRetries, job];
        metaRetryTimer.start();
    }
    Timer {
        id: metaRetryTimer
        interval: 30000
        onTriggered: {
            const jobs = root._metaRetries;
            root._metaRetries = [];
            for (const j of jobs) root._queueMeta(j.game, j.kind);
        }
    }
    Process {
        id: _metaProc
        stdout: StdioCollector {
            onStreamFinished: {
                const job = root._metaJob;
                root._metaJob = null;
                if (job) root._metaResult(job, text.trim());
                Qt.callLater(root._pumpMeta);
            }
        }
    }
    // Steam's text comes with HTML character codes ("Gat &amp; Kinzie"); shown as plain text they'd read
    // literally. Decoded as it's saved, and as it's shown (for what was saved before)
    function decodeEntities(t) {
        if (!t || t.indexOf("&") < 0) return t ?? "";
        const named = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ", reg: "®", trade: "™", copy: "©" };
        return t.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (m, e) =>
            e[0] !== "#" ? (named[e] ?? m) : String.fromCodePoint(parseInt(e[1] === "x" ? e.slice(2) : e.slice(1), e[1] === "x" ? 16 : 10)));
    }
    // A usable answer: the game gets a fresh retry budget for its next fetch (a week on)
    function _metaAnswered(id) {
        if (root._metaTries[id] === undefined) return;
        const tries = Object.assign({}, root._metaTries);
        delete tries[id];
        root._metaTries = tries;
    }
    function _metaResult(job, text) {
        if (job.kind === "lutrisCache") { // Not on disk: ask Lutris, before anything queued after it
            if (text.length > 0) root._parseLutrisApiResponse(job.game, text);
            else root._queueMeta(job.game, "lutris", true);
            return;
        }
        if (job.kind === "lutris") {
            if (text.length > 0) { root._metaAnswered(job.game.id); root._parseLutrisApiResponse(job.game, text); }
            else root._retryMeta(job);
            return;
        }
        let resp = null;
        try { resp = text.length > 0 ? JSON.parse(text) : null; } catch (e) {}
        const appData = resp?.[job.game.id.substring(6)];
        if (!appData) { root._retryMeta(job); return; } // Nothing usable back (empty, an error page): try again later
        root._metaAnswered(job.game.id);
        const d = appData.success ? appData.data : null;
        const cache = root._clone(root.metadataCache);
        cache[job.game.id] = d ? {
            description: root.decodeEntities(d.short_description || ""),
            developers: d.developers || [],
            publishers: d.publishers || [],
            genres: (d.genres || []).map(g => g.description),
            metacritic: d.metacritic ? d.metacritic.score : null,
            releaseDate: d.release_date?.date || "",
            _fetchedAt: Date.now()
        } : { unavailable: true, _fetchedAt: Date.now() }; // No store page (delisted, private)
        _metadataStore.commit(cache);
    }
    // First game whose name matches (exactly, then containing it), case-insensitive. For the IPC calls
    function findGameByName(query) {
        const q = (query ?? "").toLowerCase();
        if (q === "") return null;
        return root.games.find(g => g.name.toLowerCase() === q) ?? root.games.find(g => g.name.toLowerCase().includes(q)) ?? null;
    }
    // ── Per-game data for the details page's sheets (achievements, news) ──
    // Each request runs its own short-lived process, and a result only lands if its game is still
    // the one asked for last (switching games quickly can't mix them up or cut one off half-read)
    function _query(command, gameId, onDone) {
        const proc = _queryComp.createObject(root, { command: command, gameId: gameId });
        proc.done.connect(text => {
            onDone(text, proc.gameId);
            proc.destroy();
        });
        proc.running = true;
    }
    Component {
        id: _queryComp
        Process {
            id: queryProc
            property string gameId
            signal done(string text)
            stdout: StdioCollector { onStreamFinished: queryProc.done(text) }
        }
    }
    function _helper(name) {
        return Quickshell.shellPath("scripts/game-launcher/" + name);
    }

    // Achievements (Steam): { total, unlocked, achievements: [...] }, already in display order with
    // each one's share of players (steam_achievements.py). Same game again: kept while it re-reads
    property var achievements: null
    property string achievementsFor: ""
    property bool achievementsLoading: false
    property string _achievementsText: "" // The last JSON, to skip rebuilding the list when nothing changed
    function loadAchievements(game) {
        if (!game?.id?.startsWith("steam_")) return;
        if (root.achievementsFor !== game.id) {
            root.achievementsFor = game.id;
            root.achievements = null;
        }
        root.achievementsLoading = root.achievements === null;
        _query(["python3", "-I", _helper("steam_achievements.py"), game.id.substring(6), root.cacheDir], game.id, (text, gameId) => {
            if (gameId !== root.achievementsFor) return;
            root.achievementsLoading = false;
            if (text === root._achievementsText && root.achievements !== null) return;
            root._achievementsText = text;
            try { root.achievements = JSON.parse(text); }
            catch (e) { root.achievements = { total: 0, unlocked: 0, achievements: [] }; }
        });
    }

    // News (Steam): the developer's announcements, newest first (steam_news.py, cached an hour).
    // Same game again: kept while it re-reads, and the list isn't rebuilt when nothing changed
    property var news: []
    property string newsFor: ""
    property bool newsLoading: false
    property string newsError: ""
    property string _newsText: ""
    // Unread news: per game, the date (Unix seconds) of the newest post seen in its News sheet.
    // A game never opened there counts the last week's posts as new
    readonly property alias newsSeen: _newsSeenStore.value
    function newsSeenFor(gameId) {
        return root.newsSeen[gameId] ?? Math.floor(Date.now() / 1000) - 7 * 86400;
    }
    function markNewsSeen(gameId, newestDate) {
        if (!gameId || newestDate <= (root.newsSeen[gameId] ?? 0)) return;
        _newsSeenStore.commit(Object.assign({}, root.newsSeen, { [gameId]: newestDate }));
    }
    // How many of the loaded game's posts are newer than what was last seen
    readonly property int unreadNews: {
        if (root.news.length === 0) return 0;
        const seen = root.newsSeenFor(root.newsFor);
        return root.news.filter(p => p.date > seen).length;
    }
    function loadNews(game) {
        if (!game?.id?.startsWith("steam_")) return;
        if (root.newsFor !== game.id) {
            root.newsFor = game.id;
            root.news = [];
            root.newsError = "";
            root._newsText = "";
        }
        root.newsLoading = root.news.length === 0;
        _query(["python3", "-I", _helper("steam_news.py"), game.id.substring(6), root.cacheDir], game.id, (text, gameId) => {
            if (gameId !== root.newsFor) return;
            root.newsLoading = false;
            if (text === root._newsText) return;
            root._newsText = text;
            try {
                const result = JSON.parse(text);
                root.news = result.items ?? [];
                root.newsError = result.error ?? "";
            } catch (e) {
                root.news = [];
                root.newsError = String(e);
            }
        });
    }
    function getMetadata(gameId) {
        return root.metadataCache[gameId] || null;
    }
    // ── Lutris metadata fetching (from cached API JSON or live fetch) ───
    function fetchLutrisMetadata(game) {
        if (!game?.id?.startsWith("lutris_")) return;
        // Cached for 7 days. _v 2: steamId "None" fixed, fuller description; older entries are parsed again
        const cached = root.metadataCache[game.id];
        if (cached && cached._v === 2 && cached._fetchedAt && (Date.now() - cached._fetchedAt) < 604800000) return;
        root._queueMeta(game, "lutrisCache");
    }
    function _parseLutrisApiResponse(game, jsonText) {
        try {
            const d = JSON.parse(jsonText);
            if (!d || !d.slug) return;
            const meta = {
                // First paragraph (the API's text runs on with credits and links after it)
                description: (d.description || "").replace(/\r\n/g, "\n").split(/\n\s*\n/)[0].replace(/\s+/g, " ").trim().substring(0, 600),
                developers: [],
                publishers: [],
                genres: (d.genres || []).map(g => g.name).filter(n => n),
                metacritic: null,
                releaseDate: d.year ? String(d.year) : "",
                platforms: (d.platforms || []).map(p => p.name).filter(n => n),
                steamId: /^\d+$/.test(String(d.steamid ?? "")) ? String(d.steamid) : null, // The API says "None"
                userCount: d.user_count || 0,
                lutrisSlug: d.slug || "",
                _v: 2,
                _fetchedAt: Date.now()
            };
            const cache = root._clone(root.metadataCache);
            cache[game.id] = meta;
            _metadataStore.commit(cache);
        } catch(e) { console.error("Lutris metadata parse error:", e); }
    }
    // Games cache is special: triggers detection after load, stores arrays
    JsonStore {
        id: _gamesCacheStore
        filePath: `${root.cacheDir}/games_cache.json`
        defaultValue: []
        autoLoad: false
        onRevisionChanged: {
            if (data.length > 0) {
                let cached = data;
                if (root.hideWithoutBoxArt)
                    cached = cached.filter(game => game.boxArt);
                root.games = sortGames(cached);
                root.loading = false;
                refilter();
            }
            // Always refresh in background after loading cache
            detectGamesProc.running = true;
        }
    }
    // ── File picker (zenity) ──
    // Lives in the Singleton so it survives the launcher window closing while the dialog is up.
    // zenity runs as a child and its output is read when it exits: no polling and no time limit
    // (it used to poll a temp file every 300 ms and drop a choice that took over two minutes)
    property bool filePickerActive: false
    property string _pickerMode: ""
    property string _pickerGameId: ""
    function _resetPickerState() {
        root.filePickerActive = false;
        root._pickerMode = "";
        root._pickerGameId = "";
    }
    function launchFilePicker(gameId, mode) {
        if (!gameId || gameId.length === 0 || pickerProc.running) return;
        root._pickerMode = mode;
        root._pickerGameId = gameId;
        root.filePickerActive = true;
        const title = mode === "hero" ? "Choose Background Image" : mode === "boxart" ? "Choose Cover Image" : "Choose Logo Image";
        pickerProc.command = ["zenity", "--file-selection", `--title=${title}`,
            "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp"];
        pickerProc.running = true;
    }
    function cancelFilePicker() {
        pickerProc.running = false; // Closes the dialog
        root._resetPickerState();
    }
    Process {
        id: pickerProc
        stdout: StdioCollector { id: pickerOutput }
        onExited: (exitCode, exitStatus) => {
            const path = exitCode === 0 ? pickerOutput.text.trim() : "";
            if (path.length === 0 || root._pickerGameId.length === 0) {
                root._resetPickerState();
                return;
            }
            const ext = path.substring(path.lastIndexOf(".")).replace(/[^a-zA-Z0-9.]/g, "");
            // Own name per kind: covers used to share "_custom_logo" and overwrite a custom logo
            const suffix = root._pickerMode === "hero" ? "_custom_hero" : root._pickerMode === "boxart" ? "_custom_boxart" : "_custom_logo";
            // A new name each time (like the SteamGridDB downloads), so the cached cover in the grid never shows
            // the old picture; the previous file of this kind is removed (the unstamped name included)
            const prefix = root._pickerGameId.replace(/[^a-zA-Z0-9_-]/g, "_") + suffix;
            const destName = prefix + "_" + Date.now() + ext;
            const destPath = root.cacheDir + "/custom-art/" + destName;
            pickerCopyProc._destForService = destPath;
            pickerCopyProc._mode = root._pickerMode;
            pickerCopyProc._gameId = root._pickerGameId;
            // The picked path can contain anything (quotes included): pass it as an argument. Copied aside
            // before the old file goes, in case the picked file is that old file
            pickerCopyProc.command = ["sh", "-c",
                'mkdir -p -- "$1" && cp -- "$2" "$1/.incoming" && rm -f -- "$1/$4"* && mv -- "$1/.incoming" "$3"',
                "art-copy", root.cacheDir + "/custom-art", path, destPath, prefix];
            pickerCopyProc.running = true;
        }
    }
    Process {
        id: pickerCopyProc
        running: false
        property string _destForService: ""
        property string _mode: ""
        property string _gameId: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && _destForService.length > 0 && _gameId.length > 0) {
                if (_mode === "hero")
                    root.setCustomHeroArt(_gameId, _destForService);
                else if (_mode === "logo")
                    root.setCustomLogo(_gameId, _destForService);
                else if (_mode === "boxart")
                    root.setCustomBoxArt(_gameId, _destForService);
            }
            _destForService = "";
            _mode = "";
            _gameId = "";
            root._resetPickerState();
        }
    }
    function toggleFavorite(gameId) {
        const fav = Object.assign({}, root.favorites);
        if (fav[gameId]) {
            delete fav[gameId];
        } else {
            fav[gameId] = { addedAt: Date.now() };
        }
        _favoritesStore.commit(fav);
        // Only resort when in favorites sort mode (avoids full grid rebuild)
        if (root.sortOrder === "favorites") {
            resortGames();
        }
    }
    function isFavorite(gameId) {
        return root.favoritesSet.has(gameId);
    }
    function toggleCompleted(game) {
        if (!game || !game.id) return;
        const comp = Object.assign({}, root.completedGames);
        if (comp[game.id]) {
            delete comp[game.id];
        } else {
            // Store snapshot of game data so it persists when uninstalled
            comp[game.id] = {
                id: game.id,
                name: game.name || "",
                source: game.source || "",
                boxArt: game.boxArt || "",
                icon: game.icon || "",
                heroArt: game.heroArt || "",
                gameDir: game.gameDir || "",
                protondbTier: game.protondbTier || "",
                completedAt: Date.now()
            };
        }
        _completedStore.commit(comp);
        if (root.sortOrder === "completed") {
            resortGames();
        }
    }
    function isCompleted(gameId) {
        return !!root.completedGames[gameId];
    }
    // Install state from Steam's StateFlags (appmanifest), read from the live game list (a details page
    // holds a snapshot). 4 = fully installed, 2 = update required, 2048 = uninstalling; the rest of
    // the "busy" bits mean a download, update or validation is running
    readonly property int _busyFlags: 256 | 1024 | 131072 | 262144 | 524288 | 1048576 | 2097152 | 4194304
    function installState(gameOrId) {
        const id = typeof gameOrId === "string" ? gameOrId : gameOrId?.id;
        const g = root._installedGamesMap[id];
        const flags = g?.stateFlags ?? 0;
        if (root.steamPending[id]) return root.steamPending[id]; // Ours, before Steam's manifest says so
        if (!g || flags === 0) return "notInstalled";
        if (!g.id.startsWith("steam_")) return "installed"; // Lutris: present means installed
        if (flags & 2048) return "uninstalling";
        if (!(flags & 4)) return "installing";
        if (flags & 512) return "updatePaused"; // Steam's "UpdatePaused" bit
        if (flags & root._busyFlags) return "updating";
        if (flags & 2) return "updateRequired";
        return "installed";
    }
    function isGameInstalled(gameId) {
        const state = root.installState(gameId);
        return state === "installed" || state === "updateRequired" || state === "updatePaused" || state === "updating";
    }
    // The steamapps folder of the library a Steam game is in (from <library>/steamapps/common/<dir>), or ""
    function _steamappsDir(game) {
        if (!game?.id?.startsWith("steam_")) return "";
        return game.gameDir?.match(/^(.*\/steamapps)\/common\/[^/]+\/?$/)?.[1] ?? "";
    }
    // Steam's files for a game (read from the live game list), or null if it isn't a Steam game on disk:
    //   manifest  appmanifest_<id>.acf, with the download totals
    //   downloads where a running download is written: downloading/<id> for the game,
    //             workshop/downloads/<id> for its mods. The manifest's byte counts only get rewritten
    //             on state changes, so live progress is what's on disk here
    //   mods      workshop/content/<id>, the installed Workshop mods
    function steamPaths(game) {
        const g = root._installedGamesMap[game?.id] ?? game;
        const dir = root._steamappsDir(g);
        if (!dir) return null;
        const appid = g.id.substring(6);
        return {
            manifest: `${dir}/appmanifest_${appid}.acf`,
            downloads: [`${dir}/downloading/${appid}`, `${dir}/workshop/downloads/${appid}`],
            mods: `${dir}/workshop/content/${appid}`
        };
    }
    // Games whose Workshop mods are downloading (id → true), from Steam's workshop/appworkshop_<id>.acf
    // ("NeedsDownload" is 1 until the mods are in). One scan of every library, while the launcher is open
    property var workshopDownloading: ({})
    readonly property var _steamappsDirs: {
        const dirs = new Set();
        for (let i = 0; i < root.games.length; i++) {
            const dir = root._steamappsDir(root.games[i]);
            if (dir) dirs.add(dir);
        }
        return [...dirs];
    }
    Process {
        id: _workshopScanProc
        command: ["sh", "-c", "for d; do grep -l '\"NeedsDownload\"[[:space:]]*\"1\"' \"$d\"/workshop/appworkshop_*.acf; done 2>/dev/null; true",
            "sh", ...root._steamappsDirs]
        stdout: StdioCollector {
            onStreamFinished: {
                const ids = (text.match(/appworkshop_\d+\.acf/g) ?? []).map(f => "steam_" + f.match(/\d+/)[0]).sort();
                if (ids.join() === Object.keys(root.workshopDownloading).sort().join()) return; // Unchanged: no rebinding
                const map = {};
                for (const id of ids) map[id] = true;
                root.workshopDownloading = map;
            }
        }
    }
    Timer {
        interval: 3000
        running: GlobalStates.gameLauncherOpen && root._steamappsDirs.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!_workshopScanProc.running) _workshopScanProc.running = true
    }
    function openDownloads() { Quickshell.execDetached(["xdg-open", "steam://open/downloads"]); }
    // Steam installs and uninstalls run here, without Steam's dialogs (launch_options.py install/uninstall).
    // Steam only reads its manifests on start and rewrites them on exit, so both close Steam if it's open
    // and start it again in the tray. While one runs, the game's id → "installing"/"uninstalling" is in
    // steamPending, which installState reports (the manifest says so too once Steam is back)
    readonly property string _steamHelper: Quickshell.shellPath("scripts/game-launcher/launch_options.py")
    property var steamPending: ({})
    function _setPending(id, state) {
        const p = Object.assign({}, root.steamPending);
        if (state) p[id] = state; else delete p[id];
        root.steamPending = p;
    }
    // Steam's library folders with their free space, for the launcher's own "install where?" choice
    property var steamLibraries: []
    Process {
        id: _librariesProc
        command: ["python3", "-I", root._steamHelper, "libraries"]
        stdout: StdioCollector { onStreamFinished: { try { root.steamLibraries = JSON.parse(text); } catch (e) {} } }
    }
    Connections {
        target: GlobalStates
        function onGameLauncherOpenChanged() { if (GlobalStates.gameLauncherOpen) _librariesProc.running = true; }
    }
    Component {
        id: _steamActionComp
        Process {
            property var game
            property string action // "install" or "uninstall"
            stdout: StdioCollector { id: _actionOut }
            onExited: (exitCode, exitStatus) => {
                let r = null; try { r = JSON.parse(_actionOut.text); } catch (e) {}
                const name = game.name || "Game";
                const why = {
                    "game-running": "It's still running. Close it and try again.",
                    "steam-wont-close": "Steam didn't close, so nothing was changed. Try again.",
                    "unusual-location": "Its folder isn't where Steam normally keeps games, so it was left alone.",
                    "not-installed": "Steam doesn't list it as installed.",
                    "already-installed": "Steam already has it installed or downloading.",
                    "no-app-info": "Steam hasn't loaded this game's details yet. Open its page in Steam once, then try again.",
                    "unknown-library": "That Steam library folder is gone."
                }[r?.error] ?? "Something went wrong; see the shell log.";
                if (!r?.ok) console.warn("[GameLauncher]", action, game.id, _actionOut.text.trim());
                const cmd = r?.ok
                    ? ["notify-send", "-a", "Game Launcher", "Game Launcher", (action === "install" ? "Downloading " : "Uninstalled ") + name]
                    : ["notify-send", "-a", "Game Launcher", "-u", "critical", "Couldn't " + action + " " + name, why];
                const icon = game.boxArt || game.icon || "";
                if (icon.startsWith("/")) cmd.push("-i", icon);
                Quickshell.execDetached(cmd);
                root._setPending(game.id, "");
                root.refreshGames(); // The watcher would too; this updates the page straight away
                destroy();
            }
        }
    }
    function _runSteamAction(game, action, extraArgs) {
        if (root.steamPending[game.id]) return;
        root._setPending(game.id, action === "install" ? "installing" : "uninstalling");
        _steamActionComp.createObject(root, {
            game: game, action: action,
            command: ["python3", "-I", root._steamHelper, action, game.id.substring(6), "--restart", ...(extraArgs ?? [])],
            running: true
        });
    }
    // library: one of steamLibraries' paths (the launcher asks when there's more than one); default the first
    function installGame(game, library) {
        if (!game || !game.id) return;
        const src = (game.source || "").toLowerCase();
        if (src === "steam") {
            root._runSteamAction(game, "install", library ? ["--library", library] : []);
        } else if (src === "lutris") {
            const slug = game.id.substring(7); // strip "lutris_"
            Quickshell.execDetached(["xdg-open", "lutris:" + slug]);
        }
    }
    function uninstallGame(game) {
        if (!game || !game.id) return;
        const src = (game.source || "").toLowerCase();
        if (src === "steam") {
            root._runSteamAction(game, "uninstall");
        } else if (src === "lutris") {
            const slug = game.id.substring(7); // strip "lutris_"
            Quickshell.execDetached(["lutris", "lutris:uninstall/" + slug]);
        }
    }
    function getCompletedGamesList() {
        const result = [];
        // For each completed game, prefer live installed data, fall back to stored snapshot
        const ids = Object.keys(root.completedGames);
        for (let j = 0; j < ids.length; j++) {
            const id = ids[j];
            const installed = root._installedGamesMap[id];
            result.push(installed || root.completedGames[id]);
        }
        return result.sort(function(a, b) { return a.name.localeCompare(b.name); });
    }
    function updateAccessData(gameId) {
        const ad = Object.assign({}, root.accessData);
        const now = Date.now();
        const prev = ad[gameId];
        ad[gameId] = {
            count: (prev?.count || 0) + 1,
            lastAccessed: now,
            firstAccessed: prev?.firstAccessed || now
        };
        _accessStore.commit(ad);
    }
    function resortGames() {
        root.lastAccessTime = Date.now();
        root.games = sortGames([...root.games]);
        refilter();
    }
    function sortGames(gamesList) {
        if (root.sortOrder === "none") {
            return gamesList;
        } else if (root.sortOrder === "playtime") {
            return gamesList.sort((a, b) => {
                const ptA = a.playtime ?? 0;
                const ptB = b.playtime ?? 0;
                return ptB - ptA;
            });
        } else if (root.sortOrder === "recency") {
            return gamesList.sort((a, b) => {
                const timeA = root.accessData[a.id]?.lastAccessed ?? 0;
                const timeB = root.accessData[b.id]?.lastAccessed ?? 0;
                return timeB - timeA;
            });
        } else if (root.sortOrder === "favorites" || root.sortOrder === "completed") {
            return gamesList.sort((a, b) => a.name.localeCompare(b.name));
        }
        return gamesList;
    }
    // ── Filtering (moved from UI for reuse) ─────────────────────
    property string _prevSearchQuery: ""  // Optimization: Track previous query for incremental filtering
    onSearchQueryChanged: refilter()
    onSelectedLauncherChanged: { _prevSearchQuery = ""; refilter(); }
    onSelectedTagChanged: { _prevSearchQuery = ""; refilter(); }
    // A tag that's gone (its last game untagged, or removed everywhere) stops filtering, so the grid
    // never stays stuck on "No games tagged …" with no tag button left to clear it
    onAllTagsChanged: if (selectedTag !== "" && allTags.indexOf(selectedTag) < 0) selectedTag = ""
    onHideWithoutBoxArtChanged: { _prevSearchQuery = ""; refilter(); }
    onHidePartialBoxArtChanged: { _prevSearchQuery = ""; refilter(); }
    onSortOrderChanged: {
        _prevSearchQuery = "";
        resortGames();
        if (Config.options?.gameLauncher) Config.options.gameLauncher.sortOrder = root.sortOrder;
    }
    function refilter() {
        let allGames;
        if (root.sortOrder === "completed") {
            allGames = getCompletedGamesList();
            if (root.searchQuery !== "")
                allGames = fuzzySearch(root.searchQuery, allGames);
        } else {
            // Optimization: Incremental filtering — if query is being refined (chars added),
            // search the already-filtered list instead of the full games list
            const isRefinement = root.searchQuery !== "" && root._prevSearchQuery !== ""
                && root.searchQuery.toLowerCase().startsWith(root._prevSearchQuery.toLowerCase())
                && root.searchQuery.length > root._prevSearchQuery.length;
            if (root.searchQuery === "") {
                allGames = root.games;
            } else if (isRefinement && root.filteredGames.length > 0) {
                // Re-score only the current filtered set (subset search)
                allGames = fuzzySearch(root.searchQuery, root.filteredGames);
            } else {
                allGames = fuzzySearch(root.searchQuery);
            }
        }
        root._prevSearchQuery = root.searchQuery;
        // Single-pass filter: launcher + favorites + tag + boxArt + dedup
        const filterLauncher = root.selectedLauncher !== "all";
        const launcherLower = filterLauncher ? root.selectedLauncher : "";
        const filterFav = root.sortOrder === "favorites";
        const filterTag = root.selectedTag !== "";
        const selectedTag = root.selectedTag;
        const hideUninstalled = root.searchQuery === "" && !filterTag; // Searching or looking at a tag: owned ones too
        const hideNoArt = root.hideWithoutBoxArt;
        const hidePartial = root.hidePartialBoxArt;
        const seen = new Set();
        const result = [];
        for (let fi = 0; fi < allGames.length; fi++) {
            const g = allGames[fi];
            if (hideUninstalled && g.stateFlags === 0) continue;
            if (filterLauncher && (!g.source || g.source.toLowerCase() !== launcherLower)) continue;
            if (filterFav && !isFavorite(g.id)) continue;
            if (filterTag && !root.hasTag(g.id, selectedTag)) continue;
            if (hideNoArt && (!g.boxArt || g.boxArt.length === 0) && g.source !== "Custom") continue;
            if (hidePartial && g.partialBoxArt) continue;
            const key = g.id || g.name;
            if (seen.has(key)) continue;
            seen.add(key);
            result.push(g);
        }
        root.filteredGames = result;
    }
    // ── File watcher for auto-refresh ─────────────────────────
    // watch_games.sh prints raw inotify events ("dir/ EVENT file"). Installs/uninstalls
    // refresh quickly; manifest edits (Steam rewrites a manifest when a download starts, pauses
    // or finishes) wait a little longer, for the burst to settle. Events during a scan are
    // dropped, the scan covers them.
    Timer {
        id: _watchDebounce
        repeat: false
        onTriggered: if (!root.loading) root.refreshGames()
    }
    Process {
        id: watchGamesProc
        running: true
        command: [Quickshell.shellPath("scripts/game-launcher/watch_games.sh")]
        stdout: SplitParser {
            onRead: data => {
                if (root.loading) return;
                const structural = /\b(CREATE|DELETE|MOVED_TO|MOVED_FROM)\b/.test(data);
                const interval = structural ? 2000 : 5000;
                // Don't let a later edit postpone an already-pending quick refresh
                if (_watchDebounce.running && _watchDebounce.interval < interval) return;
                _watchDebounce.interval = interval;
                _watchDebounce.restart();
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.indexOf("MISSING_INOTIFYWAIT") >= 0)
                    console.warn("GameLauncher: inotifywait not installed, file watching disabled");
                else if (data.indexOf("NO_PATHS") >= 0)
                    console.warn("GameLauncher: no watch paths found, file watching disabled");
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Restart watcher if it crashed (not if it exited cleanly due to missing tools)
            if (exitCode !== 0 && exitCode !== 1) {
                _watchRestartTimer.start();
            }
        }
    }
    Timer {
        id: _watchRestartTimer
        interval: 10000
        onTriggered: { watchGamesProc.running = true; }
    }
    Process {
        id: detectGamesProc
        running: false
        command: [Quickshell.shellPath("scripts/game-launcher/detect_games.sh"), root.cacheDir, root.boxArtDir]
        environment: ({ STEAM_API_KEY: root.steamApiKey }) // Not an argument: any process can read those (ps)
        // A scan that started before the keyring handed over the API key misses the API's games: run again
        onRunningChanged: if (!running && root._rescanForKey) { root._rescanForKey = false; root.refreshGames(); }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    root.loading = false;
                    return;
                }
                // Nothing changed since the last scan: keep the current list so the grid
                // doesn't reset its scroll position and replay its entrance animation
                if (text === root._lastDetectOutput && root.games.length > 0) {
                    root.loading = false;
                    return;
                }
                try {
                    let parsedGames = JSON.parse(text);
                    // Filter games without box art if configured
                    if (root.hideWithoutBoxArt) {
                        parsedGames = parsedGames.filter(game => game.boxArt || game.source === "Custom");
                    }
                    for (const g of parsedGames) if (g.source === "Custom") root._applySessionTimes(g);
                    // Optimization: Pre-derive hero art paths so UI bindings don't do string ops
                    for (let i = 0; i < parsedGames.length; i++) {
                        const g = parsedGames[i];
                        if (!g.heroArt && g.boxArt) {
                            const derived = g.boxArt.replace("library_600x900.jpg", "library_hero.jpg")
                                                 .replace("library_600x900_2x.jpg", "library_hero.jpg");
                            if (derived !== g.boxArt && derived.startsWith("/")) g.derivedHeroArt = derived;
                        }
                    }
                    root.games = sortGames(parsedGames);
                    root._lastDetectOutput = text;
                    root.loading = false;
                    refilter();
                    // Save to cache for instant load next time
                    _gamesCacheStore.value = root.games;
                    _gamesCacheStore.save();
                } catch (e) {
                    console.error("Failed to parse games data:", e);
                    root.loading = false;
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                console.warn("Game detection stderr:", data);
            }
        }
    }
    property string _lastDetectOutput: ""
    property bool _rescanForKey: false
    onSteamApiKeyChanged: {
        if (root.steamApiKey.length === 0) return;
        if (detectGamesProc.running) root._rescanForKey = true;
        else root.refreshGames();
    }
    function refreshGames() {
        root.loading = true;
        detectGamesProc.running = true;
    }
    signal gameLaunching(var game) // For the launch splash (modules/gameLauncher/LaunchSplash.qml)
    // option: which of a Steam game's launch options (its index, scripts/game-launcher/steam_launch_options.py),
    // picked on its page, so Steam starts that one without asking; -1 for its usual command
    property var lastLaunchOption: ({}) // id → the option last launched, for the splash's Retry
    function launchGame(game, option = -1) {
        if (game.launchCommand) {
            root.markBuildSeen(game); // Playing it is seeing the update
            startSession(game);
            root.lastLaunchOption = Object.assign({}, root.lastLaunchOption, { [game.id]: option });
            // Any word between the id and the index works ("x"); without one Steam ignores the index
            Quickshell.execDetached(option >= 0 && game.id.startsWith("steam_")
                ? ["steam", "-silent", `steam://launch/${game.id.substring(6)}/x/${option}`]
                : game.launchCommand);
            root.gameLaunching(game);
            // Toast confirming the launch, unless the splash already shows it
            if (Config.options?.gameLauncher?.launchAnimation ?? true) return;
            const notifyCmd = ["notify-send", "Game Launcher", "Launching " + (game.name || "game") + "…", "-a", "Game Launcher"];
            const icon = game.boxArt || game.icon || "";
            if (icon.length > 0) notifyCmd.push("-i", icon);
            Quickshell.execDetached(notifyCmd);
        }
    }
    // ── Games added by hand (any app: a Flatpak, an AppImage, a command) ──
    // From an app's desktop entry (the Add a game list): its name, command and icon. detect_games.sh
    // puts them in the library as source "Custom"; art comes from SteamGridDB when there's a key
    function addCustomGame(entry) {
        if (!entry?.name) return "";
        const command = (entry.command ?? []).filter(a => !/^%[a-zA-Z]$/.test(a)); // Desktop entry field codes (%U…)
        if (command.length === 0) return "";
        const slug = (entry.id || entry.name).toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
        const id = "custom_" + (slug || Date.now());
        if (root.customGames.some(g => g.id === id)) return id; // Already in
        // `flatpak run [options] <app id> …`: the app id is the first argument after run that isn't an option
        let flatpakId = "";
        const run = command.findIndex((a, i) => a === "run" && /(^|\/)flatpak$/.test(command[i - 1] ?? ""));
        if (run >= 0) flatpakId = command.slice(run + 1).find(a => !a.startsWith("-")) ?? "";
        const icon = entry.icon ?? ""; // A name or a path: detect_games.sh finds the file for a name
        _customGamesStore.commit(root.customGames.concat([{
            id: id, name: entry.name, command: command, icon: icon, flatpakId: flatpakId,
            gameDir: entry.workingDirectory ?? ""
        }]));
        root.refreshGames();
        root._autoArt(id, entry.name);
        return id;
    }
    function removeCustomGame(gameId) {
        if (!gameId?.startsWith("custom_")) return;
        _customGamesStore.commit(root.customGames.filter(g => g.id !== gameId));
        for (const f of ["boxArt", "heroArt", "logo"]) root._clearCustomArtField(gameId, f);
        root.refreshGames();
    }
    function isCustomGame(gameId) { return gameId?.startsWith("custom_") ?? false; }
    // Their playtime and last played: the launcher's own sessions (no store keeps them)
    function _applySessionTimes(game) {
        const s = root.sessionData[game.id];
        if (!s) return;
        game.playtime = Math.round((s.totalTime ?? 0) / 60000);
        const last = (s.sessions ?? []).reduce((m, x) => Math.max(m, x.start + x.duration), 0);
        if (last > 0) game.lastPlayed = last;
    }
    function _autoArt(gameId, name) {
        if (root.steamGridDbApiKey.length === 0) return;
        const proc = _autoArtComp.createObject(root, {
            gameId: gameId,
            command: ["python3", "-I", _helper("sgdb_auto_art.py"), name, root.cacheDir + "/custom-art", gameId]
        });
        proc.running = true;
    }
    Component {
        id: _autoArtComp
        Process {
            id: autoArtProc
            property string gameId
            environment: ({ SGDB_KEY: root.steamGridDbApiKey }) // Not an argument: any process can read those (ps)
            stdout: SplitParser {
                onRead: line => {
                    const [kind, ...rest] = line.split(" ");
                    const path = rest.join(" ");
                    if (!path) return;
                    if (kind === "grid") root.setCustomBoxArt(autoArtProc.gameId, path);
                    else if (kind === "hero") root.setCustomHeroArt(autoArtProc.gameId, path);
                    else if (kind === "logo") root.setCustomLogo(autoArtProc.gameId, path);
                }
            }
            onExited: autoArtProc.destroy()
        }
    }

    // ── Steam: who's playing, and updates you haven't played yet ──
    // Players in the game right now (Steam's public count, no key), per app id: { count, at }. Asked for
    // when a game's page shows it, again after 5 minutes
    property var playerCounts: ({})
    function fetchPlayerCount(game) {
        if (!game?.id?.startsWith("steam_")) return;
        const appid = game.id.substring(6);
        const known = root.playerCounts[appid];
        if (known && Date.now() - known.at < 300000) return;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let count = -1; // Not counted (Steam doesn't list it: a game off the store, a tool)
            try {
                const r = JSON.parse(xhr.responseText).response;
                if (xhr.status === 200 && r?.result === 1) count = r.player_count ?? -1;
            } catch (e) {}
            root.playerCounts = Object.assign({}, root.playerCounts, { [appid]: { count: count, at: Date.now() } });
        };
        xhr.open("GET", `https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid=${appid}`);
        xhr.send();
    }
    function playerCount(game) {
        if (!game?.id?.startsWith("steam_")) return -1;
        return root.playerCounts[game.id.substring(6)]?.count ?? -1;
    }
    // Updated since you last played: its build changed since you last played it or read its News.
    // By build, not Steam's LastUpdated: that's also set when a game is installed, so a fresh install of
    // an old game looked updated. The build each game had is remembered (seenBuilds); one not seen
    // before is noted as it is, so only a later change counts
    readonly property alias seenBuilds: _seenBuildsStore.value
    // A game set to update when launched gets its new build just after that launch: so it also has to have
    // been updated (Steam's LastUpdated) more than an hour after the last session began
    function updatedSincePlayed(game) {
        const seen = root.seenBuilds[game?.id ?? ""];
        if (seen === undefined || !((game?.buildId ?? 0) > 0) || game.buildId === seen) return false;
        return game.lastPlayed > 0 && game.lastUpdated * 1000 > game.lastPlayed + 3600000; // Never played: nothing to have missed
    }
    function markBuildSeen(game) { // Played it, or opened its News
        if (!game?.id?.startsWith("steam_") || !(game.buildId > 0) || root.seenBuilds[game.id] === game.buildId) return;
        _seenBuildsStore.commit(Object.assign({}, root.seenBuilds, { [game.id]: game.buildId }));
    }
    function _noteNewBuilds() { // Installed games not seen before: their build as it is now
        if (!_seenBuildsStore.loadedOnce) return;
        const add = {};
        for (const g of root.games)
            if (g.id.startsWith("steam_") && g.buildId > 0 && root.seenBuilds[g.id] === undefined) add[g.id] = g.buildId;
        if (Object.keys(add).length > 0) _seenBuildsStore.commit(Object.assign({}, root.seenBuilds, add));
    }
    onGamesChanged: _noteNewBuilds()

    // ── Session playtime ──
    // A watcher per launched game (scripts/game-launcher/watch_game.py) reports when its process comes
    // up and when it exits, so a session is the time actually played. While it runs, the last time it
    // was seen is saved every minute: a session still open when the shell restarts is watched again,
    // and if the game closed in the meantime it ends at that last sighting.
    property var _watchers: ({}) // gameId → watcher Process
    readonly property var _genericPrograms: ["sh", "bash", "dash", "zsh", "fish", "env", "python", "python3", "java", "wine", "wine64",
        "flatpak", "gamemoderun", "prime-run", "gtk-launch", "xdg-open", "steam", "lutris", "mangohud", "gamescope"]
    // How to find a running game's processes, for scripts/clips/game_pids.py and focus_game.py (the overlay's
    // game sound, the Playing button): steam:<id>, lutris:<name>, flatpak:<app id> (a Lutris game can run one,
    // as Hytale does), exe:<program> for one added by hand
    function processMatchers(game) {
        if (!game?.id) return [];
        const out = [];
        if (game.id.startsWith("steam_")) out.push("steam:" + game.id.substring(6));
        else if (game.id.startsWith("lutris_") && game.name) out.push("lutris:" + game.name);
        else if (game.id.startsWith("custom_") && !game.flatpakId) {
            const exe = (game.launchCommand?.[0] ?? "").replace(/^.*\//, "");
            if (exe && !root._genericPrograms.includes(exe)) out.push("exe:" + exe);
        }
        if (game.flatpakId) out.push("flatpak:" + game.flatpakId);
        return out;
    }
    function startSession(game) {
        // Steam runs the game under its reaper with the app id, Lutris under lutris-wrapper with the name
        // A game added by hand: its Flatpak's sandbox, or its program
        const watch = game.id.startsWith("steam_") ? ["steam", game.id.substring(6)]
            : game.id.startsWith("lutris_") ? ["lutris", game.name]
            : game.id.startsWith("custom_") ? (game.flatpakId ? ["flatpak", game.flatpakId] : ["exe", game.launchCommand?.[0] ?? ""])
            : null;
        // A program that only starts others (sh -c …, env …) would look running all the time: not watched
        if (watch && (!watch[1] || (watch[0] === "exe" && root._genericPrograms.includes(watch[1].replace(/^.*\//, ""))))) return;
        if (!watch) return;
        const sd = _clone(root.sessionData);
        if (!sd[game.id]) sd[game.id] = { sessions: [], totalTime: 0 };
        sd[game.id].watch = watch;
        _sessionStore.commit(sd);
        _watchGame(game.id, watch, 600); // Steam may update or compile shaders before the game starts
    }
    function _resumeSessions() {
        for (const id of Object.keys(root.sessionData)) {
            const s = root.sessionData[id];
            if (!s?.watch && !s?.lastStart) continue;
            if (s.watch) _watchGame(id, s.watch, 10); // Still running: carries on; closed: "never"
            else _onWatcherEvent(id, "never"); // Opened before sessions were watched: no real end known
        }
    }
    function _watchGame(gameId, watch, grace) {
        if (root._watchers[gameId]) return; // Launched again while it's already being watched
        const proc = _watcherComp.createObject(root, {
            gameId: gameId,
            command: ["python3", "-I", _helper("watch_game.py"), watch[0], watch[1], String(grace)]
        });
        root._watchers[gameId] = proc;
        proc.running = true;
    }
    Component {
        id: _watcherComp
        Process {
            id: watcherProc
            property string gameId
            stdout: SplitParser {
                onRead: line => {
                    const [event, ms] = line.trim().split(" ");
                    root._onWatcherEvent(watcherProc.gameId, event, Number(ms));
                }
            }
            onExited: {
                delete root._watchers[watcherProc.gameId];
                watcherProc.destroy();
            }
        }
    }
    function _onWatcherEvent(gameId, event, ms) {
        const sd = _clone(root.sessionData);
        const s = sd[gameId];
        if (!s) return;
        if (event === "started") {
            if (!s.lastStart) s.lastStart = ms; // Re-watched after a restart: the session goes on
            s.lastAlive = ms;
        } else if (event === "alive") {
            s.lastAlive = ms;
        } else if (event === "ended") {
            _closeSession(s, ms);
        } else if (event === "never") {
            _closeSession(s, s.lastAlive ?? 0); // Never started, or closed while the shell was down
        } else {
            return;
        }
        _sessionStore.commit(sd);
    }
    // 1 minute to 24 hours counts as playtime
    function _closeSession(s, end) {
        const duration = end - (s.lastStart ?? end);
        if (s.lastStart && duration >= 60000 && duration <= 86400000) {
            s.totalTime = (s.totalTime || 0) + duration;
            s.sessions.push({ start: s.lastStart, duration: duration });
        }
        delete s.lastStart;
        delete s.lastAlive;
        delete s.watch;
    }

    /**
     * Scored fuzzy search — matches subsequences, handles typos, ranks by quality.
     *
     * Scoring:
     *  - Consecutive character matches get bonus points (feels like "exact" match)
     *  - Matches at the start of the string or after a word boundary (space, _, -) score higher
     *  - Shorter names score slightly higher (penalize long unrelated titles)
     *  - Exact substring match gets a large bonus to always rank first
     *  - Source field can contribute a small match boost
     *
     * Returns games sorted best-match-first. Games that don't match at all are filtered out.
     */
    function fuzzySearch(query, sourceList) {
        if (!query || query.length === 0) {
            return sourceList || root.games;
        }
        const gamesToSearch = sourceList || root.games;
        const qLower = query.toLowerCase();
        const qLen = qLower.length;
        function scoreMatch(text) {
            if (!text) return -1;
            const tLower = text.toLowerCase();
            const tLen = tLower.length;
            // Exact substring — always best
            const subIdx = tLower.indexOf(qLower);
            if (subIdx >= 0) {
                // Bonus: 100 base + coverage ratio + position bonus
                let bonus = 100 + (qLen / tLen) * 50;
                if (subIdx === 0) bonus += 30;
                else if (" _-:.".indexOf(tLower[subIdx - 1]) >= 0) bonus += 20;
                return bonus;
            }
            // Subsequence match with scoring
            let qi = 0;
            let score = 0;
            let consecutive = 0;
            let prevMatchIdx = -2;
            for (let ti = 0; ti < tLen && qi < qLen; ti++) {
                if (tLower[ti] === qLower[qi]) {
                    qi++;
                    // Consecutive bonus
                    if (ti === prevMatchIdx + 1) {
                        consecutive++;
                        score += 3 + consecutive * 2;
                    } else {
                        consecutive = 0;
                        score += 2;
                    }
                    // Word boundary bonus
                    if (ti === 0 || " _-:.".indexOf(tLower[ti - 1]) >= 0) {
                        score += 5;
                    }
                    prevMatchIdx = ti;
                }
            }
            if (qi < qLen) return -1; // didn't match all query chars
            // Penalize long names slightly (prefer tighter matches)
            score -= (tLen - qLen) * 0.3;
            return Math.max(score, 0.1);
        }
        const scored = [];
        for (let i = 0; i < gamesToSearch.length; i++) {
            const game = gamesToSearch[i];
            const nameScore = scoreMatch(game.name);
            const sourceScore = game.source ? scoreMatch(game.source) * 0.3 : -1;
            // Search tags (user-defined)
            let tagScore = -1;
            const gameTags = root.tagsData[game.id];
            if (gameTags && Array.isArray(gameTags)) {
                for (let ti = 0; ti < gameTags.length; ti++) {
                    const ts = scoreMatch(gameTags[ti]);
                    if (ts > tagScore) tagScore = ts;
                }
            }
            tagScore *= 0.6;
            // Search metadata (genres, developers, publishers)
            let metaScore = -1;
            const meta = root.metadataCache[game.id];
            if (meta) {
                if (meta.genres && Array.isArray(meta.genres)) {
                    for (let gi = 0; gi < meta.genres.length; gi++) {
                        const gs = scoreMatch(meta.genres[gi]);
                        if (gs > metaScore) metaScore = gs;
                    }
                }
                if (meta.developers && Array.isArray(meta.developers)) {
                    for (let di = 0; di < meta.developers.length; di++) {
                        const ds = scoreMatch(meta.developers[di]);
                        if (ds > metaScore) metaScore = ds;
                    }
                }
                if (meta.publishers && Array.isArray(meta.publishers)) {
                    for (let pi = 0; pi < meta.publishers.length; pi++) {
                        const ps = scoreMatch(meta.publishers[pi]);
                        if (ps > metaScore) metaScore = ps;
                    }
                }
            }
            metaScore *= 0.5;
            const best = Math.max(nameScore, sourceScore, tagScore, metaScore);
            if (best > 0) {
                scored.push({ game: game, score: best });
            }
        }
        // Equal scores (Fallout 2, 3 and 4) keep the library's order. Without a tie-break they swapped on
        // every keystroke (Qt's sort isn't stable, and refining searches the last result), so tiles jumped
        const rank = new Map();
        for (let gi = 0; gi < root.games.length; gi++) rank.set(root.games[gi], gi);
        const rankOf = game => rank.get(game) ?? Number.MAX_SAFE_INTEGER;
        scored.sort(function(a, b) { return (b.score - a.score) || (rankOf(a.game) - rankOf(b.game)); });
        const result = new Array(scored.length);
        for (let ri = 0; ri < scored.length; ri++) result[ri] = scored[ri].game;
        return result;
    }
    // Custom art overrides
    function getCustomArt(gameId) {
        const data = root.customArt[gameId];
        return data ? Object.assign({}, data) : {};
    }
    // The art a field stops using is deleted, if it's ours (in custom-art/). Replacing a picked file with a
    // SteamGridDB one (or the other way round) used to leave the old one behind: 76 files, 73 MB
    function _dropReplacedArt(oldPath, newPath) {
        if (!oldPath || oldPath === newPath || !oldPath.startsWith(root.cacheDir + "/custom-art/")) return;
        let uses = 0; // Still used by another field or game: keep it
        for (const id in root.customArt)
            for (const f in root.customArt[id])
                if (root.customArt[id][f] === oldPath) uses++;
        if (uses <= 1) Quickshell.execDetached(["rm", "-f", "--", oldPath]);
    }
    function _setCustomArtField(gameId, field, filePath) {
        const art = _clone(root.customArt);
        if (!art[gameId]) art[gameId] = {};
        root._dropReplacedArt(art[gameId][field], filePath);
        art[gameId][field] = filePath;
        _customArtStore.commit(art);
    }
    function _clearCustomArtField(gameId, field) {
        if (root.customArt[gameId] && root.customArt[gameId][field]) {
            const art = _clone(root.customArt);
            root._dropReplacedArt(art[gameId][field], "");
            delete art[gameId][field];
            if (Object.keys(art[gameId]).length === 0) delete art[gameId];
            _customArtStore.commit(art);
        }
    }
    function setCustomHeroArt(gameId, filePath) { _setCustomArtField(gameId, "heroArt", filePath); }
    function setCustomBoxArt(gameId, filePath) { _setCustomArtField(gameId, "boxArt", filePath); }
    function setCustomLogo(gameId, filePath) { _setCustomArtField(gameId, "logo", filePath); }
    function clearCustomHeroArt(gameId) { _clearCustomArtField(gameId, "heroArt"); }
    function clearCustomBoxArt(gameId) { _clearCustomArtField(gameId, "boxArt"); }
    function clearCustomLogo(gameId) { _clearCustomArtField(gameId, "logo"); }
    // ── Tags / Categories ─────────────────────────────────────
    function getGameTags(gameId) {
        const tags = root.tagsData[gameId];
        return Array.isArray(tags) ? tags : [];
    }
    function hasTag(gameId, tag) {
        const tags = getGameTags(gameId);
        return tags.indexOf(tag) >= 0;
    }
    // Alphabetical, ignoring case (so "fps" doesn't sort after every capitalised tag)
    function _tagOrder(x, y) { return x.localeCompare(y, undefined, { sensitivity: "base" }); }
    function addTag(gameId, tag) {
        tag = (tag ?? "").trim();
        if (!gameId || tag.length === 0) return;
        // An existing tag typed in another case is that tag ("FPS" joins "fps"), not a second one
        tag = root.allTags.find(t => _tagOrder(t, tag) === 0) ?? tag;
        const data = _clone(root.tagsData);
        const tags = Array.isArray(data[gameId]) ? data[gameId] : (data[gameId] = []);
        if (tags.indexOf(tag) >= 0) return;
        tags.push(tag);
        tags.sort(_tagOrder);
        _commitTags(data);
    }
    function removeTag(gameId, tag) {
        if (!gameId || !tag) return;
        const data = _clone(root.tagsData);
        if (_dropTag(data, gameId, tag)) _commitTags(data);
    }
    function removeTagEverywhere(tag) { // The Tags panel's bin
        if (!tag) return;
        const data = _clone(root.tagsData);
        let changed = false;
        for (const id of Object.keys(data)) changed = _dropTag(data, id, tag) || changed;
        if (changed) _commitTags(data);
    }
    // Takes tag off one game in data (dropping the game's entry once it has none); whether it had it
    function _dropTag(data, gameId, tag) {
        const tags = data[gameId];
        const idx = Array.isArray(tags) ? tags.indexOf(tag) : -1;
        if (idx < 0) return false;
        tags.splice(idx, 1);
        if (tags.length === 0) delete data[gameId];
        return true;
    }
    // Saves, and refilters a tag view (a tag that's gone clears itself through onAllTagsChanged)
    function _commitTags(data) {
        _tagsStore.commit(data);
        if (root.selectedTag !== "") refilter();
    }
    // ── Particle override ────────────────────────────────────
    function getParticleOverride(gameId) {
        return root.particleOverrides[gameId] || "";
    }
    function setParticleOverride(gameId, preset) {
        if (!gameId) return;
        const data = Object.assign({}, root.particleOverrides);
        if (!preset || preset.length === 0 || preset === "auto") {
            delete data[gameId];
        } else {
            data[gameId] = preset;
        }
        _particleOverrideStore.commit(data);
    }
    // ── Build / update status helpers ───────────────────────────
    // Steam StateFlags bitmask: bit 1 (0x2) = NeedsUpdate
}
