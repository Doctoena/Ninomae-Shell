import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * The Screenshots sheet's Clips page: the game's saved gameplay clips (services/GameClips.qml puts them
 * in <clips folder>/<game>/), newest first in a grid of 16:9 tiles with their length; clicking one plays
 * it in the sheet. scripts/clips/list_clips.py lists them and makes the thumbnails (cached).
 * Keys (from ScreenshotsPanel.handleKey): on the grid the arrows move a ring and Enter plays; in the player
 * Space plays/pauses, ←/→ jump 5 s, Page Up/Down go to the previous/next clip, Esc goes back to the grid.
 * Delete (twice) is the panel's: ScreenshotsPanel.requestTrash asks before trashCurrent.
 *
 * Trim (T, or the header's scissors): [ and ] mark where it starts and ends at the playhead, it loops
 * in that part, and Save makes it a new clip (scripts/clips/export_clip.py; the original is kept).
 * Copy (Ctrl+C, the header's button, or right-click on the grid) puts the clip on the clipboard as a
 * file, to paste into Discord or a file manager, as the screenshots' copy does.
 */
Item {
    id: root
    required property var game
    property bool active: false // The page is showing (the sheet is open on it)

    property var clips: [] // [{ path, time, duration, width, height, size, thumb }], newest first
    readonly property bool loading: lister.running && clips.length === 0
    property int playerIndex: -1
    readonly property bool viewing: playerIndex >= 0 && playerIndex < clips.length
    readonly property var current: viewing ? clips[playerIndex] : null
    readonly property string folder: GameClips.folderFor(game?.name ?? "")
    // The player (videoLoader), or a stopped stand-in while none is loaded, so everything can use it as is
    readonly property var video: videoLoader.item ?? idleVideo
    QtObject {
        id: idleVideo
        property real position: 0
        property real duration: 0
        readonly property int playbackState: MediaPlayer.StoppedState
        function play() {}
        function pause() {}
        function stop() {}
    }

    onActiveChanged: if (active) refresh(); else playerIndex = -1; // Leaving the player unloads it
    // What was found for it last time (GameLauncherService.clipsCache): opens filled in, looks again behind that
    onGameChanged: { clips = GameLauncherService.clipsCache[game?.id ?? ""] ?? []; playerIndex = -1; if (active) refresh(); }
    Component.onCompleted: clips = GameLauncherService.clipsCache[game?.id ?? ""] ?? []
    function refresh() {
        if (!game?.name) return;
        lister.running = false;
        lister.running = true;
    }
    Process {
        id: lister
        command: ["python3", "-I", Quickshell.shellPath("scripts/clips/list_clips.py"), root.folder,
                  `${GameLauncherService.cacheDir}/clip-thumbs`]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 7).map(f => ({
                    time: parseFloat(f[0]), duration: parseFloat(f[1]), width: parseInt(f[2]), height: parseInt(f[3]),
                    size: parseInt(f[4]), thumb: f[5], path: f.slice(6).join("\t")
                }));
                if (root.game?.id) GameLauncherService.clipsCache[root.game.id] = list;
                if (JSON.stringify(list) === JSON.stringify(root.clips)) return; // Unchanged: the grid isn't rebuilt
                // Stay on the one playing, or go to one just made (a trim)
                const cur = root._openAfterRefresh || (root.current?.path ?? "");
                root._openAfterRefresh = "";
                root.clips = list;
                if (cur !== "") root.playerIndex = Math.max(0, list.findIndex(c => c.path === cur));
            }
        }
    }

    // ── Actions ──
    function back() { playerIndex = -1; }
    function openFolder() { Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "open-folder", folder]); }
    function openExternally() { if (current) { root.video.pause(); Quickshell.execDetached(["xdg-open", current.path]); } }
    function trashCurrent() {
        if (!current) return;
        const i = playerIndex, path = current.path;
        root.video.stop();
        Quickshell.execDetached(["gio", "trash", "--", path]);
        clips = clips.filter(c => c.path !== path);
        if (game?.id) GameLauncherService.clipsCache[game.id] = clips; // Or it'd show again next time, for a moment
        playerIndex = clips.length === 0 ? -1 : Math.min(i, clips.length - 1);
    }
    function togglePlay() {
        if (root.video.playbackState === MediaPlayer.PlayingState) root.video.pause();
        else {
            if (root.video.duration > 0 && root.video.position >= root.video.duration - 50) root.video.position = 0; // Ended: from the start
            root.video.play();
        }
    }
    function seekBy(ms) { root.video.position = Math.max(0, Math.min(root.video.duration, root.video.position + ms)); }

    // ── Trim ──
    // Trimming: the part between trimStart and trimEnd (ms) is what Save keeps
    property bool trimming: false
    property real trimStart: 0
    property real trimEnd: 0
    readonly property real clipLength: root.video.duration > 0 ? root.video.duration : (current?.duration ?? 0) * 1000
    readonly property bool hasRange: trimming && (trimStart > 50 || trimEnd < clipLength - 50)
    function toggleTrim() {
        if (!current || exportKind !== "") return;
        trimming = !trimming;
        if (trimming) { trimStart = 0; trimEnd = clipLength; }
    }
    function markStart() { if (!trimming) toggleTrim(); trimStart = Math.max(0, Math.min(root.video.position, trimEnd - 500)); }
    function markEnd() { if (!trimming) toggleTrim(); trimEnd = Math.min(clipLength, Math.max(root.video.position, trimStart + 500)); }
    Connections { // While trimming, playing loops in the part kept
        target: root.video
        function onPositionChanged() {
            if (root.trimming && root.video.playbackState === MediaPlayer.PlayingState
                && (root.video.position >= root.trimEnd || root.video.position < root.trimStart - 250))
                root.video.position = root.trimStart;
        }
    }

    // Made by GameClips, so closing the launcher doesn't stop one halfway; this page shows how it's going
    readonly property string exportKind: GameClips.exportKind // "trim" while one is being made
    readonly property real exportProgress: GameClips.exportProgress
    property string _openAfterRefresh: ""
    Binding { target: GameClips; property: "pageOpen"; value: root.active } // It notifies only when no page shows it
    // What the last one made says, for a few seconds in the controls card
    property string status: ""
    property bool statusIsError: false
    Timer { id: statusTimer; interval: 5000; onTriggered: root.status = "" }
    function showStatus(text, isError) { status = text; statusIsError = isError; statusTimer.restart(); }
    function exportClip(kind) {
        if (!current || exportKind !== "") return;
        root.video.pause();
        const start = hasRange ? trimStart / 1000 : 0, end = hasRange ? trimEnd / 1000 : clipLength / 1000;
        status = "";
        GameClips.exportClip(kind, current.path, start, end);
    }
    Connections {
        target: GameClips
        function onExportFinished(kind, ok, message, path, bytes) {
            if (!ok) { root.showStatus(message, true); return; }
            root.trimming = false;
            root._openAfterRefresh = path; // The new clip, once the list has it
            root.refresh();
            root.showStatus(Translation.tr("Saved as a new clip"), false);
        }
    }

    // ── Copy: the clip as a file (text/uri-list), what file managers put on the clipboard ──
    property string copiedPath: "" // Its tick (header) or "Copied" badge (grid) for a moment
    readonly property bool copied: copiedPath !== "" && copiedPath === (current?.path ?? "")
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedPath = "" }
    function copyClip(path) {
        if (!path) return;
        copier.running = false;
        copier.path = path;
        copier.command = ["sh", "-c", 'printf "%s\r\n" "$1" | wl-copy --type text/uri-list', "copy-clip",
                          "file://" + path.split("/").map(encodeURIComponent).join("/")];
        copier.running = true;
    }
    Process {
        id: copier
        property string path
        onExited: exitCode => { if (exitCode === 0) { root.copiedPath = copier.path; copiedTimer.restart(); } }
    }

    // Keys from the sheet. Returns whether it used the key
    function handleKey(key, modifiers) {
        if (key === Qt.Key_C && (modifiers & Qt.ControlModifier)) { // The one playing, or the grid's ring/hovered one
            if (viewing) copyClip(current.path);
            else if (gridIndex >= 0 && gridIndex < clips.length) copyClip(clips[gridIndex].path);
            return true;
        }
        if (key === Qt.Key_Escape) {
            if (trimming) { trimming = false; return true; } // Out of trimming first
            if (viewing) { back(); return true; }
            return false;
        }
        if (viewing) {
            if (key === Qt.Key_Space) { togglePlay(); return true; }
            if (key === Qt.Key_T) { toggleTrim(); return true; }
            if (key === Qt.Key_BracketLeft) { markStart(); return true; }
            if (key === Qt.Key_BracketRight) { markEnd(); return true; }
            if (key === Qt.Key_Left || key === Qt.Key_Right) { seekBy(key === Qt.Key_Left ? -5000 : 5000); return true; }
            if (key === Qt.Key_PageUp) { playerIndex = Math.max(0, playerIndex - 1); return true; }
            if (key === Qt.Key_PageDown) { playerIndex = Math.min(clips.length - 1, playerIndex + 1); return true; }
            return key === Qt.Key_Up || key === Qt.Key_Down || key === Qt.Key_Return || key === Qt.Key_Enter;
        }
        const isArrow = key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Up || key === Qt.Key_Down;
        if (clips.length > 0 && isArrow) {
            if (!keyboardNav || gridIndex < 0) gridIndex = Math.max(0, Math.min(clips.length - 1, gridIndex));
            else if (key === Qt.Key_Left) gridIndex = Math.max(0, gridIndex - 1);
            else if (key === Qt.Key_Right) gridIndex = Math.min(clips.length - 1, gridIndex + 1);
            else gridIndex = Math.max(0, Math.min(clips.length - 1, gridIndex + (key === Qt.Key_Up ? -grid.columns : grid.columns)));
            keyboardNav = true;
            grid.positionViewAtIndex(gridIndex, GridView.Contain);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (keyboardNav && gridIndex >= 0 && gridIndex < clips.length) playerIndex = gridIndex;
            return true; // Not on to the details page (Enter there plays the game)
        }
        return isArrow;
    }
    property int gridIndex: -1
    property bool keyboardNav: false
    onPlayerIndexChanged: {
        trimming = false; // Another clip: its own range
        if (playerIndex >= 0) gridIndex = playerIndex;
    }

    // ── Labels ──
    function durationLabel(s) {
        const t = Math.max(0, Math.round(s));
        return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
    }
    function dateLabel(t) {
        if (!(t > 0)) return "";
        const d = new Date(t * 1000), now = new Date();
        const day = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
        const days = Math.round((day(now) - day(d)) / 86400000);
        const when = days === 0 ? Translation.tr("Today") : days === 1 ? Translation.tr("Yesterday")
            : days > 1 && days < 7 ? d.toLocaleDateString(Qt.locale(), "dddd")
            : d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "MMMM d" : "MMMM d, yyyy");
        return `${when} · ${d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)}`;
    }
    function sizeLabel(bytes) { return bytes >= 1e9 ? (bytes / 1e9).toFixed(1) + " GB" : Math.round(bytes / 1e6) + " MB"; }

    // ── Grid ──
    GridView {
        id: grid
        anchors { fill: parent; topMargin: 14 - pad; leftMargin: 20 - pad; rightMargin: 20 - pad }
        topMargin: pad; bottomMargin: 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: !root.viewing && root.clips.length > 0
        readonly property int pad: 4
        readonly property int gap: 8
        readonly property int columns: 4
        cellWidth: Math.floor((width - pad * 2) / columns)
        cellHeight: Math.round((cellWidth - gap) * 9 / 16) + gap
        leftMargin: pad
        model: root.clips
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            ClipTile {
                anchors { fill: parent; rightMargin: grid.gap; bottomMargin: grid.gap }
                clipData: cell.modelData
                order: grid.atYBeginning ? cell.index : 0
                current: root.keyboardNav && cell.index === root.gridIndex
                onHoveredChanged: if (hovered) { root.gridIndex = cell.index; root.keyboardNav = false; }
                onClicked: root.playerIndex = cell.index
                onRightClicked: root.copyClip(cell.modelData.path)
            }
        }
    }
    SheetEdgeFade {
        anchors { left: grid.left; right: grid.right; top: grid.top }
        height: 20
        sheetColor: Appearance.m3colors.m3background
        visible: grid.visible
        active: !grid.atYBeginning
    }
    SheetEdgeFade {
        anchors { left: grid.left; right: grid.right; bottom: grid.bottom }
        height: 28; reversed: true
        sheetColor: Appearance.m3colors.m3background
        visible: grid.visible
        active: !grid.atYEnd
    }
    SheetEmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -8
        visible: !root.viewing && root.clips.length === 0
        icon: root.loading ? "hourglass_empty" : "movie"
        text: root.loading ? Translation.tr("Looking for clips…") : Translation.tr("No clips yet")
        hint: root.loading ? ""
            : !GameClips.available ? Translation.tr("Install gpu-screen-recorder to record clips")
            : !(Config.options.gameLauncher.clipsEnabled ?? false) ? Translation.tr("Turn on clips in Settings → In game")
            : Translation.tr("Press %1 while playing to save the last %2").arg(GameClips.keyLabel).arg(GameClips.seconds >= 60
                ? (GameClips.seconds === 60 ? Translation.tr("minute") : Translation.tr("%1 minutes").arg(GameClips.seconds / 60))
                : Translation.tr("%1 seconds").arg(GameClips.seconds))
    }

    // ── Player ──
    Item {
        id: player
        anchors { top: parent.top; topMargin: 14; bottom: controls.top; bottomMargin: 12; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        visible: root.viewing
        readonly property real aspect: (root.current?.width ?? 0) > 0 && (root.current?.height ?? 0) > 0
            ? Math.max(0.5, Math.min(3, root.current.width / root.current.height)) : 16 / 9
        ClippingRectangle {
            id: screen
            anchors.centerIn: parent
            width: Math.round(Math.min(parent.width, parent.height * player.aspect))
            height: Math.round(width / player.aspect)
            radius: Appearance.rounding.normal
            color: "black"
            Image { // Its thumbnail until the first frame is up
                anchors.fill: parent
                source: root.current?.thumb ? "file://" + root.current.thumb : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: root.video.position === 0 && root.video.playbackState !== MediaPlayer.PlayingState
            }
            // Made only while a clip is open: the panel opens without building a media player
            Loader {
                id: videoLoader
                anchors.fill: parent
                active: root.viewing
                sourceComponent: Video {
                    source: root.current ? "file://" + root.current.path : ""
                    fillMode: VideoOutput.PreserveAspectFit
                    onSourceChanged: if (source != "") play()
                    Component.onCompleted: if (source != "") play()
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePlay()
            }
            Rectangle { // Paused or ended: a play mark in the middle
                anchors.centerIn: parent
                width: 64; height: 64
                radius: Appearance.rounding.container + 6
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.3)
                opacity: root.video.playbackState !== MediaPlayer.PlayingState ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.video.duration > 0 && root.video.position >= root.video.duration - 50 ? "replay" : "play_arrow"
                    fill: 1; iconSize: 34
                    color: Appearance.colors.colOnLayer0
                }
            }
        }
        SheetNavButton {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            iconName: "chevron_left"; enabled: root.playerIndex > 0
            onClicked: root.playerIndex--
        }
        SheetNavButton {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            iconName: "chevron_right"; enabled: root.playerIndex < root.clips.length - 1
            onClicked: root.playerIndex++
        }
    }
    // Play/pause, where it is, and what it is: a card as wide as the video
    Rectangle {
        id: controls
        anchors { bottom: parent.bottom; bottomMargin: 16; horizontalCenter: parent.horizontalCenter }
        width: Math.max(screen.width, 560)
        height: 44
        radius: Appearance.rounding.container
        color: Appearance.colors.colLayer1
        visible: root.viewing
        RippleButton {
            id: playButton
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            implicitWidth: 32; implicitHeight: 32
            buttonRadius: Appearance.rounding.segment
            focusPolicy: Qt.NoFocus
            colBackground: "transparent"
            onClicked: root.togglePlay()
            contentItem: Item {
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.video.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                    fill: 1; iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
        StyledText {
            id: timeText
            anchors { left: playButton.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            text: `${root.durationLabel(root.video.position / 1000)} / ${root.durationLabel((root.video.duration || (root.current?.duration ?? 0) * 1000) / 1000)}`
            font.pixelSize: Appearance.font.pixelSize.small
            font.features: { "tnum": 1 } // Digits keep their width as it counts
            color: Appearance.colors.colOnLayer1
        }
        StyledSlider {
            id: seek
            anchors { left: timeText.right; leftMargin: 12; right: chips.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            from: 0; to: 1
            value: root.video.duration > 0 ? root.video.position / root.video.duration : 0
            stopIndicatorValues: []
            tooltipContent: root.durationLabel(value * root.video.duration / 1000)
            focusPolicy: Qt.NoFocus
            onMoved: root.video.position = value * root.video.duration
        }
        // Trimming: the part kept, as a band over the bar, between two handles to drag. Dragging one
        // pauses and scrubs the video to it, so the cut lands on the frame you see; the rest of the bar
        // still seeks
        Item {
            id: range
            visible: root.trimming && root.clipLength > 0
            anchors.fill: parent
            function xOf(ms) { return seek.x + seek.handleMargins + ms / root.clipLength * seek.effectiveDraggingWidth; }
            function msAt(x) { return Math.max(0, Math.min(root.clipLength, (x - seek.x - seek.handleMargins) / seek.effectiveDraggingWidth * root.clipLength)); }
            Rectangle {
                x: range.xOf(root.trimStart); width: Math.max(2, range.xOf(root.trimEnd) - x)
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                radius: Appearance.rounding.unsharpenmore
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.78)
            }
            TrimHandle { isEnd: false }
            TrimHandle { isEnd: true }
        }
        // Right side: what's being made, what was just made, the trim controls, or the clip's details
        Item {
            id: chips
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            implicitWidth: (root.exportKind !== "" ? progressRow : root.status !== "" ? statusChip
                : root.trimming ? trimRow : detailsRow).implicitWidth
            implicitHeight: 28
            width: implicitWidth; height: implicitHeight
            Row { // Being made
                id: progressRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: root.exportKind !== ""
                spacing: 8
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Saving trim…") + `  ${Math.round(root.exportProgress * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer1
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110; height: 6; radius: 3
                    color: Appearance.colors.colLayer2
                    Rectangle {
                        width: parent.width * root.exportProgress; height: parent.height; radius: 3
                        color: Appearance.colors.colPrimary
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
            }
            Rectangle { // Just made (or why it couldn't be)
                id: statusChip
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: root.exportKind === "" && root.status !== ""
                implicitWidth: statusRow.implicitWidth + 16
                implicitHeight: 28
                radius: Appearance.rounding.chip
                color: root.statusIsError ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
                Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.statusIsError ? "error" : "check"; iconSize: 15
                        color: root.statusIsError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.status
                        width: Math.min(implicitWidth, 320); elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                        color: root.statusIsError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
                    }
                }
            }
            Row { // Trimming: set each end at the playhead, then save
                id: trimRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: root.exportKind === "" && root.status === "" && root.trimming
                spacing: 6
                ChipButton {
                    chipIcon: "first_page"; label: root.durationLabel(root.trimStart / 1000)
                    tip: Translation.tr("Start here ( [ )")
                    onClicked: root.markStart()
                }
                ChipButton {
                    chipIcon: "last_page"; label: root.durationLabel(root.trimEnd / 1000)
                    tip: Translation.tr("End here ( ] )")
                    onClicked: root.markEnd()
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("%1 s").arg(Math.round((root.trimEnd - root.trimStart) / 1000))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                ChipButton {
                    accent: true
                    enabled: root.hasRange
                    chipIcon: "content_cut"; label: Translation.tr("Save")
                    tip: Translation.tr("Save this part as a new clip (the original stays)")
                    onClicked: root.exportClip("trim")
                }
            }
            Row { // The clip's details
                id: detailsRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: root.exportKind === "" && root.status === "" && !root.trimming
                spacing: 6
                SheetInfoChip { icon: "schedule"; text: root.dateLabel(root.current?.time ?? 0) }
                SheetInfoChip { visible: (root.current?.size ?? 0) > 0; icon: "save"; text: root.sizeLabel(root.current?.size ?? 0) }
            }
        }
    }

    // ── Pieces ──
    // A clip's tile: its thumbnail, how long it is, and when on hover. Hovered or current: the accent ring
    // and a slight zoom, as the screenshot tiles
    component ClipTile: Item {
        id: tile
        property var clipData
        property bool current: false
        property int order: 0
        signal clicked()
        signal rightClicked()
        readonly property bool hovered: tileMa.containsMouse
        property real appear: 0
        opacity: appear
        transform: Translate { y: (1 - tile.appear) * 12 }
        SequentialAnimation {
            running: true
            PauseAnimation { duration: Math.min(tile.order, 10) * 40 }
            NumberAnimation { target: tile; property: "appear"; to: 1; duration: 320; easing.type: Easing.OutCubic }
        }
        ClippingRectangle {
            id: frame
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            scale: tileMa.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Image {
                id: thumb
                anchors.fill: parent
                source: tile.clipData?.thumb ? "file://" + tile.clipData.thumb : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 480
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                scale: tile.hovered || tile.current ? 1.04 : 1.0
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Rectangle { // A faint edge, so dark clips don't melt into the panel
                anchors.fill: parent
                radius: frame.radius
                color: "transparent"
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                text: "movie"
                iconSize: 22
                color: Appearance.colors.colSubtext
            }
            Rectangle { // When it was saved, along the bottom while hovered (or the keyboard ring is on it)
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 44
                opacity: tile.hovered || tile.current ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: ColorUtils.transparentize("black", 0.4) }
                }
                StyledText {
                    anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 8 }
                    text: root.dateLabel(tile.clipData?.time ?? 0)
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                    color: "white"
                }
            }
            Rectangle { // How long it is
                anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                implicitWidth: lengthRow.implicitWidth + 12
                implicitHeight: 24
                radius: Appearance.rounding.chip
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.25)
                Row {
                    id: lengthRow
                    anchors.centerIn: parent
                    spacing: 3
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "play_arrow"; fill: 1; iconSize: 14; color: Appearance.colors.colOnLayer0 }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.durationLabel(tile.clipData?.duration ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                }
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
            shown: root.copiedPath !== "" && root.copiedPath === tile.clipData?.path
        }
    }

    // One end of the trim range on the seek bar: a grip to drag (wider hit area than it looks)
    component TrimHandle: Item {
        id: th
        property bool isEnd: false
        readonly property real ms: isEnd ? root.trimEnd : root.trimStart
        readonly property bool engaged: thMa.containsMouse || thMa.pressed
        x: range.xOf(ms) - width / 2
        width: 20; height: parent.height
        Rectangle {
            anchors.centerIn: parent
            width: th.engaged ? 8 : 6; height: th.engaged ? 28 : 24
            radius: width / 2
            color: Appearance.colors.colPrimary
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Rectangle { // Grip line
                anchors.centerIn: parent
                width: 2; height: parent.height * 0.45; radius: 1
                color: Appearance.colors.colOnPrimary
                opacity: 0.8
            }
        }
        MouseArea {
            id: thMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            preventStealing: true
            onPressed: root.video.pause()
            onPositionChanged: mouse => {
                if (!pressed) return;
                const at = range.msAt(mapToItem(range, mouse.x, 0).x);
                if (th.isEnd) root.trimEnd = Math.max(root.trimStart + 500, at);
                else root.trimStart = Math.min(root.trimEnd - 500, at);
                root.video.position = th.ms; // Scrub: the frame where it cuts
            }
        }
    }

    // A chip you can press (the trim controls): neutral, or accent for the action
    component ChipButton: RippleButton {
        id: cb
        property string chipIcon
        property string label
        property string tip: ""
        property bool accent: false
        focusPolicy: Qt.NoFocus // The details page keeps the keys
        implicitWidth: cbRow.implicitWidth + 16
        implicitHeight: 28
        buttonRadius: Appearance.rounding.chip
        opacity: enabled ? 1 : 0.5
        colBackground: accent ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        colBackgroundHover: accent ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
        colRipple: accent ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
        contentItem: Item {
            Row {
                id: cbRow
                anchors.centerIn: parent
                spacing: 5
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cb.chipIcon; iconSize: 15
                    color: cb.accent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cb.label
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    color: cb.accent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
            }
        }
        StyledToolTip { text: cb.tip; visible: cb.tip !== "" && cb.hovered }
    }


}
