import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * Add a game: any installed app (a Flatpak, an AppImage with a desktop entry, an emulator) into the
 * library, as Steam's "Add a non-Steam game" does. A panel growing up out of the launcher
 * (LauncherTopPanel) from the toolbar's Add button. On the left, the lit app as it'll look in the
 * library: the cover, banner and logo SteamGridDB has for it (fetched when there's a key, kept in the
 * cache), its name and Add to library; one that's in shows its own art, time played, its page and a bin.
 * On the right, the search and the apps, games first. Steam and Lutris, and their game shortcuts, are
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
    readonly property var currentGame: current?.customId ? (GameLauncherService._installedGamesMap[current.customId] ?? null) : null

    function add(app) {
        if (!app || app.customId) return;
        GameLauncherService.addCustomGame({ id: app.entry.id, name: app.entry.name, command: Array.from(app.entry.command),
                                            icon: app.entry.icon, workingDirectory: app.entry.workingDirectory });
    }
    function open(app) { // In already: its page
        const game = app?.customId ? GameLauncherService._installedGamesMap[app.customId] : null;
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

    // ── Preview: the art it'll get (or has), its name, Add or its page ──
    ClippingRectangle {
        id: preview
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 16 }
        width: 340
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        Image { // The banner art, shaded towards the foot for the text
            anchors.fill: parent
            source: root.art?.hero ? "file://" + root.art.hero : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 768 // Fixed: the preview doesn't resize
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.6) }
                GradientStop { position: 1; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.05) }
            }
        }
        ClippingRectangle { // The cover, else the app's icon
            id: cover
            anchors { left: parent.left; leftMargin: 20; top: parent.top; topMargin: 20 }
            width: 132; height: 198
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            Image {
                id: coverImage
                anchors.fill: parent
                source: root.art?.grid ? "file://" + root.art.grid : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 264
                asynchronous: true
            }
            IconImage {
                anchors.centerIn: parent
                visible: coverImage.status !== Image.Ready
                implicitSize: 56
                source: Quickshell.iconPath(root.current?.icon ?? "", "application-x-executable")
            }
            Rectangle { // Hairline edge
                anchors.fill: parent
                radius: cover.radius
                color: "transparent"
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
            }
        }
        Image { // The logo, beside the cover's foot
            anchors { left: cover.right; leftMargin: 16; right: parent.right; rightMargin: 16; bottom: cover.bottom }
            height: 56
            source: root.art?.logo ? "file://" + root.art.logo : ""
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            verticalAlignment: Image.AlignBottom
            sourceSize.height: 112 // Fixed: twice the most it's shown at
            asynchronous: true
            visible: status === Image.Ready
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
            spacing: 4
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: root.current?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.title; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (!root.current) return "";
                    if (root.current.customId) {
                        const min = root.currentGame?.playtime ?? 0;
                        const played = min >= 60 ? Translation.tr("%1h played").arg(Math.round(min / 60)) : min > 0 ? Translation.tr("%1m played").arg(min) : "";
                        return [Translation.tr("In your library"), played].filter(t => t).join(" · ");
                    }
                    return [root.current.isGame ? Translation.tr("Game") : Translation.tr("App"), root.current.flatpak ? "Flatpak" : ""].filter(t => t).join(" · ");
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Item { width: 1; height: 8 }
            Row {
                width: parent.width
                spacing: 8
                RippleButton { // Add to library, or for one that's in, its page
                    id: mainButton
                    readonly property bool isIn: !!root.current?.customId
                    width: parent.width - (bin.visible ? bin.width + parent.spacing : 0)
                    implicitHeight: 40
                    enabled: !!root.current
                    buttonRadius: Appearance.rounding.segment
                    colBackground: isIn ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35) : Appearance.colors.colPrimary
                    colBackgroundHover: isIn ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.15) : Appearance.colors.colPrimaryHover
                    colRipple: isIn ? Appearance.colors.colLayer2Active : Appearance.colors.colPrimaryActive
                    onClicked: isIn ? root.open(root.current) : root.add(root.current)
                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: mainButton.isIn ? "open_in_new" : "library_add"
                                iconSize: 18
                                color: mainButton.isIn ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: mainButton.isIn ? Translation.tr("Open its page") : Translation.tr("Add to library")
                                font.weight: Font.DemiBold
                                color: mainButton.isIn ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
                RippleButton { // Take it out of the library (a second click confirms)
                    id: bin
                    readonly property bool armed: visible && root.armedId === (root.current?.customId ?? "")
                    visible: !!root.current?.customId
                    implicitWidth: 40; implicitHeight: 40; padding: 0
                    buttonRadius: Appearance.rounding.segment
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
    }

    // ── The list: search (no header and no close: the toolbar's + closes it, as Esc does), then the apps ──
    Rectangle {
        id: searchBox
        anchors { left: preview.right; leftMargin: 16; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 16 }
        height: 36
        radius: Appearance.rounding.segment
        color: search.activeFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        Behavior on color { ColorAnimation { duration: 140 } }
        MaterialSymbol {
            id: searchIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
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
                    if (root.current?.customId) root.open(root.current);
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
        anchors { left: searchBox.left; right: searchBox.right; top: searchBox.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 16 }
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        model: root.matches
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool lit: ListView.isCurrentItem
            width: ListView.view.width
            height: 46
            radius: Appearance.rounding.container
            color: lit ? Appearance.colors.colLayer1Hover : "transparent"
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered) list.currentIndex = row.index
            }
            TapHandler { onTapped: row.modelData.customId ? root.open(row.modelData) : root.add(row.modelData) }
            IconImage {
                id: rowIcon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                implicitSize: 26
                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
            }
            StyledText {
                anchors { left: rowIcon.right; leftMargin: 12; right: rowTrail.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: row.modelData.name
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            Row { // What it is; while lit, that a click adds it
                id: rowTrail
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!row.modelData.customId
                    text: "check"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.customId ? Translation.tr("In your library") : row.lit ? Translation.tr("Click to add")
                        : row.modelData.isGame ? Translation.tr("Game") : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: row.lit && !row.modelData.customId ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
            }
        }
    }
    SheetEdgeFade {
        anchors { left: list.left; right: list.right; bottom: list.bottom }
        height: 24
        reversed: true
        sheetColor: root.backgroundColor
        active: !list.atYEnd
    }
    SheetEmptyState {
        anchors.centerIn: list
        visible: root.matches.length === 0
        icon: "search_off"
        text: Translation.tr("No apps match")
        hint: ""
    }
}
