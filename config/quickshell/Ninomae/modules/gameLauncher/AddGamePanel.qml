import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * Add a game: any installed app (a Flatpak, an AppImage with a desktop entry, an emulator) into the
 * library, as Steam's "Add a non-Steam game" does. A panel growing up out of the launcher
 * (LauncherTopPanel) from the toolbar's Add button. On the left, the lit app as it'll look in the
 * library: on its banner, its cover as a library tile (pointed at, with its glass piece: Add, or ▶ once it's
 * in), with the logo, name, what it is and Add to library beside it (art from SteamGridDB, fetched when there's a
 * key, kept in the cache); one that's in shows its own art, time played, its page and a bin. On the right, in a
 * well, the search and the apps under Games and Apps (games first), the lit one on the accent card with Add. Steam and Lutris, and their game shortcuts, are
 * left out (those games are in already). Adding keeps the panel open to add more (art comes with it,
 * GameLauncherService.addCustomGame). ↑/↓ move, Enter adds (or opens), Delete (twice) takes one out,
 * Esc closes.
 */
LauncherTopPanel {
    id: root
    panelWidth: 1100
    panelHeight: 400
    clipContent: true
    signal openGame(var game)
    onShownChanged: if (shown) {
        search.text = "";
        list.currentIndex = 0;
        armedId = "";
        search.forceActiveFocus();
        wantArt();
        // Previews not looked at for a month go (a banner is often several MB)
        Quickshell.execDetached(["find", GameLauncherService.sgdbPreviewDir, "-type", "f", "-mtime", "+30", "-delete"]);
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
    readonly property var matches: { // The apps the search matches
        const q = search.text.trim().toLowerCase();
        return q === "" ? apps : apps.filter(a => a.name.toLowerCase().includes(q));
    }
    readonly property var current: matches[list.currentIndex] ?? null
    readonly property var currentGame: current?.customId ? (GameLauncherService.gamesById[current.customId] ?? null) : null

    function add(app) {
        if (!app || app.customId) return;
        GameLauncherService.addCustomGame({ id: app.entry.id, name: app.entry.name, command: Array.from(app.entry.command),
                                            icon: app.entry.icon, workingDirectory: app.entry.workingDirectory });
    }
    function open(app) { // In already: its page
        const game = app?.customId ? GameLauncherService.gamesById[app.customId] : null;
        if (game) root.openGame(game);
    }
    // A first press of the bin (or Delete) arms it; a second, within a few seconds, takes the game out
    property string armedId: ""
    Timer { id: disarm; interval: 3000; onTriggered: root.armedId = "" }
    function remove(app) {
        if (!app?.customId) return;
        if (root.armedId === app.customId) { root.armedId = ""; GameLauncherService.removeCustomGame(app.customId); }
        else { root.armedId = app.customId; disarm.restart(); }
    }
    onCurrentChanged: {
        if (armedId !== (current?.customId ?? "")) armedId = "";
        wantArt();
    }
    function wantArt() { // The lit app's art, unless it's in (its own) or was looked up already
        if (!canFetch || !current || current.customId || (current.name in previewArt)) return;
        fetchDelay.interval = current.isGame ? 350 : 1200; // Other apps only once they've been rested on
        fetchDelay.restart();
    }

    // ── SteamGridDB art for the preview: the lit app's, once it has been lit a moment; files kept in the cache
    //    (GameLauncherService.sgdbPreviewDir, by app name), so an app seen before shows at once and isn't looked up
    //    again, and adding it moves them into the game's art instead of fetching them twice ──
    readonly property bool canFetch: GameLauncherService.steamGridDbApiKey.length > 0
    property var previewArt: ({}) // App name → { grid, hero, logo } (empty: nothing found)
    readonly property var art: current?.customId ? {
            grid: GameLauncherService.localArt(currentGame, "boxArt"),
            hero: GameLauncherService.bannerArt(currentGame),
            logo: GameLauncherService.logoArt(currentGame)
        } : (current ? (previewArt[current.name] ?? null) : null)
    Timer {
        id: fetchDelay
        onTriggered: {
            if (!root.current || root.current.customId || (root.current.name in root.previewArt)) return;
            if (artProc.running) { restart(); return; }
            artProc.name = root.current.name;
            root.setArt(root.current.name, null, ""); // Looked up: not again
            // The cached files once a lookup has finished (<slug>.done, also when nothing was found), else the
            // lookup again: one cut off by the panel closing left only some of them (it prints "<kind> <path>" per file)
            artProc.command = ["sh", "-c", '[ -e "$1/$2.done" ] && { ls -- "$1"/"$2"_sgdb_* 2>/dev/null; exit 0; }; '
                               + 'python3 -I "$3" "$4" "$1" "$2" && mkdir -p "$1" && touch "$1/$2.done"', "sgdb-preview",
                               GameLauncherService.sgdbPreviewDir, GameLauncherService.sgdbSlug(root.current.name), Quickshell.shellPath("scripts/game-launcher/sgdb_auto_art.py"), root.current.name];
            artProc.running = true;
        }
    }
    Process {
        id: artProc
        property string name
        environment: ({ SGDB_KEY: GameLauncherService.steamGridDbApiKey }) // Not an argument: any process can read those (ps)
        stdout: SplitParser { // Each file as it lands (a banner can take a while): the cover shows first
            onRead: line => {
                const m = line.match(/(\/\S*_sgdb_(grid|hero|logo)_auto\.\w+)$/);
                if (m) root.setArt(artProc.name, m[2], m[1]);
            }
        }
    }
    function setArt(name, kind, path) {
        const next = Object.assign({}, root.previewArt);
        next[name] = Object.assign({}, next[name] ?? {});
        if (kind) next[name][kind] = path;
        root.previewArt = next;
    }

    // ── Preview: on its banner, the app as a library tile (pointed at, with its glass piece), and beside it the logo,
    //    name, what it is, and Add to library (one that's in: its page and a bin) ──
    readonly property bool currentIn: !!current?.customId
    readonly property bool hasArt: !!(art?.grid || art?.hero || art?.logo)
    ClippingRectangle {
        id: preview
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 16 }
        width: 470
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        Image { // The banner art, shaded so the tile and words sit on it
            anchors.fill: parent
            source: root.art?.hero ? "file://" + root.art.hero : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 960 // Fixed: the preview doesn't resize
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45) }
                GradientStop { position: 1; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.1) }
            }
        }

        // The tile, as the library will show it while pointed at: the ring, its cover (else the app's icon), the glass
        // piece with its name and New (or its hours), and Add on the accent squircle (▶ once it's in)
        Item {
            id: tile
            x: 22; y: 26
            width: 176; height: 264
            Rectangle {
                anchors { fill: parent; margins: -4 }
                radius: Appearance.rounding.small + 4
                color: "transparent"
                border { width: 2; color: Appearance.colors.colPrimary }
            }
            ClippingRectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.art?.grid ? "file://" + root.art.grid : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 352
                    asynchronous: true
                }
                IconImage {
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -24 }
                    visible: coverImage.status !== Image.Ready
                    implicitSize: 64
                    source: Quickshell.iconPath(root.current?.icon ?? "", "application-x-executable")
                }
            }
            Rectangle { // The cover's fine edge light
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: "transparent"
                border { width: 1; color: ColorUtils.transparentize("white", 0.84) }
            }
            TileGlassPiece { // As the library shows it: Add (▶ once it's in, which starts it)
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                name: root.current?.name ?? ""
                minutes: root.currentGame?.playtime ?? 0
                lastPlayed: root.currentGame?.lastPlayed ?? 0
                showButton: !!root.current
                buttonIcon: root.currentIn ? "play_arrow" : "library_add"
                buttonTip: root.currentIn ? Translation.tr("Play") : Translation.tr("Add to library")
                onButtonClicked: root.currentIn ? GameLauncherService.quickLaunch(root.currentGame, () => root.open(root.current)) : root.add(root.current)
            }
        }
        StyledText {
            anchors { horizontalCenter: tile.horizontalCenter; top: tile.bottom; topMargin: 14 }
            text: Translation.tr("As it'll look in your library")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        // Beside the tile: the logo, its name, what it is, then Add (or its page and a bin), level with the tile's foot
        Column {
            anchors { left: tile.right; leftMargin: 22; right: parent.right; rightMargin: 20; top: tile.top; topMargin: 8 }
            spacing: 6
            Image {
                width: parent.width; height: 62
                source: root.art?.logo ? "file://" + root.art.logo : ""
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignBottom
                sourceSize.height: 124 // Fixed: twice the most it's shown at
                asynchronous: true
                visible: status === Image.Ready
            }
            Item { width: 1; height: 4 }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: root.current?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.title; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Row { // What it is, with dots between: Game · Flatpak, or In your library · 3 h played
                spacing: 6
                Repeater {
                    model: {
                        if (!root.current) return [];
                        if (root.currentIn) {
                            const min = root.currentGame?.playtime ?? 0;
                            return [Translation.tr("In your library"), min >= 60 ? Translation.tr("%1h played").arg(Math.round(min / 60)) : min > 0 ? Translation.tr("%1m played").arg(min) : ""].filter(t => t);
                        }
                        return [root.current.isGame ? Translation.tr("Game") : Translation.tr("App"), root.current.flatpak ? "Flatpak" : ""].filter(t => t);
                    }
                    Row {
                        required property var modelData
                        required property int index
                        spacing: 6
                        Rectangle {
                            visible: index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3; height: 3; radius: 1.5
                            color: Appearance.colors.colSubtext
                            opacity: 0.6
                        }
                        StyledText {
                            text: modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtextGlass
                        }
                    }
                }
            }
            StyledText { // Its art comes with it
                width: parent.width
                visible: !root.currentIn && root.hasArt
                topPadding: 4
                wrapMode: Text.WordWrap
                text: Translation.tr("Its cover, banner and logo from SteamGridDB come with it.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
        Row {
            anchors { left: tile.right; leftMargin: 22; right: parent.right; rightMargin: 20; bottom: tile.bottom }
            spacing: 8
            RippleButton { // Add to library, or for one that's in, its page
                id: mainButton
                width: parent.width - (bin.visible ? bin.width + parent.spacing : 0)
                implicitHeight: 40
                enabled: !!root.current
                buttonRadius: 12
                colBackground: root.currentIn ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35) : Appearance.colors.colPrimary
                colBackgroundHover: root.currentIn ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.15) : Appearance.colors.colPrimaryHover
                colRipple: root.currentIn ? Appearance.colors.colLayer2Active : Appearance.colors.colPrimaryActive
                onClicked: root.currentIn ? root.open(root.current) : root.add(root.current)
                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.currentIn ? "open_in_new" : "library_add"
                            iconSize: 18
                            color: root.currentIn ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.currentIn ? Translation.tr("Open its page") : Translation.tr("Add to library")
                            font.weight: Font.DemiBold
                            color: root.currentIn ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
            RippleButton { // Take it out of the library (a second click confirms)
                id: bin
                readonly property bool armed: visible && root.armedId === (root.current?.customId ?? "")
                visible: root.currentIn
                implicitWidth: 40; implicitHeight: 40; padding: 0
                buttonRadius: 12
                colBackground: armed ? ColorUtils.transparentize(Appearance.colors.colError, 0.75) : ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, armed ? 0.65 : 0.75)
                colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.6)
                onClicked: root.remove(root.current)
                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: bin.armed ? "delete_forever" : "delete"
                        iconSize: 18
                        color: bin.armed || bin.hovered ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                    }
                }
                StyledToolTip { text: bin.armed ? Translation.tr("Click again to take it out") : Translation.tr("Take it out of the library") }
            }
        }
    }
    GlassEdge { anchors.fill: preview; radius: preview.radius }

    // ── The list, in a well: the search (no header and no close: the toolbar's + closes it, as Esc does), then the
    //    apps straight on the well under "Games" and "Apps", the lit one on the accent card with Add ──
    GlassWell {
        id: listWell
        anchors { left: preview.right; leftMargin: 12; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 16; bottom: parent.bottom; bottomMargin: 16 }
    }
    Rectangle { // The search: a darker field with a fine rim
        id: searchBox
        anchors { left: listWell.left; right: listWell.right; top: listWell.top; margins: 6 }
        height: 40
        radius: 12
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
        border.width: search.activeFocus ? 2 : 1
        border.color: search.activeFocus ? Appearance.colors.colPrimary : ColorUtils.transparentize("white", 0.9)
        MaterialSymbol {
            id: searchIcon
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: "search"
            iconSize: 17
            color: search.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        }
        ToolbarTextField {
            id: search
            anchors { left: searchIcon.right; leftMargin: 6; right: parent.right; rightMargin: 8; top: parent.top; bottom: parent.bottom }
            padding: 0
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.small
            colBackground: "transparent"
            placeholderText: Translation.tr("Search apps: a Flatpak, an AppImage, an emulator…")
            onTextChanged: list.currentIndex = 0
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + (event.key === Qt.Key_Down ? 1 : -1)));
                    list.positionViewAtIndex(list.currentIndex, ListView.Contain);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.currentIn) root.open(root.current);
                    else root.add(root.current);
                } else if (event.key === Qt.Key_Delete && search.text === "") root.remove(root.current);
                else if (event.key === Qt.Key_Escape) root.closeRequested();
                else return;
                event.accepted = true;
            }
        }
    }
    ListView {
        id: list
        anchors { left: listWell.left; right: listWell.right; top: searchBox.bottom; bottom: listWell.bottom; leftMargin: 6; rightMargin: 6; topMargin: 2; bottomMargin: 6 }
        clip: true
        // Its edges fade into the well while there's more to scroll to. Only while it can scroll: a list that fits
        // needs no layer
        layer.enabled: !(atYBeginning && atYEnd)
        layer.effect: ScrollFadeMask { topActive: !list.atYBeginning; bottomActive: !list.atYEnd }
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        model: root.matches
        delegate: Column {
            id: row
            required property var modelData
            required property int index
            readonly property bool lit: ListView.isCurrentItem
            readonly property bool added: !!modelData.customId
            // A heading where the games end and the apps begin (games come first), and over the first
            readonly property bool heads: index === 0 || (root.matches[index - 1]?.isGame ?? false) !== modelData.isGame
            width: ListView.view.width
            Item {
                visible: row.heads
                width: parent.width; height: 26
                StyledText {
                    anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 5 }
                    text: row.modelData.isGame ? Translation.tr("Games") : Translation.tr("Apps")
                    font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
            }
            Rectangle {
                width: parent.width
                height: 46
                radius: 12
                color: row.lit ? Appearance.colors.colLayer3Accent : "transparent"
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered && root.settled) list.currentIndex = row.index
                }
                TapHandler { onTapped: row.added ? root.open(row.modelData) : root.add(row.modelData) }
                Rectangle { // The app's icon on its squircle
                    id: rowIcon
                    anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 10
                    color: Appearance.colors.colLayer4
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 22
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }
                }
                Column { // Its name, and what it is under it
                    anchors { left: rowIcon.right; leftMargin: 11; right: rowTrail.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: row.lit ? Font.DemiBold : Font.Normal
                        color: row.lit ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: [row.modelData.isGame ? Translation.tr("Game") : Translation.tr("App"), row.modelData.flatpak ? "Flatpak" : ""].filter(t => t).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                Item { // In the library already (a quiet check), or, lit, Add on the accent
                    id: rowTrail
                    anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                    width: row.added ? inRow.implicitWidth + 4 : row.lit ? addChip.width : 0
                    height: 30
                    Row {
                        id: inRow
                        visible: row.added
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        spacing: 5
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "check_circle"; iconSize: 15; fill: 1; color: Appearance.colors.colPrimary }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("In your library")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Rectangle {
                        id: addChip
                        visible: row.lit && !row.added
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: addRow.implicitWidth + 20; height: 30
                        radius: 9
                        color: Appearance.colors.colPrimary
                        Row {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "library_add"; iconSize: 15; color: Appearance.colors.colOnPrimary }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }
    SheetEmptyState {
        anchors.centerIn: list
        visible: root.matches.length === 0
        icon: "search_off"
        text: Translation.tr("No apps match")
        hint: ""
    }
}
