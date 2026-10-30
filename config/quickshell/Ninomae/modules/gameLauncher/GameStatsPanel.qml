import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Library statistics, in the shell's squircle style: headline tiles (playtime, games played, installed, disk,
// ProtonDB of the whole library), then Most played · Recently played · Storage as cards that scroll inside
// the launcher's short, wide panel. Every game row opens that game's details.
Item {
    id: root
    signal backPressed()
    signal gameSelected(var game)
    property bool animationReady: false
    Component.onCompleted: { _animTimer.start(); _readDiskSizes(); _recompute(); }
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
    Process {
        id: diskProc
        stdout: StdioCollector {
            onStreamFinished: { try { root._diskSizes = JSON.parse(text); } catch (e) {} _statsDebounce.restart(); }
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
    readonly property real _leftoverTotal: _leftovers.reduce((t, e) => t + e.size, 0)
    property bool _showLeftovers: false
    Process {
        id: leftoversProc
        running: true
        command: ["python3", "-I", root._helper, "leftovers"]
        stdout: StdioCollector {
            onStreamFinished: {
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
        return GameLauncherService.games.find(g => g.id === "steam_" + e.appid) ?? { name: e.name, _placeholder: true };
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
        const mostPlayed = _top(rows.filter(r => r.minutes > 0), "minutes", 10);
        const recent = _top(rows.filter(r => r.last > 0), "last", 10);
        const biggest = _top(rows.filter(r => r.size > 0), "size", Infinity); // Every install: Storage scrolls
        const tierTotal = tierGames || 1;
        root._stats = {
            totalMin, total: games.length, installed, played, backlog, diskTotal, tierGames, recentTotalMin, recentGames,
            averageMin: played > 0 ? totalMin / played : 0,
            mostPlayed, maxMinutes: mostPlayed.length ? mostPlayed[0].minutes : 1,
            recent, biggest, maxSize: biggest.length ? biggest[0].size : 1,
            // Best to worst, the order _tierColors lists them in
            tiers: Object.keys(root._tierColors).filter(k => tiers[k]).map(k => ({ tier: k, count: tiers[k], fraction: tiers[k] / tierTotal }))
        };
    }

    // ─── Layout ───────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        // Header: back on the left (like the details panel), then the quick-setting dialogs' accent squircle,
        // title and one-line summary
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            RippleButton {
                implicitWidth: 36; implicitHeight: 36; padding: 0
                buttonRadius: Appearance.rounding.container
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                contentItem: Item { MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 18; color: Appearance.colors.colOnLayer2 } }
                onClicked: root.backPressed()
                StyledToolTip { text: Translation.tr("Back") }
            }
            QuickDialogHeader {
                icon: "insights"
                title: Translation.tr("Library statistics")
                subtitle: root._stats ? Translation.tr("%1 games  ·  %2 installed  ·  %3 played").arg(root._thousands(root._stats.total)).arg(root._stats.installed).arg(root._thousands(root._stats.played)) : ""
            }
        }

        // ── Headline numbers, as tiles ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root._stats !== null
            StatTile {
                order: 0
                iconName: "schedule"
                value: root._formatTime(root._stats?.totalMin ?? 0)
                label: Translation.tr("played in total")
            }
            StatTile {
                order: 1
                iconName: "sports_esports"
                value: root._thousands(root._stats?.played ?? 0)
                label: Translation.tr("games played  ·  avg %1").arg(root._formatTime(root._stats?.averageMin ?? 0))
            }
            StatTile { // What's installed and the room it takes (one tile: they were two for the same games)
                order: 2
                iconName: "download_done"
                value: String(root._stats?.installed ?? 0)
                label: Translation.tr("installed  ·  %1").arg(root._formatBytes(root._stats?.diskTotal ?? 0))
                       + ((root._stats?.backlog ?? 0) > 0 ? "  ·  " + Translation.tr("%1 never played").arg(root._stats.backlog) : "")
            }
            StatTile { // Recent activity, the Recently played card's numbers added up
                order: 3
                iconName: "history"
                value: root._formatTime(root._stats?.recentTotalMin ?? 0)
                label: (root._stats?.recentGames ?? 0) === 1 ? Translation.tr("last 2 weeks  ·  1 game")
                     : (root._stats?.recentGames ?? 0) > 1 ? Translation.tr("last 2 weeks  ·  %1 games").arg(root._stats.recentGames)
                     : Translation.tr("last 2 weeks")
            }
            StatTile { // ProtonDB of the whole library: one bar, the counts under it
                order: 4
                weight: 1.5
                iconName: "verified"
                label: (root._stats?.tierGames ?? 0) > 0
                       ? (root._stats?.tiers ?? []).map(t => t.count + " " + t.tier).join("  ·  ")
                       : Translation.tr("No games rated")
                Item { // The layout sizes this box and the Row only fills it: segments sized from a layout-managed
                    // Row changed its implicit width, which re-laid it out in a loop ("possible QQuickItem::polish() loop")
                    Layout.fillWidth: true
                    Layout.topMargin: 4; Layout.bottomMargin: 4
                    implicitHeight: 8
                    Rectangle { anchors.fill: parent; radius: 4; color: Appearance.colors.colLayer3; visible: (root._stats?.tierGames ?? 0) === 0 }
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
                                radius: 4
                                color: ColorUtils.mix(root._tierColors[modelData.tier] ?? Appearance.colors.colPrimary, Appearance.colors.colPrimary, 0.5)
                            }
                        }
                    }
                }
            }
        }

        // ── Lists: each scrolls inside its card ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            visible: root._stats !== null

            Card {
                order: 5
                iconName: "emoji_events"
                title: Translation.tr("Most played")
                StatList {
                    id: mostList
                    visible: count > 0
                    model: root._stats?.mostPlayed ?? []
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

            Card {
                order: 6
                iconName: "history"
                title: Translation.tr("Recently played")
                caption: Translation.tr("Last 2 weeks") // What the times on the right count
                StatList {
                    id: recentList
                    visible: count > 0
                    model: root._stats?.recent ?? []
                    delegate: GameRow {
                        required property var modelData
                        width: ListView.view.width
                        game: modelData.game
                        // Right: time played in the last two weeks (all-time is Most played's). Under the name: when,
                        // and the last session if the launcher saw it
                        subtitle: root._ago(modelData.last) + (modelData.sessionMin > 0 ? "  ·  " + Translation.tr("%1 session").arg(root._formatTime(modelData.sessionMin)) : "")
                        trailing: modelData.recentMin > 0 ? root._formatTime(modelData.recentMin) : ""
                    }
                }
                Empty { visible: recentList.count === 0; text: Translation.tr("Nothing played yet") }
            }

            // Every install, biggest first, or (Review) what uninstalled games left behind
            Card {
                order: 7
                iconName: "hard_drive"
                title: root._showLeftovers ? Translation.tr("Left behind") : Translation.tr("Storage")
                StatList {
                    id: storageList
                    visible: !root._showLeftovers && count > 0
                    model: root._showLeftovers ? [] : (root._stats?.biggest ?? [])
                    delegate: GameRow {
                        required property var modelData
                        width: ListView.view.width
                        game: modelData.game
                        trailing: root._formatBytes(modelData.size)
                        fraction: modelData.size / root._stats.maxSize
                    }
                }
                Empty { visible: storageList.count === 0 && !root._showLeftovers; text: Translation.tr("No install sizes found") }
                RippleButton { // "Left by N uninstalled games · size  Review"
                    Layout.fillWidth: true
                    implicitHeight: 36
                    visible: !root._showLeftovers && root._leftovers.length > 0
                    buttonRadius: Appearance.rounding.container
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

    // A headline number: accent squircle icon, the value and a label (extra content goes under them)
    component StatTile: Surface {
        id: tile
        property string iconName
        property string value
        property string label
        default property alias content: tileCol.data
        implicitHeight: 64
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12
            QuickDialogIcon { icon: tile.iconName; active: true } // Tinted, like the resource monitor's cards
            ColumnLayout {
                id: tileCol
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    visible: tile.value !== ""
                    text: tile.value
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tile.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // A card's list: fills what the card leaves, scrolls inside it
    component StatList: StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        animateAppearance: false // The model is replaced on every recompute: rows would pop in again
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
                    color: Appearance.colors.colLayer3
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
                    color: Appearance.colors.colLayer3
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
