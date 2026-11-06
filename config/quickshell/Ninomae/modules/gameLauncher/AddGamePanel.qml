import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

/**
 * Add a game: any installed app (a Flatpak, an AppImage with a desktop entry, an emulator) into the
 * library, as Steam's "Add a non-Steam game" does. A panel growing up out of the launcher
 * (LauncherTopPanel) from the toolbar's Add button. On top, the search and the filters: Games (desktop
 * entries that say they're games), All apps, and In your library (what's been added, with its art and
 * time played). Steam and Lutris, and their game shortcuts, are left out (those games are in already).
 * Picking an app adds it (GameLauncherService.addCustomGame), with art from SteamGridDB when there's a
 * key, and the panel stays open to add more. An added one opens its page; its bin takes it out again
 * (a second click confirms). ↑/↓/←/→ move, Enter adds or opens, Tab steps the filters, Delete (twice)
 * removes, Esc closes.
 */
LauncherTopPanel {
    id: root
    panelWidth: 1100
    panelHeight: 400 // Four rows and a half: the list shows it scrolls
    clipContent: true
    signal openGame(var game)
    onShownChanged: if (shown) {
        search.text = "";
        filter = games.length > 0 ? "games" : "all";
        grid.currentIndex = 0;
        armedId = "";
        search.forceActiveFocus();
    }

    // Apps that can be added: shown, with a command, and not Steam, Lutris or a shortcut into them
    readonly property var apps: {
        const added = {};
        for (const c of GameLauncherService.customGames) added[c.name] = c.id;
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || !e.command || e.command.length === 0) continue;
            const exec = e.command.join(" ");
            if (/steam:\/\/rungameid|lutris:rungame|^steam( |$)|\/steam( |$)/.test(exec)) continue;
            if (/^(net\.lutris\.Lutris|lutris|steam)(\.desktop)?$/.test(e.id)) continue;
            out.push({ entry: e, name: e.name, icon: e.icon ?? "", isGame: (e.categories ?? []).includes("Game"),
                       customId: added[e.name] ?? "", flatpak: /(^|\/)flatpak run/.test(exec) });
        }
        return out.sort((a, b) => (b.isGame - a.isGame) || a.name.localeCompare(b.name));
    }
    readonly property var games: apps.filter(a => a.isGame)
    // What's been added, as the library has it (its art and playtime), newest first
    readonly property var library: GameLauncherService.customGames.slice().reverse().map(c => ({
        name: c.name, icon: c.icon ?? "", customId: c.id, game: GameLauncherService._installedGamesMap[c.id] ?? null
    }))
    property string filter: "games" // games, all or added
    readonly property var filters: [
        { key: "games", label: Translation.tr("Games"), count: games.length },
        { key: "all", label: Translation.tr("All apps"), count: apps.length },
        { key: "added", label: Translation.tr("In your library"), count: library.length }
    ]
    readonly property var matches: { // The filter's list, as far as the search matches
        const list = filter === "added" ? library : filter === "games" ? games : apps;
        const q = search.text.trim().toLowerCase();
        return q === "" ? list : list.filter(a => a.name.toLowerCase().includes(q));
    }
    onMatchesChanged: grid.currentIndex = Math.max(0, Math.min(grid.currentIndex, matches.length - 1))

    function pick(item) {
        if (!item) return;
        if (item.customId) { // In already: its page
            const game = item.game ?? GameLauncherService._installedGamesMap[item.customId];
            if (game) root.openGame(game);
            return;
        }
        GameLauncherService.addCustomGame({ id: item.entry.id, name: item.entry.name, command: Array.from(item.entry.command),
                                            icon: item.entry.icon, workingDirectory: item.entry.workingDirectory });
    }
    // A first press of the bin (or Delete) arms it; a second, within a few seconds, takes the game out
    property string armedId: ""
    Timer { id: disarm; interval: 3000; onTriggered: root.armedId = "" }
    function remove(item) {
        if (!item?.customId) return;
        if (root.armedId === item.customId) { root.armedId = ""; GameLauncherService.removeCustomGame(item.customId); }
        else { root.armedId = item.customId; disarm.restart(); }
    }
    function stepFilter(dir) {
        const i = filters.findIndex(f => f.key === filter);
        filter = filters[(i + dir + filters.length) % filters.length].key;
        grid.currentIndex = 0;
    }

    // ── Search and filters, one row (no header and no close: the toolbar's + closes it, as Esc does) ──
    Row {
        id: topRow
        anchors { top: parent.top; topMargin: 16; horizontalCenter: parent.horizontalCenter }
        spacing: 12
        Rectangle {
            id: searchBox
            width: 360; height: 36
            radius: Appearance.rounding.segment
            color: search.activeFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: 140 } }
            MaterialSymbol {
                id: searchIcon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "search"; iconSize: 17
                color: search.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            }
            ToolbarTextField {
                id: search
                anchors { left: searchIcon.right; leftMargin: 6; right: parent.right; rightMargin: 8; top: parent.top; bottom: parent.bottom }
                padding: 0
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                colBackground: "transparent"
                placeholderText: Translation.tr("Search your apps")
                onTextChanged: grid.currentIndex = 0
                Keys.onPressed: event => {
                    const step = { [Qt.Key_Right]: 1, [Qt.Key_Left]: -1, [Qt.Key_Down]: grid.columns, [Qt.Key_Up]: -grid.columns }[event.key];
                    // ←/→ move the text cursor while there's text to move through
                    const inText = (event.key === Qt.Key_Left || event.key === Qt.Key_Right) && search.text !== "";
                    if (step !== undefined && !inText) {
                        grid.currentIndex = Math.max(0, Math.min(grid.count - 1, grid.currentIndex + step));
                        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.pick(root.matches[grid.currentIndex]);
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) root.stepFilter(event.key === Qt.Key_Tab ? 1 : -1);
                    else if (event.key === Qt.Key_Delete && search.text === "") root.remove(root.matches[grid.currentIndex]);
                    else if (event.key === Qt.Key_Escape) root.closeRequested();
                    else return;
                    event.accepted = true;
                }
            }
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: root.filters
                SheetFilterChip {
                    required property var modelData
                    label: modelData.count > 0 ? `${modelData.label}  ${modelData.count}` : modelData.label
                    on: root.filter === modelData.key
                    onPicked: { root.filter = modelData.key; grid.currentIndex = 0; search.forceActiveFocus(); }
                }
            }
        }
    }

    // ── The apps: neutral cards, three across ──
    GridView {
        id: grid
        anchors { top: topRow.bottom; topMargin: 14; bottom: parent.bottom; bottomMargin: 12; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16 }
        readonly property int columns: Math.max(1, Math.floor(width / 320))
        cellWidth: Math.floor(width / columns)
        cellHeight: 68
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.matches
        currentIndex: 0
        highlightMoveDuration: 0
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool added: modelData.customId !== ""
            readonly property var game: modelData.game ?? (added ? GameLauncherService._installedGamesMap[modelData.customId] ?? null : null)
            readonly property string cover: GameLauncherService.localArt(game, "boxArt")
            readonly property bool lit: cardHover.hovered || grid.currentIndex === index
            readonly property bool armed: added && root.armedId === modelData.customId
            width: grid.cellWidth; height: grid.cellHeight
            Rectangle {
                id: card
                anchors { fill: parent; margins: 4 }
                radius: Appearance.rounding.normal
                color: cell.lit ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) grid.currentIndex = cell.index }
                TapHandler { onTapped: root.pick(cell.modelData) }

                ClippingRectangle { // The game's cover once it's in and has one, else the app's icon on a squircle
                    id: lead
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: cell.cover !== "" ? 32 : 44; height: 44
                    radius: Appearance.rounding.small
                    color: cell.cover !== "" ? "transparent" : Appearance.colors.colLayer2
                    Image {
                        anchors.fill: parent
                        visible: cell.cover !== ""
                        source: cell.cover !== "" ? "file://" + cell.cover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(64, 88)
                    }
                    IconImage {
                        anchors.centerIn: parent
                        visible: cell.cover === ""
                        implicitSize: 28
                        source: Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                    }
                }
                Column {
                    anchors { left: lead.right; leftMargin: 12; right: trailing.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    StyledText {
                        width: parent.width
                        text: cell.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: {
                            if (cell.armed) return Translation.tr("Click again to take it out");
                            if (cell.added) {
                                const min = cell.game?.playtime ?? 0;
                                return min >= 60 ? Translation.tr("In your library · %1h played").arg(Math.round(min / 60))
                                    : min > 0 ? Translation.tr("In your library · %1m played").arg(min) : Translation.tr("In your library");
                            }
                            return [cell.modelData.isGame ? Translation.tr("Game") : Translation.tr("App"), cell.modelData.flatpak ? "Flatpak" : ""]
                                .filter(t => t).join(" · ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: cell.armed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                }
                Item { // Add (an accent chip while lit), or for one that's in, a check and its bin
                    id: trailing
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    width: cell.added ? bin.width : addChip.width
                    height: 30
                    Rectangle {
                        id: addChip
                        visible: !cell.added
                        anchors.verticalCenter: parent.verticalCenter
                        width: addRow.implicitWidth + 18; height: 28
                        radius: Appearance.rounding.segment
                        color: cell.lit ? Appearance.colors.colPrimary : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "add"; iconSize: 16
                                color: cell.lit ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cell.lit
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                    RippleButton { // Take it out of the library (a second click confirms)
                        id: bin
                        visible: cell.added
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30; padding: 0
                        focusPolicy: Qt.NoFocus
                        buttonRadius: Appearance.rounding.segment
                        colBackground: cell.armed ? ColorUtils.transparentize(Appearance.colors.colError, 0.8) : "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, cell.armed ? 0.7 : 0.82)
                        colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                // A check at rest: it's in. The bin while lit
                                text: cell.armed ? "delete_forever" : cell.lit ? "delete" : "check"
                                iconSize: 18
                                color: cell.armed || bin.hovered ? Appearance.colors.colError : Appearance.colors.colSubtext
                            }
                        }
                        StyledToolTip { text: cell.armed ? Translation.tr("Click again to take it out") : Translation.tr("Take it out of the library") }
                        onClicked: root.remove(cell.modelData)
                    }
                }
                Rectangle { // The keyboard's card: the accent ring
                    anchors.fill: parent
                    radius: card.radius
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                    visible: grid.currentIndex === cell.index && search.activeFocus && !cardHover.hovered && root.matches.length > 1
                    opacity: 0.6
                }
            }
        }
    }
    SheetEdgeFade {
        anchors { left: grid.left; right: grid.right; bottom: grid.bottom }
        height: 24; reversed: true
        sheetColor: root.backgroundColor
        active: !grid.atYEnd
    }
    SheetEmptyState {
        anchors.centerIn: grid
        visible: root.matches.length === 0
        icon: search.text !== "" ? "search_off" : root.filter === "added" ? "library_add" : "apps"
        text: search.text !== "" ? Translation.tr("No apps match")
            : root.filter === "added" ? Translation.tr("Nothing added yet") : Translation.tr("No games among your apps")
        hint: search.text === "" && root.filter !== "all" ? (root.filter === "added" ? Translation.tr("Pick an app under All apps to add it")
            : Translation.tr("Apps that say they're games show here. The rest are under All apps")) : ""
    }
}
