import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell.Widgets

/**
 * The grid's tag filter: a panel growing up out of the launcher (LauncherTopPanel), like Add a game and
 * the details page's Captures and News, from the tag button by the sort one. A tile per tag with how many
 * games have it and a few of their covers; picking one shows only those (GameLauncherService.selectedTag)
 * and closes the panel, picking it again (or the header's "show all") shows everything. The tag in use
 * is the accent one. One row: every tag while they fit, else whole tiles stepped through with the
 * ‹ › arrows or the wheel. The bin in a tile's corner takes the tag off every game, on a second click.
 * ←/→ move, Enter picks, Delete (twice) removes, Esc closes.
 */
LauncherTopPanel {
    id: root
    panelWidth: 1100
    panelHeight: 300
    onShownChanged: if (shown) {
        tiles.currentIndex = Math.max(0, tags.indexOf(GameLauncherService.selectedTag));
        tiles.show(tiles.currentIndex);
        keyboardNav = false;
        keys.forceActiveFocus();
    }

    readonly property var tags: GameLauncherService.allTags
    // The keyboard's tile is only lit after a key press; the mouse lights the one it's over
    property bool keyboardNav: false
    // Up to four covers per tag (the custom ones where set, else the library's), in one pass over the
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
                if (list.length < 4) list.push(art);
            }
        }
        return out;
    }
    // A first press of the bin (or Delete) arms it; a second, within a few seconds, removes the tag
    property string armedTag: ""
    Timer { id: disarm; interval: 3000; onTriggered: root.armedTag = "" }
    function remove(tag) {
        if (root.armedTag === tag) { root.armedTag = ""; GameLauncherService.removeTagEverywhere(tag); }
        else { root.armedTag = tag; disarm.restart(); }
    }
    function pick(tag) {
        GameLauncherService.selectedTag = GameLauncherService.selectedTag === tag ? "" : tag;
        root.closeRequested();
    }
    function moveTo(i) {
        tiles.currentIndex = Math.max(0, Math.min(tiles.count - 1, i));
        tiles.show(tiles.currentIndex);
        root.keyboardNav = true;
    }

    Item { // Takes the keys while it's open (the search bar has them otherwise)
        id: keys
        focus: true
        Keys.onPressed: event => {
            const i = tiles.currentIndex;
            const current = root.tags[i];
            if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) root.moveTo(i + (event.key === Qt.Key_Right ? 1 : -1));
            else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) root.moveTo(event.key === Qt.Key_Home ? 0 : tiles.count - 1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (current) root.pick(current); }
            else if (event.key === Qt.Key_Delete) { if (current) { root.keyboardNav = true; root.remove(current); } }
            else if (event.key === Qt.Key_Escape) root.closeRequested();
            else return;
            event.accepted = true;
        }
    }

    SheetHeader {
        id: header
        icon: "sell"
        title: Translation.tr("Tags")
        subtitle: GameLauncherService.selectedTag !== "" ? Translation.tr("Showing \"%1\"").arg(GameLauncherService.selectedTag)
            : root.tags.length === 1 ? Translation.tr("1 tag") : Translation.tr("%1 tags").arg(root.tags.length)
        onCloseRequested: root.closeRequested()
        SheetIconButton { // Back to every game
            visible: GameLauncherService.selectedTag !== ""
            iconName: "filter_alt_off"
            tip: Translation.tr("Show all games")
            onClicked: { GameLauncherService.selectedTag = ""; root.closeRequested(); }
        }
    }

    ListView {
        id: tiles
        // One row of whole tiles: all of them while they fit at 240 px or more, else as many 300 px ones
        // as fit between the ‹ › arrows, stepped a tile at a time (arrows, wheel, keys), never half cut off
        readonly property real room: parent.width - 32
        readonly property int n: root.tags.length
        readonly property bool paged: n * 240 + (n - 1) * spacing > room
        readonly property real rowRoom: paged ? room - 2 * (44 + 8) : room // Less the arrows (and their gap)
        readonly property int perPage: paged ? Math.max(1, Math.floor((rowRoom + spacing) / (240 + spacing))) : Math.max(1, n)
        readonly property real tileW: Math.min(300, Math.floor((rowRoom - spacing * (perPage - 1)) / perPage))
        property int first: 0 // The leftmost tile shown
        readonly property int lastFirst: Math.max(0, n - perPage)
        onLastFirstChanged: if (first > lastFirst) first = lastFirst
        function show(i) { // Step just far enough that tile i is in view
            if (i < first) first = i;
            else if (i > first + perPage - 1) first = Math.min(lastFirst, i - perPage + 1);
        }
        anchors { top: header.bottom; topMargin: 14; bottom: parent.bottom; bottomMargin: 16; horizontalCenter: parent.horizontalCenter }
        width: Math.min(n, perPage) * tileW + Math.max(0, Math.min(n, perPage) - 1) * spacing
        orientation: ListView.Horizontal
        spacing: 10
        clip: true
        interactive: false
        contentX: first * (tileW + spacing)
        Behavior on contentX { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        model: root.tags
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (root.armedTag !== root.tags[currentIndex]) root.armedTag = ""
        WheelHandler { // The usual up/down wheel steps a tile a notch; a touchpad's small deltas add up to one
            property real acc: 0
            enabled: tiles.paged
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                acc += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                if (Math.abs(acc) < 120) return;
                tiles.first = Math.max(0, Math.min(tiles.lastFirst, tiles.first + (acc > 0 ? -1 : 1)));
                acc = 0;
            }
        }
        delegate: Rectangle {
            id: tile
            required property string modelData
            required property int index
            readonly property bool active: GameLauncherService.selectedTag === modelData
            readonly property bool lit: tileHover.hovered || (root.keyboardNav && tiles.currentIndex === index)
            readonly property bool armed: root.armedTag === modelData
            readonly property var covers: root.covers[modelData] ?? []
            width: tiles.tileW; height: tiles.height
            radius: Appearance.rounding.normal
            // The tag in use: the accent squircle (accent = active); the rest neutral, a step up on hover
            color: active ? (lit ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                : lit ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: 140 } }
            HoverHandler {
                id: tileHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered) { tiles.currentIndex = tile.index; root.keyboardNav = false; }
            }
            TapHandler { onTapped: root.pick(tile.modelData) }
            RippleButton { // Take the tag off every game (a second click confirms); lined up with the text and the covers' foot
                id: bin
                anchors { left: parent.left; leftMargin: 14; bottom: parent.bottom; bottomMargin: 14 }
                width: 30; height: 30; padding: 0
                focusPolicy: Qt.NoFocus
                buttonRadius: Appearance.rounding.segment
                opacity: tile.lit || tile.armed ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                readonly property color rest: tile.active ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85) : Appearance.colors.colLayer2
                colBackground: tile.armed ? ColorUtils.transparentize(Appearance.colors.colError, 0.8) : rest
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, tile.armed ? 0.7 : 0.82)
                colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: tile.armed ? "delete_forever" : "delete"
                        iconSize: 18
                        color: tile.armed || bin.hovered ? Appearance.colors.colError
                            : tile.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
                StyledToolTip { text: tile.armed ? Translation.tr("Click again to remove") : Translation.tr("Remove from every game") }
                onClicked: root.remove(tile.modelData)
            }
            Column {
                anchors { left: parent.left; leftMargin: 16; right: coverStack.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 4
                MaterialSymbol {
                    text: "sell"; iconSize: 20; fill: tile.active ? 1 : 0
                    color: tile.active ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                }
                StyledText {
                    width: parent.width
                    text: tile.modelData
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
                    color: tile.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: {
                        const n = GameLauncherService.tagCounts[tile.modelData] ?? 0;
                        return n === 1 ? Translation.tr("1 game") : Translation.tr("%1 games").arg(n);
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: tile.active ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2) : Appearance.colors.colSubtext
                }
            }
            Item { // A few of its games' covers, fanned out to the right: as many as leave room for the name
                id: coverStack
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                readonly property real coverH: tile.height - 28
                readonly property real coverW: Math.round(coverH * 2 / 3)
                readonly property real step: 22
                readonly property var shown: tile.covers.slice(0, Math.max(1, Math.min(4, Math.floor((tile.width - 112 - coverW) / step) + 1)))
                width: shown.length === 0 ? 0 : coverW + (shown.length - 1) * step
                height: coverH
                Repeater {
                    model: coverStack.shown
                    delegate: ClippingRectangle {
                        id: cover
                        required property string modelData
                        required property int index
                        x: index * coverStack.step
                        z: coverStack.shown.length - index
                        width: coverStack.coverW; height: coverStack.coverH
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        Image {
                            anchors.fill: parent
                            source: "file://" + cover.modelData
                            sourceSize: Qt.size(coverStack.coverW * 2, coverStack.coverH * 2)
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
        }
    }
    SheetNavButton {
        anchors { right: tiles.left; rightMargin: 8; verticalCenter: tiles.verticalCenter }
        visible: tiles.paged
        iconName: "chevron_left"
        enabled: tiles.first > 0
        onClicked: tiles.first--
    }
    SheetNavButton {
        anchors { left: tiles.right; leftMargin: 8; verticalCenter: tiles.verticalCenter }
        visible: tiles.paged
        iconName: "chevron_right"
        enabled: tiles.first < tiles.lastFirst
        onClicked: tiles.first++
    }
    SheetEmptyState {
        anchors.centerIn: parent
        visible: root.tags.length === 0
        icon: "sell"
        text: Translation.tr("No tags yet")
        hint: Translation.tr("Tag games from their page (the tag button under Play)")
    }
}
