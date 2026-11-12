import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * The game page's Captures: a game's screenshots in a panel growing up out of the launcher (LauncherTopPanel): what the shell's
 * F12 and the overlay saved and the game's own screenshot folders (scripts/game-launcher/find_screenshots.py), newest
 * first, in 16:9 tiles four across as the Clips page's (other shapes cropped to fill them); clicking one
 * opens it large with its details joined under it and the others down its right. Keys come from the details page while it's
 * open (handleKey): on the grid the arrows (Home/End) move a ring and Enter opens that one; in the viewer
 * ←/→ (Home/End) step through and Delete, pressed twice, moves it to the Trash; Esc goes back to the grid, then closes.
 * What it found is kept per game for the session (GameLauncherService.screenshotsCache), so it opens
 * filled in and looks again behind that.
 *
 * With an Immich server set (Settings → Game Launcher), they upload there (all of them from the banner, the
 * one open from the viewer's banner button) into the game's album, and that album's photos show here too, by
 * date among the rest: all but the ones uploaded from here (same file name as one on disk), so each shows
 * once. Those are "immich:<asset id>" in paths, shown from copies scripts/game-launcher/immich_media.py
 * fetches; they can't be trashed from here.
 *
 * A banner of the game's art stays across the top throughout (each button names itself on hover): close (back
 * to the grid while one is open), the game's logo, the pages as joined tabs, Screenshots and Clips (ClipsPage.qml:
 * gameplay clips saved with the clip key; Tab flips between them), with their counts; on the right where the shots
 * are (with some of both) and the actions for what's showing (the grid: folder, Immich album, upload all; a shot:
 * copy, open, upload, Trash; a clip: trim, copy, open, back up, Trash). The grid's tiles are joined, and end in a
 * tile saying how to take more (CaptureAddTile). An open shot or clip has the others in a column on its right.
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
    onPageChanged: { _resetView(); GameLauncherService.screenshotsPage = page; trashArmed = false; }

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
        clipsPage.refresh(); // For the Clips tab's count, before its page is opened
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
        command: [Quickshell.shellPath("scripts/game-launcher/find_screenshots.py"), root.appid, root.game?.gameDir || "", root.game?.flatpakId || "",
                  root.game?.name || ""] // The name: where the shell saves them (game_screenshot.sh)
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
    // The panel is made anew each time it opens: a request still out when it closes is dropped, or its answer
    // would come back to a panel that's gone
    property var _requests: []
    Component.onDestruction: { for (const r of _requests) { r.dropped = true; r.xhr.abort(); } }
    function _immichRequest(method, path, body, failed, done) {
        const xhr = new XMLHttpRequest();
        const req = { xhr, dropped: false };
        _requests.push(req);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || req.dropped) return;
            _requests = _requests.filter(r => r !== req);
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
    // and a game's own folder may hold JPEGs. The tick/badge only shows once it's really copied
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
    // Trash asks twice: the first click (or Delete) arms it, red, and a second one within 4 s moves the shot or clip
    // to the Trash. Moving to another one, or waiting, puts it back
    property bool trashArmed: false
    function requestTrash() {
        if (!trashArmed) { trashArmed = true; trashDisarm.restart(); return; }
        trashArmed = false;
        if (onShots) trashCurrent(); else clipsPage.trashCurrent();
    }
    Timer { id: trashDisarm; interval: 4000; onTriggered: root.trashArmed = false }
    Connections { target: clipsPage; function onPlayerIndexChanged() { root.trashArmed = false; } }
    // To the Trash (so it can be got back)
    function trashCurrent() {
        const i = viewerIndex, path = currentEntry;
        if (isRemote(path)) return;
        Quickshell.execDetached(["gio", "trash", "--", path]);
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
    onViewerIndexChanged: {
        trashArmed = false;
        if (viewerIndex >= 0) { _lastViewed = viewerIndex; gridIndex = viewerIndex; } // The ring comes back on it
    }
    onViewingChanged: if (!viewing) gallery.positionViewAtIndex(_lastViewed, GridView.Contain)

    // Keys, from the details page's handler while this is open. Returns whether it used the key
    function handleKey(key, modifiers) {
        if (key === Qt.Key_Tab && !viewing && !clipsPage.viewing) { page = onShots ? "clips" : "shots"; return true; }
        if (key === Qt.Key_Delete && (onShots ? viewing && !currentIsRemote : clipsPage.viewing)) { requestTrash(); return true; }
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
            else if (key === Qt.Key_Up || key === Qt.Key_Down) gridIndex = Math.max(0, Math.min(paths.length - 1, gridIndex + (key === Qt.Key_Up ? -gallery.columns : gallery.columns)));
            else gridIndex = key === Qt.Key_Home ? 0 : paths.length - 1;
            keyboardNav = true;
            gallery.positionViewAtIndex(gridIndex, GridView.Contain);
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

    // ── Banner: the game's art across the top, carrying everything (each button says what it is on hover): close
    //    (back to the grid while one is open), the game's logo, the pages as joined tabs with their counts, then
    //    on the right where the shots are, the actions for what's showing, and Trash on its own ──
    Item {
        id: banner
        anchors { top: parent.top; topMargin: 14; left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 20 }
        height: 64
        readonly property int shotCount: root.localCount + root.remoteCount
        readonly property bool onGrid: root.onShots ? !root.viewing : !clipsPage.viewing
        function counted(name, n) { return n > 0 ? `${name} (${n})` : name; }

        ArtBanner {
            anchors.fill: parent
            game: root.game
            showCover: false
            shadeMid: 0.62; shadeEnd: 0.85 // Darker again on the right, under the buttons
        }
        SheetIconButton { // Close, or back to the grid
            id: closeButton
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            grouped: false
            iconName: banner.onGrid ? "close" : "arrow_back"
            tip: banner.onGrid ? Translation.tr("Close") : root.onShots ? Translation.tr("All screenshots") : Translation.tr("All clips")
            onClicked: {
                if (banner.onGrid) root.closeRequested();
                else if (root.onShots) root.viewerIndex = -1;
                else clipsPage.back();
            }
        }
        Image { // The game's logo, else its name
            id: bannerLogo
            anchors { left: closeButton.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
            readonly property string art: GameLauncherService.logoArt(root.game)
            source: art ? "file://" + art : ""
            height: 40
            width: status === Image.Ready ? Math.min(130, Math.round(height * implicitWidth / Math.max(1, implicitHeight))) : 0
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.height: 80
        }
        StyledText {
            id: bannerName
            visible: bannerLogo.width === 0
            anchors { left: closeButton.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
            width: visible ? Math.min(implicitWidth, 200) : 0
            elide: Text.ElideRight
            text: root.game?.name ?? ""
            font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        Row { // The pages
            anchors { left: bannerLogo.width > 0 ? bannerLogo.right : bannerName.right; leftMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 3
            PageTab { // Also the way back to all of them from the viewer
                first: true
                tabIcon: "photo_library"; label: Translation.tr("Screenshots"); count: banner.shotCount
                on: root.onShots
                onClicked: { if (root.onShots) root.viewerIndex = -1; else root.page = "shots"; }
            }
            PageTab {
                last: true
                tabIcon: "movie"; label: Translation.tr("Clips"); count: clipsPage.clips.length
                on: !root.onShots
                onClicked: { if (!root.onShots) clipsPage.back(); else root.page = "clips"; }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            ActionGroup { // Where the shots are: only with some of both
                visible: root.onShots && !root.viewing && root.localCount > 0 && root.remoteCount > 0
                SheetIconButton {
                    joined: true; across: true
                    iconName: "apps"; active: root.filter === "all"
                    tip: banner.counted(Translation.tr("Everywhere"), banner.shotCount)
                    onClicked: root.filter = "all"
                }
                SheetIconButton {
                    joined: true; across: true
                    iconName: "computer"; active: root.filter === "local"
                    tip: banner.counted(Translation.tr("On this PC"), root.localCount)
                    onClicked: root.filter = "local"
                }
                SheetIconButton {
                    joined: true; across: true
                    iconName: "cloud"; active: root.filter === "immich"
                    tip: banner.counted(Translation.tr("In Immich"), root.remoteCount)
                    onClicked: root.filter = "immich"
                }
            }
            ActionGroup { // The actions for what's showing
                // ── The grid ──
                SheetIconButton { // Screenshots: the folder the newest one on disk is in, else where they go (made if missing)
                    joined: true; across: true
                    visible: banner.onGrid && (root.onShots ? root.localPaths.length > 0 || root.screenshotFolder !== "" : true)
                    iconName: "folder_open"
                    tip: root.onShots ? Translation.tr("Open screenshots folder") : Translation.tr("Open clips folder")
                    onClicked: {
                        if (!root.onShots) { clipsPage.openFolder(); return; }
                        Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "open-folder",
                            root.localPaths.length > 0 ? root.localPaths[0].replace(/\/[^/]*$/, "") : root.screenshotFolder]);
                    }
                }
                SheetIconButton {
                    joined: true; across: true
                    visible: banner.onGrid && root.onShots && root.immichAlbumId !== "" && GameLauncherService.immichReady
                    iconName: "photo_album"; tip: Translation.tr("Open album in Immich")
                    onClicked: Quickshell.execDetached(["xdg-open", `${GameLauncherService.immichUrl}/albums/${root.immichAlbumId}`])
                }
                // ── A shot ──
                SheetIconButton {
                    joined: true; across: true
                    visible: root.onShots && root.viewing
                    iconName: root.copied ? "check" : "content_copy"
                    tip: root.copied ? Translation.tr("Copied") : Translation.tr("Copy image (Ctrl+C)")
                    onClicked: root.copyCurrent()
                }
                SheetIconButton {
                    joined: true; across: true
                    visible: root.onShots && root.viewing
                    iconName: "open_in_new"
                    tip: root.currentIsRemote ? Translation.tr("Open in Immich") : Translation.tr("Open in image viewer")
                    onClicked: root.openExternally(root.currentEntry)
                }
                // ── A clip ──
                SheetIconButton {
                    joined: true; across: true
                    visible: !root.onShots && clipsPage.viewing
                    enabled: clipsPage.exportKind === ""
                    active: clipsPage.trimming
                    iconName: "content_cut"; tip: clipsPage.trimming ? Translation.tr("Stop trimming (T)") : Translation.tr("Trim (T)")
                    onClicked: clipsPage.toggleTrim()
                }
                SheetIconButton {
                    joined: true; across: true
                    visible: !root.onShots && clipsPage.viewing
                    iconName: clipsPage.copied ? "check" : "content_copy"
                    tip: clipsPage.copied ? Translation.tr("Copied") : Translation.tr("Copy clip (Ctrl+C)")
                    onClicked: clipsPage.copyClip(clipsPage.current?.path ?? "")
                }
                SheetIconButton {
                    joined: true; across: true
                    visible: !root.onShots && clipsPage.viewing
                    iconName: "open_in_new"; tip: Translation.tr("Open in video app")
                    onClicked: clipsPage.openExternally()
                }
                // ── Immich: on the grid all of them (not the album's own photos: they're there already), else the
                //    one open. Clips are "backed up" ──
                SheetIconButton {
                    joined: true; across: true
                    readonly property var files: root.onShots ? (root.viewing ? [root.currentEntry] : root.localPaths)
                        : (clipsPage.viewing ? [clipsPage.current?.path ?? ""] : clipsPage.clips.map(c => c.path))
                    readonly property string uploadState: GameLauncherService.immichUploadState
                    visible: GameLauncherService.immichReady && files.length > 0 && !(root.onShots && root.currentIsRemote)
                    enabled: uploadState !== "uploading"
                    iconName: ({ uploading: "hourglass_top", done: "check", failed: "error" })[uploadState] ?? "cloud_upload"
                    tip: uploadState === "uploading" ? Translation.tr("Uploading to Immich…")
                        : uploadState === "failed" ? Translation.tr("Upload failed")
                        : banner.onGrid ? (root.onShots ? Translation.tr("Upload all %1 to Immich") : Translation.tr("Back up all %1 to Immich")).arg(files.length)
                        : (root.onShots ? Translation.tr("Upload to Immich") : Translation.tr("Back up to Immich"))
                    onClicked: GameLauncherService.uploadToImmich(files, root.game?.name ?? "")
                }
            }
            ActionGroup { // Trash, apart from the rest: the shot or clip open (not an Immich photo), asked twice
                visible: root.onShots ? root.viewing && !root.currentIsRemote : clipsPage.viewing
                SheetIconButton {
                    joined: true; across: true
                    danger: true
                    active: root.trashArmed
                    iconName: root.trashArmed ? "delete_forever" : "delete"
                    tip: root.trashArmed ? Translation.tr("Click again to move to Trash") : Translation.tr("Move to Trash (Delete)")
                    onClicked: root.requestTrash()
                }
            }
        }
    }
    // A group of the banner's buttons (each `joined: true; across: true`): each its own square, 3 px apart, rounded at
    // the group's ends. With none of them shown it's 0 wide, which the Row skips (not hidden: its buttons would then
    // count as hidden too, and it'd never come back)
    component ActionGroup: Row {
        spacing: 3
    }
    // A page of the banner: its icon, name and count (quiet), joined to the other; the open one tinted
    component PageTab: RippleButton {
        id: tab
        property string tabIcon
        property string label
        property int count: 0
        property bool on: false
        property bool first: false
        property bool last: false
        focusPolicy: Qt.NoFocus // The details page keeps the keys
        implicitWidth: tabRow.implicitWidth + 24
        implicitHeight: 36
        buttonRadiusLeft: first ? Appearance.rounding.small : Appearance.rounding.joined
        buttonRadiusRight: last ? Appearance.rounding.small : Appearance.rounding.joined
        colBackground: on ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
        colBackgroundHover: on ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        contentItem: Item {
            Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.tabIcon; iconSize: 17; fill: tab.on ? 1 : 0
                    color: tab.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.label
                    font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.DemiBold
                    color: tab.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tab.count > 0
                    text: tab.count
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Grid: the shots in 16:9 tiles, four across, as the Clips page's (CaptureGrid; shots of another shape
    //    are cropped to fill theirs, the viewer shows them whole) ──
    CaptureGrid {
        id: gallery
        anchors { top: banner.bottom; topMargin: 12 - pad; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 20 - pad; rightMargin: 20 - pad }
        visible: root.onShots && !root.viewing && root.paths.length > 0
        model: root.paths.length > 0 ? root.paths.concat([""]) : [] // Last, how to take more ("")
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: gallery.cellWidth; height: gallery.cellHeight
            Loader { // Only the tile it shows
                anchors { fill: parent; rightMargin: gallery.gap; bottomMargin: gallery.gap }
                sourceComponent: cell.modelData === "" ? howToTile : shotTile
            }
            Component {
                id: howToTile
                CaptureAddTile {
                    icon: "add_a_photo"
                    text: Translation.tr("Press F12 while playing to take one")
                    topLeftRadius: gallery.corner(cell.index, "tl"); topRightRadius: gallery.corner(cell.index, "tr")
                    bottomLeftRadius: gallery.corner(cell.index, "bl"); bottomRightRadius: gallery.corner(cell.index, "br")
                }
            }
            Component {
                id: shotTile
                Tile {
                    entry: cell.modelData
                    tl: gallery.corner(cell.index, "tl"); tr: gallery.corner(cell.index, "tr")
                    bl: gallery.corner(cell.index, "bl"); br: gallery.corner(cell.index, "br")
                    current: root.keyboardNav && cell.index === root.gridIndex
                    order: gallery.atYBeginning ? cell.index : 0 // Scrolled to: no wait
                    onHoveredChanged: if (hovered && root.settled) { root.gridIndex = cell.index; root.keyboardNav = false; } // Keys go on from here
                    onClicked: root.viewerIndex = cell.index
                    onRightClicked: root.copyEntry(cell.modelData)
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
        anchors.verticalCenterOffset: (banner.height + 14) / 2 // In the room under the banner
        visible: root.onShots && !root.viewing && root.paths.length === 0
        icon: root.loading ? "hourglass_empty" : "add_a_photo"
        text: root.loading ? Translation.tr("Looking for screenshots…") : Translation.tr("No screenshots yet")
        hint: root.loading ? "" : Translation.tr("Press F12 while playing to take one") // Any game's, as the grid's last tile
    }

    // ── Clips page ──
    ClipsPage {
        id: clipsPage
        settled: root.settled
        anchors { top: banner.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: !root.onShots
        game: root.game
        active: root.shown && !root.onShots
    }

    // ── Viewer: the shot large under the banner, what it is joined under it, the others down the right ──
    Item {
        id: stage
        anchors { top: banner.bottom; topMargin: 12; bottom: parent.bottom; bottomMargin: 16; left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 20 }
    }
    Item {
        id: viewer
        anchors { top: stage.top; bottom: stage.bottom; bottomMargin: 36 + 3; left: stage.left
                  right: filmstrip.visible ? filmstrip.left : stage.right; rightMargin: filmstrip.visible ? 12 : 0 }
        visible: root.viewing
        readonly property string source: root.currentEntry !== "" ? root.sourceFor(root.currentEntry) : ""
        readonly property real aspect: root.aspectOf(root.currentEntry)
        // The size a shot is shown at in this frame, and decoded at: from the target size, never the animating one,
        // so the picture's size easing between shapes doesn't decode it again on the way (in steps, a little sharper
        // than shown, without decoding a 4K shot in full)
        function shownWidth(entry) { return Math.round(Math.min(width, height * root.aspectOf(entry))); }
        function decodeWidth(entry) { return Math.ceil(shownWidth(entry) * 1.5 / 256) * 256; }
        // Stepping to another shot: the one before stays on top while the new one decodes, then the new one slides
        // in from the side it's on as the old one slides out the other way and fades
        property string _last: ""
        property string _lastEntry: ""
        property string _ghostEntry: "" // The one the ghost shows, for its decode size (so it's the cached copy)
        property int _lastIndex: -1
        property int _dir: 1 // +1: moved on (it comes in from the right), -1: back
        property bool _revealed: false // Once per shot: a second start would jump it back mid-slide
        readonly property real slide: 48
        onSourceChanged: {
            enter.stop(); ghostFade.stop();
            _revealed = false;
            // From viewerIndex itself: it's already the new one here (a binding on it might not be yet)
            _dir = root.viewerIndex >= _lastIndex ? 1 : -1;
            _lastIndex = root.viewerIndex;
            _ghostEntry = _lastEntry;
            ghost.source = fullImage.loadedOnce ? _last : "";
            ghost.opacity = 1; ghost.shift = 0;
            _last = source;
            _lastEntry = root.currentEntry;
            // One shown before (or preloaded) is in the cache: Ready at once, with no status change to start on
            Qt.callLater(() => { if (fullImage.status === Image.Ready) viewer.reveal(); });
        }
        function reveal() {
            if (_revealed) return;
            _revealed = true;
            if (ghost.source == "") return; // The first one: it just fades in
            fullImage.shift = _dir * slide;
            enter.restart(); ghostFade.restart();
        }
        onVisibleChanged: if (!visible) { fullImage.loadedOnce = false; ghost.source = ""; _last = ""; _lastEntry = ""; _lastIndex = -1; }

        // The shots either side, decoded ahead at the size they'll be shown at, so stepping to them is instant
        Preload { offset: -1 }
        Preload { offset: 1 }
        component Preload: Image {
            property int offset
            readonly property int at: root.viewerIndex + offset
            readonly property string entry: root.viewing && at >= 0 && at < root.paths.length ? root.paths[at] : ""
            visible: false
            asynchronous: true
            source: entry !== "" ? root.sourceFor(entry) : ""
            sourceSize.width: entry !== "" ? viewer.decodeWidth(entry) : 0
        }

        ClippingRectangle { // The picture's own rect, fitted from its known shape, so the rounding is on its corners
            id: picture
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom } // On its details
            // Eased between shots of different shapes instead of snapping
            width: viewer.shownWidth(root.currentEntry)
            height: Math.round(viewer.shownWidth(root.currentEntry) / viewer.aspect)
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            topLeftRadius: Appearance.rounding.small; topRightRadius: Appearance.rounding.small
            bottomLeftRadius: Appearance.rounding.joined; bottomRightRadius: Appearance.rounding.joined
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
                sourceSize.width: viewer.decodeWidth(root.currentEntry)
                property bool loadedOnce: false
                property real shift: 0
                transform: Translate { x: fullImage.shift }
                onStatusChanged: if (status === Image.Ready) { loadedOnce = true; viewer.reveal(); }
                opacity: loadedOnce ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                NumberAnimation on shift { id: enter; running: false; to: 0; duration: 280; easing.type: Easing.OutCubic }
            }
            Image {
                id: ghost
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: viewer.decodeWidth(viewer._ghostEntry) // Same size as it was shown: still in the cache
                visible: source != "" && opacity > 0
                property real shift: 0
                transform: Translate { x: ghost.shift }
                ParallelAnimation {
                    id: ghostFade
                    NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ghost; property: "shift"; to: -viewer._dir * viewer.slide; duration: 280; easing.type: Easing.OutCubic }
                }
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
        SheetNavButton { anchors { left: picture.left; leftMargin: 10; verticalCenter: picture.verticalCenter } iconName: "chevron_left"; enabled: root.viewerIndex > 0; onClicked: root.viewerIndex-- }
        SheetNavButton { anchors { right: picture.right; rightMargin: 10; verticalCenter: picture.verticalCenter } iconName: "chevron_right"; enabled: root.viewerIndex < root.paths.length - 1; onClicked: root.viewerIndex++ }
    }
    // When, how big, and where it is: joined pieces under the picture, as wide as it (wider only if the text needs it)
    Row {
        id: details
        anchors.horizontalCenter: viewer.horizontalCenter
        y: viewer.y + picture.y + picture.height + 3 // Under the picture (inside the viewer: not anchorable from here)
        visible: root.viewing
        spacing: 3
        readonly property var info: root._info[root.currentEntry] ?? ({})
        readonly property real chipsWidth: indexPiece.width + sizePiece.width + wherePiece.width + 3 * (sizePiece.visible ? 3 : 2)
        width: Math.min(viewer.width, Math.max(picture.width, dateText.implicitWidth + 28 + chipsWidth))
        Rectangle { // The date fills what the chips leave
            width: details.width - details.chipsWidth
            height: 36
            color: Appearance.colors.colLayer3
            topLeftRadius: Appearance.rounding.joined; topRightRadius: Appearance.rounding.joined
            bottomLeftRadius: Appearance.rounding.small; bottomRightRadius: Appearance.rounding.joined
            StyledText {
                id: dateText
                anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: {
                    const t = details.info.time ?? 0;
                    if (!(t > 0)) return "";
                    const d = new Date(t * 1000);
                    const date = d.toLocaleDateString(Qt.locale(), d.getFullYear() === new Date().getFullYear() ? "dddd, MMMM d" : "dddd, MMMM d, yyyy");
                    return `${date} · ${root.timeLabel(t)}`;
                }
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnLayer3
            }
        }
        InfoPiece { // Which one of them
            id: indexPiece
            icon: "photo_library"
            text: Translation.tr("%1 of %2").arg(root.viewerIndex + 1).arg(root.paths.length)
        }
        InfoPiece {
            id: sizePiece
            visible: (details.info.width ?? 0) > 0
            icon: "aspect_ratio"
            text: `${details.info.width} × ${details.info.height}`
        }
        InfoPiece {
            id: wherePiece
            last: true
            icon: details.info.remote ? "cloud" : "computer"
            text: details.info.remote ? Translation.tr("Immich") : Translation.tr("This PC")
        }
    }
    // A detail under the picture: icon and text, joined to the pieces beside it (last: the group's bottom-right corner)
    component InfoPiece: Rectangle {
        id: piece
        property string icon
        property string text
        property bool last: false
        width: visible ? pieceRow.implicitWidth + 24 : 0
        height: 36
        color: Appearance.colors.colLayer3
        topLeftRadius: Appearance.rounding.joined; topRightRadius: Appearance.rounding.joined
        bottomLeftRadius: Appearance.rounding.joined; bottomRightRadius: last ? Appearance.rounding.small : Appearance.rounding.joined
        Row {
            id: pieceRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: piece.icon; iconSize: 15; color: Appearance.colors.colSubtext }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: piece.text
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer3
            }
        }
    }
    // The others, down the right as a joined column: the open one ringed, slid to the middle
    ListView {
        id: filmstrip
        anchors { top: stage.top; bottom: stage.bottom; right: stage.right }
        width: 150
        readonly property int tileHeight: Math.round(width * 9 / 16)
        visible: root.viewing && root.paths.length > 1 // One shot: nothing to pick between
        orientation: ListView.Vertical
        spacing: 3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.paths
        currentIndex: root.viewerIndex
        highlightFollowsCurrentItem: true
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height / 2 - tileHeight
        preferredHighlightEnd: height / 2 + tileHeight
        highlightMoveDuration: 260
        highlight: Item {}
        delegate: Tile {
            id: filmItem
            required property string modelData
            required property int index
            width: filmstrip.width
            height: filmstrip.tileHeight
            entry: filmItem.modelData
            compact: true
            current: filmItem.index === root.viewerIndex
            tl: index === 0 ? Appearance.rounding.small : Appearance.rounding.joined; tr: tl
            bl: index === root.paths.length - 1 ? Appearance.rounding.small : Appearance.rounding.joined; br: bl
            onClicked: root.viewerIndex = filmItem.index
        }
    }

    // ── Pieces ──
    // A rounded shot, decoded about at its own size. Hovered or current: an accent ring and, on the grid, a slight
    // zoom and when it was taken;
    // a cloud mark when it's from Immich. compact: the filmstrip's (the others dimmed). Its corners are its group's
    // (joined: rounded only at the group's own corners); the ring is drawn inside it, clear of the ones beside it
    component Tile: Item {
        id: tile
        property string entry
        property bool compact: false
        property bool current: false
        property real tl: Appearance.rounding.small
        property real tr: Appearance.rounding.small
        property real bl: Appearance.rounding.small
        property real br: Appearance.rounding.small
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
            topLeftRadius: tile.tl; topRightRadius: tile.tr; bottomLeftRadius: tile.bl; bottomRightRadius: tile.br
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
                topLeftRadius: tile.tl; topRightRadius: tile.tr; bottomLeftRadius: tile.bl; bottomRightRadius: tile.br
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
        Rectangle { // The ring
            anchors.fill: parent
            topLeftRadius: tile.tl; topRightRadius: tile.tr; bottomLeftRadius: tile.bl; bottomRightRadius: tile.br
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
