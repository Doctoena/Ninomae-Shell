import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.sidebarRight.quickToggles.androidStyle
/**
 * The quick toggles as one block, as Settings joins its rows: the wide tiles two to a row, then the small ones
 * (Settings → Sidebar → Columns to a row), 4 px apart, round at the block's outer corners and only slightly
 * between (`joinedBelow`: the sidebar's sliders join under it). A row with fewer tiles stretches them to fill it. Edit mode lists the unused toggles under a line
 * as a second block, and tiles can be dragged: onto another tile to move next to it (taking that tile's size),
 * below the line to take it out, from below the line into the block to add it.
 */
AbstractQuickPanel {
    id: root
    property bool editMode: false
    property bool joinedBelow: false // Another card joins under the block: its bottom corners stay slight
    Layout.fillWidth: true
    implicitHeight: (editMode ? contentItem.implicitHeight : usedRows.implicitHeight)
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    readonly property real spacing: 4
    readonly property real wideHeight: 50
    readonly property real smallHeight: 44
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "nightLight", "gameMode", "screenSnip", "colorPicker", "mic", "audio", "notifications", "powerProfile", "antiFlashbang"]
    readonly property int columns: Math.max(1, Config.options.sidebar.quickToggles.android.columns)
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles.filter(t => !!t) : []
    readonly property var toggleRows: [...chunk(toggles.filter(t => t.size > 1), 2), ...chunk(toggles.filter(t => t.size <= 1), columns)]
    readonly property var unusedToggleRows: chunk(availableToggleTypes
        .filter(type => !toggles.some(toggle => toggle.type === type))
        .map(type => ({ type: type, size: 1 })), columns)
    readonly property bool isQuickPanel: true // Where a dragged tile stops raising its parents (AndroidQuickToggleButton)

    // ── Dragging in edit mode ──
    property string dragType: "" // The toggle being dragged
    property string dropType: "" // The tile under the pointer, and which side of it
    property bool dropBefore: false
    property bool dropUnused: false // Over the unused toggles: let go to take it out
    // What's under a point (in fromItem's coordinates): which block, and the tile there (or none)
    function hitTest(fromItem, x, y) {
        for (const block of [usedRows, unusedLoader.item]) {
            if (!block) continue;
            const p = fromItem.mapToItem(block, x, y);
            const slack = root.spacing;
            if (p.x < -slack || p.y < -slack || p.x > block.width + slack || p.y > block.height + slack) continue;
            let tile = null;
            for (const row of block.children) {
                if (row.items === undefined || p.y < row.y - slack / 2 || p.y > row.y + row.height + slack / 2) continue;
                for (const c of row.children) {
                    if (c.buttonData === undefined || p.x < c.x - slack / 2 || p.x > c.x + c.width + slack / 2) continue;
                    tile = { type: c.buttonData.type, size: c.buttonData.size, before: p.x < c.x + c.width / 2 };
                }
            }
            return { unused: block !== usedRows, tile: tile };
        }
        return null;
    }
    function updateDrag(type, fromItem, x, y) {
        const hit = hitTest(fromItem, x, y);
        root.dragType = type;
        root.dropUnused = !!hit && hit.unused;
        root.dropType = hit?.tile && !hit.unused ? hit.tile.type : "";
        root.dropBefore = hit?.tile?.before ?? false;
    }
    function endDrag(type, fromItem, x, y) {
        const hit = hitTest(fromItem, x, y);
        root.dragType = "";
        root.dropType = "";
        root.dropUnused = false;
        if (!hit || hit.tile?.type === type) return; // Nowhere, or on itself
        editToggles((list, from) => {
            if (hit.unused) { // Taken out
                if (from >= 0) list.splice(from, 1);
                return;
            }
            const entry = from >= 0 ? list[from] : { type: type, size: 1 };
            if (from >= 0) list.splice(from, 1);
            if (!hit.tile) { list.push(entry); return; } // In the block but not on a tile: at the end
            entry.size = hit.tile.size > 1 ? 2 : 1; // Takes the size of the tiles it joins
            const to = list.findIndex(t => t.type === hit.tile.type);
            list.splice(hit.tile.before ? to : to + 1, 0, entry);
        }, type);
    }

    // ── Every edit (click, right-click, scroll, drag) goes through here ──
    // A copy is changed and written back whole, so the config always sees the change and saves it
    function editToggles(change, type) {
        const list = Config.options.sidebar.quickToggles.android.toggles.filter(t => !!t).map(t => ({ type: t.type, size: t.size }));
        change(list, list.findIndex(t => t.type === type));
        Config.options.sidebar.quickToggles.android.toggles = list;
    }
    function toggleEnabled(type) { // In use: taken out; not: added as a small tile
        editToggles((list, i) => { if (i < 0) list.push({ type: type, size: 1 }); else list.splice(i, 1); }, type);
    }
    function toggleSize(type) { // Wide ↔ small
        editToggles((list, i) => { if (i >= 0) list[i].size = list[i].size > 1 ? 1 : 2; }, type);
    }
    function moveBy(type, offset) { // Past the next tile of its own size (wide and small sit in their own rows)
        editToggles((list, i) => {
            if (i < 0) return;
            const wide = t => t.size > 1;
            let j = i + offset;
            while (j >= 0 && j < list.length && wide(list[j]) !== wide(list[i])) j += offset;
            if (j < 0 || j >= list.length) return;
            [list[i], list[j]] = [list[j], list[i]];
        }, type);
    }

    function chunk(list, size) {
        const rows = [];
        for (let i = 0; i < list.length; i += size) rows.push(list.slice(i, i + size));
        return rows;
    }

    Column {
        id: contentItem
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12
        ToggleBlock {
            id: usedRows
            rows: root.toggleRows
        }
        FadeLoader {
            shown: root.editMode
            anchors { left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }
        FadeLoader {
            id: unusedLoader
            shown: root.editMode
            anchors { left: parent.left; right: parent.right }
            sourceComponent: ToggleBlock {
                rows: root.unusedToggleRows
                unused: true
            }
        }
    }

    // Rows of tiles, joined into one block
    component ToggleBlock: Column {
        id: block
        property var rows: []
        property bool unused: false
        anchors { left: parent?.left; right: parent?.right }
        spacing: root.spacing
        Repeater {
            model: ScriptModel {
                values: Array(block.rows.length)
            }
            delegate: Row {
                id: toggleRow
                required property int index
                readonly property var items: block.rows[index] ?? []
                readonly property bool wide: (items[0]?.size ?? 1) > 1
                spacing: root.spacing
                Repeater {
                    model: ScriptModel {
                        values: toggleRow.items
                        objectProp: "type"
                    }
                    delegate: AndroidToggleDelegateChooser {
                        panel: root
                        editMode: root.editMode
                        unused: block.unused
                        rowIndex: toggleRow.index
                        rowCount: block.rows.length
                        rowLength: toggleRow.items.length
                        cellWidth: (block.width - root.spacing * (toggleRow.items.length - 1)) / Math.max(1, toggleRow.items.length)
                        cellHeight: toggleRow.wide ? root.wideHeight : root.smallHeight
                        onOpenAudioOutputPage: root.openAudioOutputPage()
                        onOpenAudioInputPage: root.openAudioInputPage()
                        onOpenBluetoothPage: root.openBluetoothPage()
                        onOpenNightLightPage: root.openNightLightPage()
                        onOpenWifiPage: root.openWifiPage()
                    }
                }
            }
        }
    }
}
