import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.sidebarRight.quickToggles.androidStyle
/**
 * The quick toggles, straight on the sidebar's controls well, as capsules (S2b): the wide ones two to a row (a round
 * icon, the name over the state, ›), then the small ones just their icons, as many to a row as fit (about 60 px apart), ending with ⋯ for the
 * control centre. Edit mode lists the unused toggles under a line, and tiles can be dragged: onto another tile to
 * move next to it (taking that tile's size), below the line to take it out, from below the line into the block to
 * add it. ⋯ isn't there while editing: it isn't a toggle, so it can't be moved or taken out.
 */
AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true
    implicitHeight: (editMode ? contentItem.implicitHeight : usedRows.implicitHeight)
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    readonly property real spacing: 6
    readonly property real wideHeight: 50
    readonly property real smallHeight: 44 // A 38 px capsule in it
    readonly property int smallPerRow: Math.max(1, Math.floor(width / 60))
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "nightLight", "gameMode", "screenSnip", "colorPicker", "mic", "audio", "notifications", "powerProfile", "antiFlashbang"]
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles.filter(t => !!t) : []
    readonly property var toggleRows: [...chunk(toggles.filter(t => t.size > 1), 2),
        ...chunk(toggles.filter(t => t.size <= 1).concat(editMode ? [] : [{ type: "more", size: 1 }]), smallPerRow)]
    readonly property var unusedToggleRows: chunk(availableToggleTypes
        .filter(type => !toggles.some(toggle => toggle.type === type))
        .map(type => ({ type: type, size: 1 })), smallPerRow)
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

    // Rows of tiles
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
                spacing: wide ? root.spacing : 0 // Small ones are spaced by their cells
                Repeater {
                    model: ScriptModel {
                        values: toggleRow.items
                        objectProp: "type"
                    }
                    delegate: AndroidToggleDelegateChooser {
                        panel: root
                        editMode: root.editMode
                        unused: block.unused
                        // Small ones: a fixed cell, so a short row lines up under the full ones
                        cellWidth: toggleRow.wide ? (block.width - toggleRow.spacing * (toggleRow.items.length - 1)) / Math.max(1, toggleRow.items.length)
                            : block.width / root.smallPerRow
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
