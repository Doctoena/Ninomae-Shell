import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell.Widgets

/**
 * The grid's tag filter: a panel growing up out of the launcher (LauncherTopPanel) from the tag button by
 * the sort one. A grid of compact tiles, All games first, then a tile per tag with a few of its games'
 * covers and how many have it; picking one shows only those (GameLauncherService.selectedTag) and closes
 * the panel, All games (or the toolbar's ✕ by the tag) shows everything. The one in use is the accent
 * one. Three rows show, more scroll. The bin on a lit tile takes the tag off every game, on a second
 * click. ←/→/↑/↓ move, Enter picks, Delete (twice) removes, Esc closes.
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
    // The keyboard's tile is only lit after a key press; the mouse lights the one it's over
    property bool keyboardNav: false
    // Up to three covers per tag (the custom ones where set, else the library's), in one pass over the
    // games; redone when tags or art change, so the tiles follow tagging while the panel is open
    readonly property var covers: {
        const _ = [GameLauncherService.tagsRevision, GameLauncherService.customArtRevision];
        const out = {};
        for (const g of GameLauncherService.games) {
            const gameTags = GameLauncherService.tagsData[g.id];
            if (!Array.isArray(gameTags)) continue;
            const art = GameLauncherService.customArt[g.id]?.boxArt || g.boxArt || "";
            if (!art.startsWith("/")) continue;
            for (const t of gameTags) {
                const list = out[t] ?? (out[t] = []);
                if (list.length < 3) list.push(art);
            }
        }
        return out;
    }
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
        // Four across (fewer on a narrow launcher), three rows in view: whole rows, none cut off
        anchors { fill: parent; topMargin: 14; bottomMargin: 14; leftMargin: 14; rightMargin: 14 }
        readonly property int columns: Math.max(1, Math.floor(width / 250))
        cellWidth: Math.floor(width / columns)
        cellHeight: Math.floor(height / 3)
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
            readonly property bool active: GameLauncherService.selectedTag === modelData
            readonly property bool lit: tileHover.hovered || (root.keyboardNav && grid.currentIndex === index)
            readonly property bool armed: !all && root.armedTag === modelData
            readonly property var covers: all ? [] : (root.covers[modelData] ?? [])
            width: grid.cellWidth; height: grid.cellHeight
            Rectangle {
                id: tile
                anchors { fill: parent; margins: 4 }
                radius: Appearance.rounding.normal
                // The one in use: the accent squircle (accent = active); the rest neutral, a step up when lit
                color: cell.active ? (cell.lit ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                    : cell.lit ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: 140 } }
                readonly property color ink: cell.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                readonly property color subInk: cell.active ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2) : Appearance.colors.colSubtext
                HoverHandler {
                    id: tileHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) { grid.currentIndex = cell.index; root.keyboardNav = false; }
                }
                TapHandler { onTapped: root.pick(cell.modelData) }

                Item { // A few of its games' covers, fanned; All games: its icon on a squircle
                    id: lead
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    readonly property real coverH: tile.height - 16
                    readonly property real coverW: Math.round(coverH * 2 / 3)
                    readonly property real step: 14
                    width: cell.covers.length > 0 ? coverW + (cell.covers.length - 1) * step : coverH
                    height: coverH
                    Rectangle {
                        visible: cell.covers.length === 0
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: cell.active ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85) : Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: cell.all ? "apps" : "sell"; iconSize: 22; fill: cell.active ? 1 : 0
                            color: cell.active ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        }
                    }
                    Repeater {
                        model: cell.covers
                        delegate: ClippingRectangle {
                            id: cover
                            required property string modelData
                            required property int index
                            x: index * lead.step
                            z: cell.covers.length - index
                            width: lead.coverW; height: lead.coverH
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            Image {
                                anchors.fill: parent
                                source: "file://" + cover.modelData
                                sourceSize: Qt.size(96, 144) // Fixed: twice the most it's shown at
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Rectangle { // A thin gap between the stacked covers, over the picture
                                anchors.fill: parent
                                radius: cover.radius
                                color: "transparent"
                                border.width: 2
                                border.color: tile.color
                            }
                        }
                    }
                }
                Column {
                    anchors { left: lead.right; leftMargin: 12; right: bin.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    StyledText {
                        width: parent.width
                        text: cell.all ? Translation.tr("All games") : cell.modelData
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                        color: tile.ink
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: {
                            if (cell.all) return Translation.tr("No tag filter");
                            if (cell.armed) return Translation.tr("Click again to remove");
                            const n = GameLauncherService.tagCounts[cell.modelData] ?? 0;
                            return n === 1 ? Translation.tr("1 game") : Translation.tr("%1 games").arg(n);
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: cell.armed ? Appearance.colors.colError : tile.subInk
                    }
                }
                RippleButton { // Take the tag off every game (a second click confirms)
                    id: bin
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: cell.all ? 0 : 30; height: 30; padding: 0
                    focusPolicy: Qt.NoFocus
                    buttonRadius: Appearance.rounding.segment
                    opacity: !cell.all && (cell.lit || cell.armed) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    colBackground: cell.armed ? ColorUtils.transparentize(Appearance.colors.colError, 0.8) : "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, cell.armed ? 0.7 : 0.82)
                    colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: cell.armed ? "delete_forever" : "delete"
                            iconSize: 18
                            color: cell.armed || bin.hovered ? Appearance.colors.colError : tile.subInk
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                    StyledToolTip { text: cell.armed ? Translation.tr("Click again to remove") : Translation.tr("Remove from every game") }
                    onClicked: root.remove(cell.modelData)
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
