import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * The game page's Captures: a game's screenshots in a panel growing up out of the launcher (LauncherTopPanel): what Steam's F12
 * saved and the game's own screenshot folders (scripts/game-launcher/find_screenshots.py), newest
 * first, in rows that keep each shot's own shape (portrait and cropped ones at least square); clicking one
 * opens it large with its details and a filmstrip under it. Keys come from the details page while it's
 * open (handleKey): on the grid the arrows (Home/End) move a ring and Enter opens that one; in the viewer
 * ←/→ (Home/End) step through and Delete moves it to the Trash; Esc goes back to the grid, then closes.
 * What it found is kept per game for the session (GameLauncherService.screenshotsCache), so it opens
 * filled in and looks again behind that.
 *
 * With an Immich server set (Settings → Game Launcher), the header uploads them there (all of them on the
 * grid, the one open in the viewer) into the game's album, and that album's photos show here too, by
 * date among the rest: all but the ones uploaded from here (same file name as one on disk), so each shows
 * once. Those are "immich:<asset id>" in paths, shown from copies scripts/game-launcher/immich_media.py
 * fetches; they can't be trashed from here. With both kinds, the header filters by where they are.
 *
 * The header also switches to the Clips page (ClipsPage.qml: gameplay clips saved with the clip key);
 * Tab flips between the two.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1200

    property var paths: [] // File paths and "immich:<asset id>", newest first (after the filter)
    property var _info: ({}) // Entry -> { time, width, height, remote }
    // "Looking for screenshots…" until both the folders and the Immich album have answered
    readonly property bool loading: paths.length === 0 && (finder.running || _albumLoading)
    property int viewerIndex: -1 // -1: the grid
    readonly property bool viewing: viewerIndex >= 0 && viewerIndex < paths.length
    readonly property string currentEntry: viewing ? paths[viewerIndex] : ""
    readonly property string appid: game?.id?.startsWith("steam_") ? game.id.substring(6) : ""
    property string page: GameLauncherService.screenshotsPage // "shots" or "clips"; opens on the last one used
    readonly property bool onShots: page === "shots"
    onPageChanged: { _resetView(); GameLauncherService.screenshotsPage = page; }

    onShownChanged: {
        if (!shown) return;
        _resetView();
        refresh();
    }
    onGameChanged: _loadGame()
    Component.onCompleted: _loadGame() // Made with its game set: no change signal for that
    function _loadGame() {
        // What was found for it last time (see GameLauncherService.screenshotsCache), else nothing yet
        const c = GameLauncherService.screenshotsCache[game?.id ?? ""];
        paths = []; _local = c?.local ?? []; _remote = c?.remote ?? []; immichAlbumId = c?.albumId ?? ""; _fetched = c?.fetched ?? {};
        filter = "all"; _resetView();
        if (c) _merge();
        if (shown) refresh();
    }
    // Kept for the next time it opens (the panel is made anew each time)
    function _remember() {
        if (!game?.id) return;
        GameLauncherService.screenshotsCache[game.id] = { local: _local, remote: _remote, albumId: immichAlbumId, fetched: _fetched };
    }
    function _resetView() { viewerIndex = -1; gridIndex = -1; keyboardNav = false; } // Back on the grid, no keyboard ring
    function refresh() {
        if (!game) return;
        finder.running = false;
        finder.running = true;
        fetchImmichAlbum();
    }

    // ── Sources ──
    property var _local: []  // [{ key: path, time, width, height, name }] from find_screenshots.py
    property string screenshotFolder: "" // Where the game's screenshots go (find_screenshots.py), with none yet too
    property var _remote: [] // The same from the game's Immich album
    property int localCount: 0  // After leaving out the uploaded copies of local ones
    property int remoteCount: 0
    property string filter: "all" // "all", "local", "immich": only offered with some of both
    onFilterChanged: { viewerIndex = -1; _merge(); }
    // Both lists by date; an album photo with a local file's name is that file uploaded: shown once, from disk
    function _merge() {
        const onDisk = new Set(_local.map(e => e.name));
        const remote = _remote.filter(e => !onDisk.has(e.name));
        localCount = _local.length;
        remoteCount = remote.length;
        if (localCount === 0 || remoteCount === 0) filter = "all"; // Nothing left to filter between
        const info = {};
        for (const e of _local) info[e.key] = { time: e.time, width: e.width, height: e.height, remote: false };
        for (const e of remote) info[e.key] = { time: e.time, width: e.width, height: e.height, remote: true };
        const merged = (filter === "immich" ? [] : _local).concat(filter === "local" ? [] : remote)
            .sort((a, b) => b.time - a.time).map(e => e.key);
        // Only when something changed: the grid's layout reads it, so a new object rebuilds every tile
        // (and replays their fade-in) each time the album is checked again
        if (JSON.stringify(info) !== JSON.stringify(_info)) _info = info;
        _remember();
        if (merged.join("\n") === paths.join("\n")) return; // Unchanged: the grid isn't rebuilt
        const current = currentEntry;
        paths = merged;
        if (current !== "") viewerIndex = Math.max(0, merged.indexOf(current)); // Stay on the one being viewed
    }
    Process {
        id: finder
        command: [Quickshell.shellPath("scripts/game-launcher/find_screenshots.py"), root.appid, root.game?.gameDir || "", root.game?.flatpakId || ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const folderLine = text.split("\n").find(l => l.startsWith("folder\t"));
                root.screenshotFolder = folderLine ? folderLine.substring(7) : "";
                root._local = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 4).map(f => {
                    const path = f.slice(3).join("\t");
                    return { key: path, time: parseFloat(f[0]), width: parseInt(f[1]), height: parseInt(f[2]), name: path.replace(/^.*\//, "") };
                });
                root._merge();
            }
        }
    }

    // ── Immich: the album named after the game (as GameLauncherService.uploadToImmich makes them) ──
    property string immichAlbumId: ""
    property bool _albumLoading: false
    function isRemote(entry) { return entry.startsWith("immich:"); }
    readonly property var localPaths: paths.filter(p => !isRemote(p))
    readonly property bool currentIsRemote: viewing && isRemote(currentEntry)
    // An image to show: the file, or the server's copy once fetched ("" until then: the tile waits).
    // Fetched with the key in a header, into a private cache: an Image can't send headers, and a key in
    // the URL would land in proxies' access logs
    property var _fetched: ({}) // asset id -> path
    function sourceFor(entry) {
        if (!isRemote(entry)) return "file://" + entry;
        const path = _fetched[entry.substring(7)];
        return path ? "file://" + path : "";
    }
    // Copies arrive one by one: handed to the tiles in batches, so the tiles aren't all re-bound per copy
    property var _fetchedPending: ({})
    Timer {
        id: fetchedFlush
        interval: 120
        onTriggered: { root._fetched = Object.assign({}, root._fetched, root._fetchedPending); root._fetchedPending = {}; root._remember(); }
    }
    Process {
        id: mediaFetcher
        environment: ({ IMMICH_API_KEY: GameLauncherService.immichApiKey }) // Not an argument: any process can read those (ps)
        stdout: SplitParser {
            onRead: line => {
                const [id, path] = line.split("\t");
                if (!path) return;
                root._fetchedPending[id] = path;
                if (!fetchedFlush.running) fetchedFlush.start();
            }
        }
    }
    // An upload from here may have made the album or added to it
    Connections {
        target: GameLauncherService
        function onImmichUploadFinished(album) { if (root.shown && album === root.game?.name) root.fetchImmichAlbum(); }
    }
    function fetchImmichAlbum() {
        if (!GameLauncherService.immichReady || !game?.name) { _remote = []; immichAlbumId = ""; _albumLoading = false; return; }
        const name = game.name;
        _albumLoading = true;
        const failed = () => { if (game?.name === name) _albumLoading = false; };
        _immichRequest("GET", `/albums?name=${encodeURIComponent(name)}&isOwned=true`, null, failed, albums => {
            if (game?.name !== name) return; // Moved on to another game meanwhile
            const album = albums.find(a => a.albumName === name);
            immichAlbumId = album?.id ?? "";
            if (!album) { _remote = []; _merge(); _albumLoading = false; return; }
            _immichRequest("POST", "/search/metadata", { albumIds: [album.id], type: "IMAGE", order: "desc", size: 1000 }, failed, result => {
                if (game?.name !== name) return;
                const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i; // They go in URLs and file names
                _remote = (result.assets?.items ?? []).filter(a => uuid.test(a.id)).map(a => ({
                    key: "immich:" + a.id, time: (Date.parse(a.fileCreatedAt) || 0) / 1000,
                    width: a.width ?? 0, height: a.height ?? 0, name: a.originalFileName
                }));
                _merge();
                _albumLoading = false;
                mediaFetcher.running = false;
                mediaFetcher.command = [Quickshell.shellPath("scripts/game-launcher/immich_media.py"), GameLauncherService.immichUrl,
                                        GameLauncherService.cacheDir, ..._remote.map(e => e.key.substring(7))];
                if (_remote.length > 0) mediaFetcher.running = true;
            });
        });
    }
    function _immichRequest(method, path, body, failed, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try { done(JSON.parse(xhr.responseText)); return; } catch (e) { console.warn("[Screenshots] Immich:", e); }
            } else {
                console.warn("[Screenshots] Immich", method, path.replace(/\?.*/, ""), "→", xhr.status); // Not the query: no names in logs
            }
            failed();
        };
        xhr.open(method, GameLauncherService.immichUrl + "/api" + path);
        xhr.setRequestHeader("x-api-key", GameLauncherService.immichApiKey);
        xhr.setRequestHeader("Accept", "application/json");
        if (body) xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : null);
    }

    // ── Actions ──
    // Outside: a file in the image viewer; an Immich photo on its page in Immich
    function openExternally(entry) {
        Quickshell.execDetached(["xdg-open", isRemote(entry) ? `${GameLauncherService.immichUrl}/photos/${entry.substring(7)}` : entry]);
    }
    // The shot just copied: the viewer's copy button shows a tick, a grid tile a "Copied" badge
    property string copiedEntry: ""
    readonly property bool copied: copiedEntry !== "" && copiedEntry === currentEntry
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedEntry = "" }
    function copyCurrent() { copyEntry(currentEntry); }
    // Always copied as PNG: Chromium/Electron apps (Vesktop, browsers) only paste image/png,
    // and Steam saves JPEGs. The tick/badge only shows once it's really copied
    function copyEntry(entry) {
        if (!entry) return;
        copier.running = false;
        copier.entry = entry;
        copier.command = isRemote(entry)
            ? ["bash", "-o", "pipefail", "-c", 'curl -sf -H "x-api-key: $IMMICH_API_KEY" "$0" | magick - png:- | wl-copy --type image/png',
               `${GameLauncherService.immichUrl}/api/assets/${entry.substring(7)}/original`]
            : ["bash", "-o", "pipefail", "-c", 'case "${0,,}" in *.png) wl-copy --type image/png < "$0" ;; *) magick "$0" png:- | wl-copy --type image/png ;; esac', entry];
        copier.running = true;
    }
    Process { // Remote ones: the full-size original, from the server
        id: copier
        property string entry
        environment: ({ IMMICH_API_KEY: GameLauncherService.immichApiKey }) // Not an argument: any process can read those (ps)
        onExited: exitCode => { if (exitCode === 0) { root.copiedEntry = copier.entry; copiedTimer.restart(); } }
    }
    // To the Trash (so it can be got back). For Steam's, its small copy in thumbnails/ goes too
    function trashCurrent() {
        const i = viewerIndex, path = currentEntry;
        if (isRemote(path)) return;
        const thumb = path.includes("/760/remote/") ? path.replace(/\/([^/]*)$/, "/thumbnails/$1") : "";
        Quickshell.execDetached(["bash", "-c", 'gio trash -- "$0"; [ -n "$1" ] && [ -f "$1" ] && gio trash -- "$1"', path, thumb]);
        // Merged again (and remembered, or it'd show again for a moment next time): the counts and the filter
        // follow, so trashing the last one on disk under "This PC" lands on all of them, not an empty page.
        // An uploaded copy of it in the album shows again in its place
        _local = _local.filter(e => e.key !== path);
        _merge();
        // On to the next one (the one before, if it was the last); back to the grid once none are left
        viewerIndex = paths.length === 0 ? -1 : Math.min(i, paths.length - 1);
    }
    // Back on the grid: keep the one just viewed in sight
    property int _lastViewed: 0
    onViewerIndexChanged: if (viewerIndex >= 0) { _lastViewed = viewerIndex; gridIndex = viewerIndex; } // The ring comes back on it
    onViewingChanged: if (!viewing) gallery.positionViewAtIndex(gallery.rowOf[_lastViewed] ?? 0, ListView.Contain)

    // Keys, from the details page's handler while this is open. Returns whether it used the key
    function handleKey(key, modifiers) {
        if (key === Qt.Key_Tab && !viewing && !clipsPage.viewing) { page = onShots ? "clips" : "shots"; return true; }
        if (!onShots) {
            if (clipsPage.handleKey(key, modifiers)) return true;
            if (key === Qt.Key_Escape) { closeRequested(); return true; }
            return false;
        }
        if (key === Qt.Key_C && (modifiers & Qt.ControlModifier)) { // Copy: the one being viewed, or the grid's ring/hovered one
            if (viewing) copyCurrent();
            else if (gridIndex >= 0 && gridIndex < paths.length) copyEntry(paths[gridIndex]);
            return true;
        }
        if (key === Qt.Key_Escape) {
            if (viewing) viewerIndex = -1; else closeRequested();
            return true;
        }
        if (viewing && key === Qt.Key_Delete) { trashCurrent(); return true; } // Not Immich's: trashCurrent leaves those
        if (viewing && (key === Qt.Key_Left || key === Qt.Key_Right)) {
            viewerIndex = Math.max(0, Math.min(paths.length - 1, viewerIndex + (key === Qt.Key_Left ? -1 : 1)));
            return true;
        }
        if (viewing && (key === Qt.Key_Home || key === Qt.Key_End)) { viewerIndex = key === Qt.Key_Home ? 0 : paths.length - 1; return true; }
        // The grid: arrows move a ring between the shots, Enter opens the one it's on
        const isArrow = key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Up || key === Qt.Key_Down;
        if (!viewing && paths.length > 0 && (isArrow || key === Qt.Key_Home || key === Qt.Key_End)) {
            if (!keyboardNav || gridIndex < 0 || gridIndex >= paths.length) gridIndex = Math.max(0, Math.min(paths.length - 1, gridIndex)); // First press: just show where it is
            else if (key === Qt.Key_Left) gridIndex = Math.max(0, gridIndex - 1);
            else if (key === Qt.Key_Right) gridIndex = Math.min(paths.length - 1, gridIndex + 1);
            else if (key === Qt.Key_Up || key === Qt.Key_Down) gridIndex = _gridStep(key === Qt.Key_Up ? -1 : 1);
            else gridIndex = key === Qt.Key_Home ? 0 : paths.length - 1;
            keyboardNav = true;
            gallery.positionViewAtIndex(gallery.rowOf[gridIndex] ?? 0, ListView.Contain);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (!viewing && keyboardNav && gridIndex >= 0 && gridIndex < paths.length) viewerIndex = gridIndex;
            return true; // Not on to the details page (Enter there plays the game)
        }
        return isArrow; // Don't move the page under it
    }
    // The grid's keyboard ring: which shot it's on, shown only once a key moved it (hovering moves it too)
    property int gridIndex: -1
    property bool keyboardNav: false
    // ↑/↓: the shot in the row above/below whose middle is nearest this one's
    function _gridStep(dir) {
        const rows = gallery.model, r = gallery.rowOf[gridIndex];
        const cur = rows[r]?.items?.find(it => it.index === gridIndex);
        const next = rows[r + dir];
        if (!cur || !next) return gridIndex;
        const mid = cur.x + cur.width / 2;
        let best = next.items[0];
        for (const it of next.items)
            if (Math.abs(it.x + it.width / 2 - mid) < Math.abs(best.x + best.width / 2 - mid)) best = it;
        return best.index;
    }

    // ── Dates and shapes ──
    function _day(t) { const d = new Date(t * 1000); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }
    // "Today", "Yesterday", a weekday this week, else the date (with the year when it isn't this one)
    function dayLabel(t) {
        if (!(t > 0)) return Translation.tr("Undated");
        const days = Math.round((_day(Date.now() / 1000) - _day(t)) / 86400000);
        const d = new Date(t * 1000);
        if (days === 0) return Translation.tr("Today");
        if (days === 1) return Translation.tr("Yesterday");
        if (days > 1 && days < 7) return d.toLocaleDateString(Qt.locale(), "dddd");
        return d.toLocaleDateString(Qt.locale(), d.getFullYear() === new Date().getFullYear() ? "MMMM d" : "MMMM d, yyyy");
    }
    function timeLabel(t) { return t > 0 ? new Date(t * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : ""; }
    function aspectOf(entry) { // Width / height, kept sane for odd sizes; 16:9 when unknown
        const i = _info[entry];
        return i && i.width > 0 && i.height > 0 ? Math.max(0.5, Math.min(3, i.width / i.height)) : 16 / 9;
    }

    // ── Header ──
    SheetHeader {
        id: header
        z: 2
        icon: "perm_media"
        title: Translation.tr("Captures") // Screenshots and clips; the switch says which page
        subtitle: {
            const parts = [root.game?.name ?? ""];
            if (!root.onShots) {
                if (clipsPage.viewing) parts.push(Translation.tr("%1 of %2").arg(clipsPage.playerIndex + 1).arg(clipsPage.clips.length));
                else if (clipsPage.clips.length > 0) parts.push(clipsPage.clips.length === 1 ? Translation.tr("1 clip") : Translation.tr("%1 clips").arg(clipsPage.clips.length));
                return parts.filter(p => p !== "").join(" · ");
            }
            if (root.viewing) parts.push(Translation.tr("%1 of %2").arg(root.viewerIndex + 1).arg(root.paths.length));
            else if (root.paths.length > 0) {
                parts.push(root.paths.length === 1 ? Translation.tr("1 screenshot") : Translation.tr("%1 screenshots").arg(root.paths.length));
                if (root.filter === "all" && root.remoteCount > 0) parts.push(Translation.tr("%1 in Immich").arg(root.remoteCount));
            }
            if (root._albumLoading && root.paths.length > 0) parts.push(Translation.tr("checking Immich…"));
            return parts.filter(p => p !== "").join(" · ");
        }
        onCloseRequested: root.closeRequested()
        // In the viewer the badge is the way back to the grid (as Esc)
        showBack: root.viewing || clipsPage.viewing
        backTip: root.onShots ? Translation.tr("All screenshots (Esc)") : Translation.tr("All clips (Esc)")
        onBackRequested: { root.viewerIndex = -1; clipsPage.back(); }
        extras: Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Row { // Where they are: only with some of both
            anchors.verticalCenter: parent.verticalCenter
            visible: root.onShots && !root.viewing && root.localCount > 0 && root.remoteCount > 0
            spacing: 2
            Repeater {
                model: [
                    { value: "all", icon: "apps", text: Translation.tr("All") },
                    { value: "local", icon: "computer", text: Translation.tr("This PC") },
                    { value: "immich", icon: "cloud", text: Translation.tr("Immich") }
                ]
                delegate: SelectionGroupButton {
                    required property var modelData
                    required property int index
                    focusPolicy: Qt.NoFocus // The details page keeps the keys
                    leftmost: index === 0
                    rightmost: index === 2
                    buttonIcon: modelData.icon
                    buttonText: modelData.text
                    toggled: root.filter === modelData.value
                    onClicked: root.filter = modelData.value
                }
            }
        }
        Row { // Screenshots or clips (Tab)
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.viewing && !clipsPage.viewing
            spacing: 2
            Repeater {
                model: [
                    { value: "shots", icon: "photo_library", text: Translation.tr("Screenshots") },
                    { value: "clips", icon: "movie", text: Translation.tr("Clips") }
                ]
                delegate: SelectionGroupButton {
                    required property var modelData
                    required property int index
                    focusPolicy: Qt.NoFocus
                    leftmost: index === 0
                    rightmost: index === 1
                    buttonIcon: modelData.icon
                    buttonText: modelData.text
                    toggled: root.page === modelData.value
                    onClicked: root.page = modelData.value
                }
            }
        }
        }
        // To the game's Immich album: on the grid all of them, open one just that one. Screenshots: not the
        // album's own photos (they're there already); clips are "backed up"
        SheetIconButton {
            readonly property bool one: root.onShots ? root.viewing : clipsPage.viewing
            readonly property var files: root.onShots ? (root.viewing ? [root.currentEntry] : root.localPaths)
                : (clipsPage.viewing ? [clipsPage.current.path] : clipsPage.clips.map(c => c.path))
            visible: GameLauncherService.immichReady && (root.onShots ? root.localPaths.length > 0 && !root.currentIsRemote : clipsPage.clips.length > 0)
            enabled: GameLauncherService.immichUploadState !== "uploading"
            iconName: ({ uploading: "hourglass_top", done: "check", failed: "error" })[GameLauncherService.immichUploadState] ?? "cloud_upload"
            tip: GameLauncherService.immichUploadState === "uploading" ? Translation.tr("Uploading to Immich…")
                : root.onShots ? (one ? Translation.tr("Upload to Immich") : Translation.tr("Upload all %1 to Immich").arg(files.length))
                : (one ? Translation.tr("Back up to Immich") : Translation.tr("Back up all %1 to Immich").arg(files.length))
            onClicked: GameLauncherService.uploadToImmich(files, root.game?.name ?? "")
        }
        SheetIconButton {
            visible: root.onShots && !root.viewing && root.immichAlbumId !== "" && GameLauncherService.immichReady
            iconName: "photo_album"; tip: Translation.tr("Open album in Immich")
            onClicked: Quickshell.execDetached(["xdg-open", `${GameLauncherService.immichUrl}/albums/${root.immichAlbumId}`])
        }
        SheetIconButton { // Grid: the folder the newest one on disk is in, else where they go (made if missing)
            visible: root.onShots && !root.viewing && (root.localPaths.length > 0 || root.screenshotFolder !== "")
            iconName: "folder_open"; tip: Translation.tr("Open screenshots folder")
            onClicked: Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "open-folder",
                root.localPaths.length > 0 ? root.localPaths[0].replace(/\/[^/]*$/, "") : root.screenshotFolder])
        }
        SheetIconButton {
            visible: root.viewing
            iconName: root.copied ? "check" : "content_copy"
            tip: root.copied ? Translation.tr("Copied") : Translation.tr("Copy image")
            onClicked: root.copyCurrent()
        }
        SheetIconButton {
            visible: root.viewing
            iconName: "open_in_new"; tip: root.currentIsRemote ? Translation.tr("Open in Immich") : Translation.tr("Open in image viewer")
            onClicked: root.openExternally(root.currentEntry)
        }
        // Clips: their folder on the grid; in the player trim, copy, the video app and Trash
        SheetIconButton {
            visible: !root.onShots && !clipsPage.viewing
            iconName: "folder_open"; tip: Translation.tr("Open clips folder")
            onClicked: clipsPage.openFolder()
        }
        SheetIconButton {
            visible: !root.onShots && clipsPage.viewing
            enabled: clipsPage.exportKind === ""
            active: clipsPage.trimming
            iconName: "content_cut"; tip: clipsPage.trimming ? Translation.tr("Stop trimming (T)") : Translation.tr("Trim (T)")
            onClicked: clipsPage.toggleTrim()
        }
        SheetIconButton {
            visible: !root.onShots && clipsPage.viewing
            iconName: clipsPage.copied ? "check" : "content_copy"
            tip: clipsPage.copied ? Translation.tr("Copied") : Translation.tr("Copy clip (Ctrl+C)")
            onClicked: clipsPage.copyClip(clipsPage.current?.path ?? "")
        }
        SheetIconButton {
            visible: !root.onShots && clipsPage.viewing
            iconName: "open_in_new"; tip: Translation.tr("Open in video app")
            onClicked: clipsPage.openExternally()
        }
        // Trash, kept apart from the rest: the shot or clip open (not an Immich photo: trashCurrent leaves those)
        Item {
            id: trashGap
            visible: root.onShots ? root.viewing && !root.currentIsRemote : clipsPage.viewing
            width: 9; height: 30
            Rectangle { anchors.centerIn: parent; width: 1; height: 16; color: Appearance.colors.colOutlineVariant }
        }
        SheetIconButton {
            visible: trashGap.visible
            danger: true
            iconName: "delete"; tip: Translation.tr("Move to Trash (Delete)")
            onClicked: root.onShots ? root.trashCurrent() : clipsPage.trashCurrent()
        }
    }

    // ── Grid: the shots in rows that fill the width, each at its own shape ──
    ListView {
        id: gallery
        // Wider than the shots by `pad` on each side, so the clip doesn't cut the edge columns' hover ring
        // (and above the first row: topMargin)
        anchors { top: header.bottom; topMargin: 14 - pad; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 20 - pad; rightMargin: 20 - pad }
        topMargin: pad
        bottomMargin: 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.onShots && !root.viewing && root.paths.length > 0
        readonly property int pad: 4 // Room for Tile's ring (3 px outside it)
        readonly property int gap: 8
        readonly property int rowHeight: 172 // Wanted; a full row is scaled to fit the width exactly
        property var rowOf: [] // Shot index -> the model row it's in
        // [{ height, items: [{ entry, index, width, x }] }]
        model: {
            const w = width - pad * 2, gap = gallery.gap, target = rowHeight;
            const rows = [], rowOfIndex = [];
            if (w <= 0) return rows;
            let row = [], sum = 0;
            const flush = last => {
                if (row.length === 0) return;
                const free = w - gap * (row.length - 1);
                const h = last ? Math.min(target, free / sum) : free / sum; // The last row isn't stretched
                const items = row.map(it => ({ entry: it.entry, index: it.index, width: Math.floor(it.aspect * h) }));
                if (!last) items[items.length - 1].width += free - items.reduce((s, it) => s + it.width, 0); // Exactly the width
                let x = 0;
                for (const it of items) { it.x = x; x += it.width + gap; } // For ↑/↓: the nearest one in the next row
                for (const it of row) rowOfIndex[it.index] = rows.length;
                rows.push({ height: Math.round(h), items: items });
                row = []; sum = 0;
            };
            root.paths.forEach((entry, index) => {
                // Portrait or cropped shots get at least a square tile (the picture fills it, trimmed at the top
                // and bottom; the viewer shows it whole), so they aren't thin slivers among full-size ones
                const aspect = Math.max(1, root.aspectOf(entry));
                row.push({ entry: entry, index: index, aspect: aspect });
                sum += aspect;
                if (sum * target + gap * (row.length - 1) >= w) flush(false);
            });
            flush(true);
            rowOf = rowOfIndex;
            return rows;
        }
        delegate: Item {
            id: rowItem
            required property var modelData
            width: gallery.width
            height: modelData.height + gallery.gap
            Row {
                x: gallery.pad
                spacing: gallery.gap
                Repeater {
                    model: rowItem.modelData.items
                    delegate: Tile {
                        required property var modelData
                        width: modelData.width
                        height: rowItem.modelData.height
                        entry: modelData.entry
                        current: root.keyboardNav && modelData.index === root.gridIndex
                        order: gallery.atYBeginning ? modelData.index : 0 // Scrolled to: no wait
                        onHoveredChanged: if (hovered) { root.gridIndex = modelData.index; root.keyboardNav = false; } // Keys go on from here
                        onClicked: root.viewerIndex = modelData.index
                        onRightClicked: root.copyEntry(modelData.entry)
                    }
                }
            }
        }
    }
    SheetEdgeFade {
        anchors { left: gallery.left; right: gallery.right; top: gallery.top }
        height: 20
        sheetColor: root.backgroundColor
        visible: gallery.visible
        active: !gallery.atYBeginning
    }
    SheetEdgeFade {
        anchors { left: gallery.left; right: gallery.right; bottom: gallery.bottom }
        height: 28; reversed: true
        sheetColor: root.backgroundColor
        visible: gallery.visible
        active: !gallery.atYEnd
    }

    SheetEmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 24
        visible: root.onShots && !root.viewing && root.paths.length === 0
        icon: root.loading ? "hourglass_empty" : "add_a_photo"
        text: root.loading ? Translation.tr("Looking for screenshots…") : Translation.tr("No screenshots yet")
        hint: root.loading ? ""
            : root.appid !== "" ? Translation.tr("Press F12 while playing to take one")
            : Translation.tr("Screenshots the game saves in its own folders show up here")
    }

    // ── Clips page ──
    ClipsPage {
        id: clipsPage
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: !root.onShots
        game: root.game
        active: root.shown && !root.onShots
    }

    // ── Viewer: the shot large, what it is under it, then a filmstrip ──
    Item {
        id: viewer
        anchors { top: header.bottom; topMargin: 14; bottom: details.top; bottomMargin: 12; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        visible: root.viewing
        readonly property string source: root.currentEntry !== "" ? root.sourceFor(root.currentEntry) : ""
        readonly property real aspect: root.aspectOf(root.currentEntry)
        // Stepping to another shot: the one before stays on top and fades out once the new one is decoded
        property string _last: ""
        onSourceChanged: {
            ghostFade.stop();
            ghost.source = fullImage.loadedOnce ? _last : "";
            ghost.opacity = 1;
            _last = source;
            // One shown before is still in the cache: it's Ready at once, with no status change to fade on
            Qt.callLater(() => { if (fullImage.status === Image.Ready) ghostFade.restart(); });
        }
        onVisibleChanged: if (!visible) { fullImage.loadedOnce = false; ghost.source = ""; _last = ""; }

        ClippingRectangle { // The picture's own rect, fitted from its known shape, so the rounding is on its corners
            id: picture
            anchors.centerIn: parent
            width: Math.round(Math.min(parent.width, parent.height * viewer.aspect))
            height: Math.round(width / viewer.aspect)
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            Image { // A small copy first (quick to decode), shown while the full size loads
                anchors.fill: parent
                source: viewer.source
                sourceSize.width: 480
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: fullImage.status !== Image.Ready
            }
            Image {
                id: fullImage
                anchors.fill: parent
                source: viewer.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true // The last one stays up (under the ghost) instead of flashing the small copy
                sourceSize.width: Math.ceil(width * 1.5) // Sharp at the panel's size without decoding 4K shots in full
                property bool loadedOnce: false
                onStatusChanged: if (status === Image.Ready) { loadedOnce = true; ghostFade.restart(); }
                opacity: loadedOnce ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            Image {
                id: ghost
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: fullImage.sourceSize.width // Same size as it was shown: still in the cache
                visible: source != "" && opacity > 0
                NumberAnimation on opacity { id: ghostFade; running: false; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
            MouseArea { // Click the picture to open it outside (image viewer, or its page in Immich)
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openExternally(root.currentEntry)
            }
            MaterialSymbol { // Not fetched from Immich yet, or unreadable
                anchors.centerIn: parent
                visible: viewer.source === "" || fullImage.status === Image.Error
                text: fullImage.status === Image.Error ? "broken_image" : "hourglass_empty"
                iconSize: 28
                color: Appearance.colors.colSubtext
            }
        }
        SheetNavButton { anchors { left: parent.left; verticalCenter: parent.verticalCenter } iconName: "chevron_left"; enabled: root.viewerIndex > 0; onClicked: root.viewerIndex-- }
        SheetNavButton { anchors { right: parent.right; verticalCenter: parent.verticalCenter } iconName: "chevron_right"; enabled: root.viewerIndex < root.paths.length - 1; onClicked: root.viewerIndex++ }
    }
    // When, how big, and where it is: a card as wide as the picture (wider only if its text needs it)
    Rectangle {
        id: details
        anchors {
            bottom: filmstrip.visible ? filmstrip.top : parent.bottom
            bottomMargin: filmstrip.visible ? 10 - filmstrip.pad : 16
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(parent.width - 40, Math.max(picture.width, dateText.implicitWidth + chips.implicitWidth + 40))
        height: 36
        radius: Appearance.rounding.container
        color: Appearance.colors.colLayer1
        visible: root.viewing
        readonly property var info: root._info[root.currentEntry] ?? ({})
        StyledText {
            id: dateText
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: {
                const t = details.info.time ?? 0;
                if (!(t > 0)) return "";
                const d = new Date(t * 1000);
                const date = d.toLocaleDateString(Qt.locale(), d.getFullYear() === new Date().getFullYear() ? "dddd, MMMM d" : "dddd, MMMM d, yyyy");
                return `${date} · ${root.timeLabel(t)}`;
            }
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        Row {
            id: chips
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 6
            SheetInfoChip {
                visible: (details.info.width ?? 0) > 0
                icon: "aspect_ratio"
                text: `${details.info.width} × ${details.info.height}`
            }
            SheetInfoChip {
                icon: details.info.remote ? "cloud" : "computer"
                text: details.info.remote ? Translation.tr("Immich") : Translation.tr("This PC")
            }
        }
    }
    ListView {
        id: filmstrip
        // `pad` bigger than the tiles all round, so the clip doesn't cut the current one's ring;
        // centred, as wide as its shots up to the panel's width
        anchors { bottom: parent.bottom; bottomMargin: 16 - pad; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width - 2 * (20 - pad), contentWidth + pad * 2)
        readonly property int pad: 4
        readonly property int tileHeight: 60
        height: tileHeight + pad * 2
        leftMargin: pad; rightMargin: pad
        visible: root.viewing && root.paths.length > 1 // One shot: nothing to pick between
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.paths
        // The current one slides to the middle
        currentIndex: root.viewerIndex
        highlightFollowsCurrentItem: true
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: width / 2 - 50
        preferredHighlightEnd: width / 2 + 50
        highlightMoveDuration: 260
        highlight: Item {}
        delegate: Item { // Full height with the tile centred: the view puts delegates at y 0, so a y on the tile itself is lost
            id: filmItem
            required property string modelData
            required property int index
            width: Math.round(Math.max(1, Math.min(2, root.aspectOf(modelData))) * filmstrip.tileHeight) // At least square, as the grid's
            height: filmstrip.height
            Tile {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: filmstrip.tileHeight
                entry: filmItem.modelData
                compact: true
                current: filmItem.index === root.viewerIndex
                onClicked: root.viewerIndex = filmItem.index
            }
        }
    }

    // ── Pieces ──
    // A rounded shot, decoded about at its own size. Hovered or current: an accent ring and, on the grid, a slight
    // zoom and when it was taken;
    // a cloud mark when it's from Immich. compact: the filmstrip's (smaller rounding, the others dimmed)
    component Tile: Item {
        id: tile
        property string entry
        property bool compact: false
        property bool current: false
        signal clicked()
        signal rightClicked()
        readonly property bool hovered: tileMa.containsMouse
        // Coming in: fades up into place, a little after the ones before it (the grid's, as the page opens)
        property int order: 0
        property real appear: compact ? 1 : 0
        opacity: appear
        transform: Translate { y: (1 - tile.appear) * 12 }
        SequentialAnimation {
            running: !tile.compact
            PauseAnimation { duration: Math.min(tile.order, 10) * 40 }
            NumberAnimation { target: tile; property: "appear"; to: 1; duration: 320; easing.type: Easing.OutCubic }
        }
        ClippingRectangle { // Rounded without an offscreen layer per tile
            id: frame
            anchors.fill: parent
            radius: tile.compact ? Appearance.rounding.small : Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            scale: tileMa.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Image {
                id: thumb
                anchors.fill: parent
                source: root.sourceFor(tile.entry)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(Math.ceil(frame.width / 64) * 64, Math.ceil(frame.height / 64) * 64) // Cropped to cover the tile
                opacity: status !== Image.Ready ? 0 : tile.compact && !tile.current && !tile.hovered ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: 180 } }
                scale: !tile.compact && (tile.hovered || tile.current) ? 1.04 : 1.0 // A slight zoom inside the frame (it clips)
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Rectangle { // A faint edge, so dark shots don't melt into the panel
                anchors.fill: parent
                radius: frame.radius
                color: "transparent"
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
                visible: thumb.status === Image.Ready
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                text: thumb.status === Image.Error ? "broken_image" : "hourglass_empty"
                iconSize: tile.compact ? 16 : 22
                color: Appearance.colors.colSubtext
            }
            Rectangle { // When it was taken, along the bottom while hovered (or the keyboard ring is on it)
                visible: !tile.compact
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 44
                opacity: (tile.hovered || tile.current) && thumb.status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: ColorUtils.transparentize("black", 0.4) }
                }
                StyledText {
                    anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 8 }
                    text: { // When: the day and the time (there are no day headings)
                        const t = root._info[tile.entry]?.time ?? 0;
                        return t > 0 ? `${root.dayLabel(t)} · ${root.timeLabel(t)}` : "";
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                    color: "white"
                }
            }
            Rectangle { // From the Immich album, not on disk
                anchors { right: parent.right; bottom: parent.bottom; margins: tile.compact ? 4 : 6 }
                visible: root.isRemote(tile.entry) && thumb.status === Image.Ready
                width: tile.compact ? 18 : 24; height: width
                radius: tile.compact ? Appearance.rounding.unsharpenmore : Appearance.rounding.chip
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.25)
                MaterialSymbol { anchors.centerIn: parent; text: "cloud"; iconSize: tile.compact ? 12 : 15; color: Appearance.colors.colOnLayer0 }
            }
        }
        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: frame.radius + 3
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
            opacity: tile.current || tile.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => mouse.button === Qt.RightButton ? tile.rightClicked() : tile.clicked()
        }
        CopiedBadge {
            anchors { top: parent.top; right: parent.right; margins: 8 }
            visible: !tile.compact
            shown: root.copiedEntry === tile.entry
        }
    }


}
