import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * The grid's tag filter: a panel growing up out of the launcher (LauncherTopPanel) from the tag button by
 * the sort one. Each tag is a banner of one of its games' art (ArtBanner, the one played last that has
 * banner art), its cover, the name and how many games have it; All games comes first. A tag with more games
 * stacks their covers behind its own and splits the banner's right half on a slant into their art. Picking one shows
 * only those (GameLauncherService.selectedTag) and closes the panel, All games (or the toolbar's ✕ by
 * the tag) shows everything. The one in use has the accent edge. Two rows show, more scroll. The bin on a
 * lit banner takes the tag off every game, on a second click. ←/→/↑/↓ move, Enter picks, Delete (twice)
 * removes, Esc closes.
 */
LauncherTopPanel {
    id: root
    panelWidth: 1100
    panelHeight: 300
    onShownChanged: if (shown) {
        grid.currentIndex = Math.max(0, entries.indexOf(GameLauncherService.selectedTag));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
        keyboardNav = false;
        keys.forceActiveFocus();
    }

    readonly property var entries: [""].concat(GameLauncherService.allTags) // "": All games
    // The keyboard's banner is only lit after a key press; the mouse lights the one it's over
    property bool keyboardNav: false
    // Each tag's games, played last first (its banner shows the first with art); redone as tagging changes
    readonly property var gamesByTag: {
        const _ = GameLauncherService.tagsRevision;
        const out = {};
        for (const id of Object.keys(GameLauncherService.tagsData)) {
            const g = GameLauncherService.gamesById[id];
            const tags = GameLauncherService.tagsData[id];
            if (!g || !Array.isArray(tags)) continue;
            for (const t of tags) (out[t] ?? (out[t] = [])).push(g);
        }
        for (const t of Object.keys(out)) out[t].sort((a, b) => (b.lastPlayed || 0) - (a.lastPlayed || 0));
        return out;
    }
    readonly property var recentGames: GameLauncherService.games.filter(g => g.lastPlayed > 0)
        .sort((a, b) => b.lastPlayed - a.lastPlayed).slice(0, 12)
    function bannerGame(games) { return games.find(g => GameLauncherService.bannerArt(g) !== "") ?? games[0] ?? null; }

    // A first press of the bin (or Delete) arms it; a second, within a few seconds, removes the tag
    property string armedTag: ""
    Timer { id: disarm; interval: 3000; onTriggered: root.armedTag = "" }
    function remove(tag) {
        if (!tag) return;
        if (root.armedTag === tag) { root.armedTag = ""; GameLauncherService.removeTagEverywhere(tag); }
        else { root.armedTag = tag; disarm.restart(); }
    }
    function pick(tag) {
        GameLauncherService.selectedTag = tag;
        root.closeRequested();
    }
    function moveTo(i) {
        grid.currentIndex = Math.max(0, Math.min(grid.count - 1, i));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
        root.keyboardNav = true;
    }

    Item { // Takes the keys while it's open (the search bar has them otherwise)
        id: keys
        focus: true
        Keys.onPressed: event => {
            const i = grid.currentIndex;
            const step = { [Qt.Key_Right]: 1, [Qt.Key_Left]: -1, [Qt.Key_Down]: grid.columns, [Qt.Key_Up]: -grid.columns }[event.key];
            if (step !== undefined) root.moveTo(i + step);
            else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) root.moveTo(event.key === Qt.Key_Home ? 0 : grid.count - 1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.pick(root.entries[i] ?? "");
            else if (event.key === Qt.Key_Delete) { root.keyboardNav = true; root.remove(root.entries[i]); }
            else if (event.key === Qt.Key_Escape) root.closeRequested();
            else return;
            event.accepted = true;
        }
    }

    // No header and no close: the toolbar's tag button that opened it closes it (and clears the tag), as Esc does

    GridView {
        id: grid
        // Three across, two rows in view: whole rows, none cut off
        anchors { fill: parent; margins: 14 }
        readonly property int columns: Math.max(1, Math.floor(width / 320))
        cellWidth: Math.floor(width / columns)
        cellHeight: Math.floor(height / 2)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        snapMode: GridView.SnapToRow
        model: root.entries
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (root.armedTag !== root.entries[currentIndex]) root.armedTag = ""
        delegate: Item {
            id: cell
            required property string modelData
            required property int index
            readonly property bool all: modelData === ""
            readonly property var games: all ? root.recentGames : (root.gamesByTag[modelData] ?? [])
            readonly property bool active: GameLauncherService.selectedTag === modelData
            readonly property bool lit: hover.hovered || (root.keyboardNav && grid.currentIndex === index)
            readonly property bool armed: !all && root.armedTag === modelData
            width: grid.cellWidth; height: grid.cellHeight
            ArtBanner {
                id: banner
                anchors { fill: parent; margins: 5 }
                game: root.bannerGame(cell.games)
                // The tag's other games: their covers stacked behind this one, their art in slanted slices beside its own
                readonly property var others: cell.games.filter(g => g !== game)
                moreCovers: others.map(g => GameLauncherService.localArt(g, "boxArt")).filter(a => a).slice(0, 3)
                moreArts: GameLauncherService.bannerArt(game) === "" ? []
                    : others.map(g => GameLauncherService.bannerArt(g)).filter(a => a).slice(0, 2)
                coverIcon: cell.all ? "apps" : "sell"
                // Lighter while lit: more of the art shows
                shadeMid: cell.lit ? 0.55 : 0.7
                shadeEnd: cell.lit ? 0.35 : 0.5
                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered && root.settled) { grid.currentIndex = cell.index; root.keyboardNav = false; }
                }
                TapHandler { onTapped: root.pick(cell.modelData) }
                Column {
                    anchors { left: parent.left; leftMargin: banner.coverEnd + 14; right: bin.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: cell.all ? Translation.tr("All games") : cell.modelData
                        font.pixelSize: Appearance.font.pixelSize.title; font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: {
                            if (cell.armed) return Translation.tr("Click again to remove");
                            const n = cell.all ? GameLauncherService.games.length : (GameLauncherService.tagCounts[cell.modelData] ?? 0);
                            return n === 1 ? Translation.tr("1 game") : Translation.tr("%1 games").arg(n);
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: cell.armed ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
                    }
                }
                RippleButton { // Take the tag off every game (a second click confirms), on the art: see-through
                    id: bin
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: cell.all ? 0 : 34; height: 34; padding: 0
                    focusPolicy: Qt.NoFocus
                    buttonRadius: Appearance.rounding.container
                    opacity: !cell.all && (cell.lit || cell.armed) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    colBackground: cell.armed ? ColorUtils.transparentize(Appearance.colors.colError, 0.75)
                        : ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, cell.armed ? 0.65 : 0.75)
                    colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.6)
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: cell.armed ? "delete_forever" : "delete"
                            iconSize: 18
                            color: cell.armed || bin.hovered ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                        }
                    }
                    StyledToolTip { text: cell.armed ? Translation.tr("Click again to remove") : Translation.tr("Remove from every game") }
                    onClicked: root.remove(cell.modelData)
                }
                Rectangle { // The one in use: the accent edge. The keyboard's: a faint one
                    anchors.fill: parent
                    radius: banner.radius
                    color: "transparent"
                    border.width: cell.active || (root.keyboardNav && grid.currentIndex === cell.index) ? 2 : 1
                    border.color: cell.active ? Appearance.colors.colPrimary
                        : root.keyboardNav && grid.currentIndex === cell.index ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.5)
                        : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                }
            }
        }
    }
    SheetEdgeFade {
        anchors { left: grid.left; right: grid.right; bottom: grid.bottom }
        height: 20; reversed: true
        sheetColor: root.backgroundColor
        active: !grid.atYEnd
    }
    SheetEmptyState {
        anchors { centerIn: parent; verticalCenterOffset: grid.cellHeight / 2 }
        visible: root.entries.length === 1
        icon: "sell"
        text: Translation.tr("No tags yet")
        hint: Translation.tr("Tag games from their page (the tag button under Play)")
    }
}
