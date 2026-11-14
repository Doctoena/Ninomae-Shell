import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

/**
 * A game's look, in a panel growing up out of the launcher (LauncherTopPanel): its background, cover and
 * logo (from SteamGridDB, or a file) and the particle effect over its page.
 * On the left, a preview of the part as the page shows it (the cover between its neighbours in the library),
 * and the four parts as joined rows, which pick what the right side shows. Hover a result or an effect to try
 * it there; a click
 * applies it and the panel stays open, so the page below shows it too. Each art tab's results are fetched
 * once per opening, a page at a time (Load more), for the game or a name searched instead. The effect's
 * amount and strength are per game too. Keys: ←/→ switch tabs, ↑/↓ scroll, Esc closes.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1240
    panelHeight: 600
    clipContent: true

    readonly property var tabs: [
        { key: "hero", label: Translation.tr("Background"), icon: "panorama" },
        { key: "grid", label: Translation.tr("Cover"), icon: "photo_library" },
        { key: "logo", label: Translation.tr("Logo"), icon: "title" },
        { key: "effect", label: Translation.tr("Effect"), icon: "auto_awesome" }
    ]
    property string tab: "hero" // hero, grid, logo (art, as SteamGridDB names them), effect (particles)
    readonly property bool isArt: tab !== "effect"
    readonly property bool hasKey: GameLauncherService.steamGridDbApiKey.length > 0

    // ── What the game uses now (as GameDetailsPanel and the grid pick it) ──
    readonly property var custom: {
        const _ = GameLauncherService.customArtRevision;
        return game ? GameLauncherService.getCustomArt(game.id) : {};
    }
    function _file(p) { return p && p.startsWith("/") ? p : ""; }
    readonly property string heroNow: _file(custom.heroArt) || _file(game?.heroArt) || (game?.derivedHeroArt ?? "")
    readonly property string coverNow: _file(custom.boxArt) || _file(game?.boxArt)
    readonly property string logoNow: _file(custom.logo) || _file(game?.icon)
    readonly property string effectNow: {
        const _ = GameLauncherService.particleOverridesRevision;
        return (game ? GameLauncherService.getParticleOverride(game.id) : "") || "auto";
    }
    // The effect's amount and strength: the saved ones, or the sliders' while they're moved
    readonly property var tweakNow: {
        const _ = GameLauncherService.particleTweaksRevision;
        return GameLauncherService.getParticleTweak(game?.id ?? "");
    }
    property real density: tweakNow.density
    property real effectOpacity: tweakNow.opacity
    function saveTweak() { if (game) GameLauncherService.setParticleTweak(game.id, density, effectOpacity); }
    readonly property bool tweaked: Math.abs(tweakNow.density - 1) >= 0.01 || Math.abs(tweakNow.opacity - 1) >= 0.01
    readonly property bool isCustom: tab === "hero" ? _file(custom.heroArt) !== ""
        : tab === "grid" ? _file(custom.boxArt) !== ""
        : tab === "logo" ? _file(custom.logo) !== ""
        : effectNow !== "auto" || tweaked

    // ── Hovered for the preview: a result's thumbnail, or an effect ──
    property string hoverArt: ""
    property string hoverEffect: ""
    readonly property bool trying: hoverArt !== "" || hoverEffect !== "" // Hovering one: the preview shows it
    readonly property string shownEffect: hoverEffect || effectNow
    function _src(p) { return !p ? "" : p.startsWith("/") ? "file://" + p : p; }
    readonly property string previewHero: _src(tab === "hero" && hoverArt ? hoverArt : heroNow)
    readonly property string previewLogo: _src(tab === "logo" && hoverArt ? hoverArt : logoNow)
    readonly property string previewCover: _src(tab === "grid" && hoverArt ? hoverArt : coverNow)

    // ── SteamGridDB results: fetched the first time a tab shows, kept while the panel is open ──
    // Per tab and search: { results, hasMore, matched }
    property string query: "" // A name searched instead of the game's own, for all three art tabs
    property var cache: ({})
    readonly property string cacheKey: tab + "|" + query
    readonly property var entry: cache[cacheKey]
    readonly property var results: entry?.results ?? []
    readonly property bool loading: isArt && hasKey && entry === undefined
    // The service's search is this one (another tab's may be loaded in it): only then can it fetch the next page
    readonly property bool serviceOnThis: GameLauncherService.sgdbArtType === tab && GameLauncherService.sgdbQuery === query
    readonly property bool loadingMore: entry !== undefined && GameLauncherService.sgdbLoading && serviceOnThis
    // Read from tab and query, not entry / serviceOnThis: run from onTabChanged, those can still be the last tab's
    function fetch() {
        if (tab === "effect" || !hasKey || !game || cache[tab + "|" + query] !== undefined) return;
        if (GameLauncherService.sgdbLoading && GameLauncherService.sgdbArtType === tab && GameLauncherService.sgdbQuery === query)
            return; // Already on its way
        GameLauncherService.fetchSteamGridDbArt(game, tab, query);
    }
    property string _moreAfter: "" // Fetch the next page once this search has loaded again
    function loadMore() {
        const key = tab + "|" + query;
        if (!cache[key]?.hasMore || GameLauncherService.sgdbLoading) return;
        if (GameLauncherService.sgdbArtType === tab && GameLauncherService.sgdbQuery === query) GameLauncherService.fetchMoreSteamGridDbArt();
        else { _moreAfter = key; GameLauncherService.fetchSteamGridDbArt(game, tab, query); } // Its first page again, then more
    }
    function search(name) { query = name.trim(); fetch(); }
    Connections {
        target: GameLauncherService
        function onSgdbLoadingChanged() {
            if (GameLauncherService.sgdbLoading || !root.shown) return;
            const key = GameLauncherService.sgdbArtType + "|" + GameLauncherService.sgdbQuery;
            // A page added to what's shown: keep the place (a new list puts a GridView back at the top)
            if (key === root.cacheKey && root.cache[key] !== undefined) artGrid.keepY = artGrid.contentY;
            const c = Object.assign({}, root.cache);
            c[key] = { results: GameLauncherService.sgdbResults, hasMore: GameLauncherService.sgdbHasMore,
                       matched: GameLauncherService.sgdbMatchedName };
            root.cache = c;
            if (root._moreAfter === key) { root._moreAfter = ""; GameLauncherService.fetchMoreSteamGridDbArt(); }
        }
        function onSteamGridDbApiKeyChanged() { root.cache = ({}); root.fetch(); }
        function onCustomArtRevisionChanged() { // A download done: that result is the one in use
            if (root.applyingUrl === "") return;
            const a = Object.assign({}, root.appliedUrl);
            a[root.applyingTab] = root.applyingUrl;
            root.appliedUrl = a;
            root.applyingUrl = "";
        }
    }
    onTabChanged: { hoverArt = ""; hoverEffect = ""; fetch(); }
    onQueryChanged: hoverArt = ""
    onShownChanged: {
        if (!shown) return;
        KeyringStorage.fetchKeyringData(); // A key added in Settings (its own process) since
        fetch();
    }

    // ── Applying: the result being downloaded, and the ones in use (this opening) ──
    property string applyingUrl: ""
    property string applyingTab: ""
    property var appliedUrl: ({})
    function apply(result) {
        if (!game || applyingUrl !== "") return;
        applyingUrl = result.url;
        applyingTab = tab;
        applyTimeout.restart();
        GameLauncherService.applySteamGridDbArt(game, result.url, tab);
    }
    Timer { id: applyTimeout; interval: 35000; onTriggered: root.applyingUrl = "" } // The download failed
    function chooseFile() { if (game) GameLauncherService.launchFilePicker(game.id, tab === "grid" ? "boxart" : tab); }
    function reset() {
        if (!game) return;
        if (tab === "hero") GameLauncherService.clearCustomHeroArt(game.id);
        else if (tab === "grid") GameLauncherService.clearCustomBoxArt(game.id);
        else if (tab === "logo") GameLauncherService.clearCustomLogo(game.id);
        else {
            GameLauncherService.setParticleOverride(game.id, "auto");
            GameLauncherService.setParticleTweak(game.id, 1, 1);
            density = 1; effectOpacity = 1; // The sliders too (moving them set these by hand)
        }
        const a = Object.assign({}, appliedUrl);
        delete a[tab];
        appliedUrl = a;
    }

    function handleKey(key) {
        if (key === Qt.Key_Escape) { closeRequested(); return true; }
        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            const i = tabs.findIndex(t => t.key === tab);
            tab = tabs[(i + (key === Qt.Key_Left ? tabs.length - 1 : 1)) % tabs.length].key;
            return true;
        }
        if (key === Qt.Key_Up || key === Qt.Key_Down) {
            const v = isArt ? artGrid : effectFlick;
            if (!v.visible) return true;
            const maxY = Math.max(0, v.contentHeight - v.height);
            v.contentY = Math.max(0, Math.min(v.contentY + (key === Qt.Key_Up ? -1 : 1) * 120, maxY));
            return true;
        }
        return false;
    }

    // The particle effects (GameParticles' presets)
    readonly property var effects: [
        { key: "auto", label: Translation.tr("Auto"), icon: "hdr_auto" },
        { key: "ambient", label: Translation.tr("Ambient"), icon: "blur_on" },
        { key: "fog", label: Translation.tr("Fog"), icon: "foggy" },
        { key: "ash", label: Translation.tr("Ash"), icon: "volcano" },
        { key: "snow", label: Translation.tr("Snow"), icon: "ac_unit" },
        { key: "rain", label: Translation.tr("Rain"), icon: "rainy" },
        { key: "storm", label: Translation.tr("Storm"), icon: "thunderstorm" },
        { key: "sakura", label: Translation.tr("Sakura"), icon: "filter_vintage" },
        { key: "leaves", label: Translation.tr("Leaves"), icon: "eco" },
        { key: "fireflies", label: Translation.tr("Fireflies"), icon: "flare" },
        { key: "bubbles", label: Translation.tr("Bubbles"), icon: "bubble_chart" },
        { key: "embers", label: Translation.tr("Embers"), icon: "whatshot" },
        { key: "tracers", label: Translation.tr("Tracers"), icon: "trending_flat" },
        { key: "wasteland", label: Translation.tr("Dust storm"), icon: "air" },
        { key: "magic", label: Translation.tr("Magic"), icon: "auto_fix_high" },
        { key: "cavern", label: Translation.tr("Cavern"), icon: "diamond" },
        { key: "stars", label: Translation.tr("Stars"), icon: "star" },
        { key: "warp", label: Translation.tr("Warp"), icon: "rocket_launch" },
        { key: "arcs", label: Translation.tr("Arcs"), icon: "bolt" },
        { key: "neon", label: Translation.tr("Neon"), icon: "nightlife" },
        { key: "circuit", label: Translation.tr("Circuit"), icon: "memory" },
        { key: "pixel", label: Translation.tr("Pixel"), icon: "grid_view" },
        { key: "none", label: Translation.tr("None"), icon: "visibility_off" }
    ]
    function effectLabel(key) { return effects.find(e => e.key === key)?.label ?? key; }

    // ── Along the top of the right side: the search (or, for the effect, its amount and strength) and Close ──
    Item {
        id: topRow
        anchors { top: parent.top; topMargin: 16; left: side.right; leftMargin: 20; right: parent.right; rightMargin: 16 }
        height: 38
        SheetIconButton {
            id: closeButton
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            grouped: false
            iconName: "close"
            tip: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
        RowLayout { // The effect's sliders, where the art tabs have their search
            anchors { left: parent.left; right: closeButton.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            visible: root.tab === "effect" && root.effectNow !== "none"
            spacing: 24
            EffectSlider {
                label: Translation.tr("Amount")
                value: root.density
                from: 0.25; to: 2
                onMoved: v => root.density = v
                onReleased: root.saveTweak()
            }
            EffectSlider {
                label: Translation.tr("Strength")
                value: root.effectOpacity
                from: 0.3; to: 1.2
                onMoved: v => root.effectOpacity = v
                onReleased: root.saveTweak()
            }
        }
    }

    // ── Left: the page as it will look, the four parts, and their buttons ──
    ColumnLayout {
        id: side
        anchors { top: parent.top; topMargin: 16; left: parent.left; leftMargin: 16 }
        width: 420
        spacing: 10

        ClippingRectangle { // The preview: the same card on every tab, its contents moving between them
            id: preview
            Layout.fillWidth: true
            Layout.preferredHeight: 224
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            MaterialSymbol { // Nothing to show
                anchors.centerIn: parent
                visible: root.tab !== "grid" && heroImage.status !== Image.Ready
                text: "panorama"
                iconSize: 40
                color: Appearance.colors.colSubtext
            }
            Image { // The background, as behind the page: it eases back and out for the cover, dims under the logo
                id: heroImage
                anchors.fill: parent
                source: root.previewHero
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                sourceSize.width: 800
                opacity: root.tab === "grid" ? 0 : 1
                scale: root.tab === "grid" ? 1.08 : 1
                Behavior on opacity { PreviewAnim {} }
                Behavior on scale { PreviewAnim {} }
            }
            Rectangle { // Dims the background while the logo is the part being changed
                anchors.fill: parent
                color: "black"
                opacity: root.tab === "logo" ? 0.35 : 0
                Behavior on opacity { PreviewAnim {} }
            }
            Loader { // The effect, live: the hovered one, else the one in use; fades in and out with its tab
                anchors.fill: parent
                active: (root.tab === "effect" || opacity > 0) && root.shownEffect !== "none" && root.shown
                opacity: root.tab === "effect" ? 1 : 0
                Behavior on opacity { PreviewAnim {} }
                sourceComponent: GameParticles {
                    // No game id: it would use the saved choice instead of the one shown here
                    gameName: root.game?.name ?? ""
                    storeTags: root.game?.storeTags ?? [] // Auto here picks as the page does
                    forcePreset: root.shownEffect === "auto" ? "" : root.shownEffect
                    imageSource: root.previewHero
                    densityScale: root.density
                    opacityScale: root.effectOpacity
                }
            }
            Image { // The logo over it, as on the page: a little bigger while it's the part being changed
                anchors.centerIn: parent
                width: parent.width * 0.7; height: parent.height * 0.45
                visible: root.previewLogo !== "" && opacity > 0
                source: root.previewLogo
                opacity: root.tab === "grid" ? 0 : 1
                scale: root.tab === "logo" ? 1.1 : root.tab === "grid" ? 0.85 : 1
                Behavior on opacity { PreviewAnim {} }
                Behavior on scale { PreviewAnim {} }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                retainWhileLoading: true
                sourceSize.width: 600
            }
            Row { // The cover as in the library: between the games beside it there, faded. It rises into place,
                // the neighbours sliding out from behind it
                id: coverRow
                anchors.centerIn: parent
                property real away: root.tab === "grid" ? 0 : 1 // 0 in place, 1 tucked away
                Behavior on away { PreviewAnim {} }
                visible: away < 1
                opacity: 1 - away
                spacing: 12
                NeighbourCover {
                    game: root.neighbours[0] ?? null
                    transform: Translate { x: (108 + 12) * 0.6 * coverRow.away }
                }
                Item {
                    width: 132; height: 198
                    anchors.verticalCenter: parent.verticalCenter
                    z: 1
                    transform: [Translate { y: 18 * coverRow.away }, Scale { origin.x: 66; origin.y: 99; xScale: 1 - 0.08 * coverRow.away; yScale: xScale }]
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: coverImage.status !== Image.Ready
                            text: "photo_library"; iconSize: 32
                            color: Appearance.colors.colSubtext
                        }
                        Image {
                            id: coverImage
                            anchors.fill: parent
                            source: root.tab === "grid" ? root.previewCover : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            retainWhileLoading: true
                            sourceSize.width: 264
                        }
                    }
                    Rectangle {
                        anchors { fill: parent; margins: -3 }
                        radius: Appearance.rounding.small + 3
                        color: "transparent"
                        border.width: 2; border.color: Appearance.colors.colPrimary
                    }
                }
                NeighbourCover {
                    game: root.neighbours[1] ?? null
                    transform: Translate { x: -(108 + 12) * 0.6 * coverRow.away }
                }
            }
            Rectangle { // Whether this is the hovered one or the one in use
                anchors { left: parent.left; top: parent.top; margins: 10 }
                readonly property bool hovering: root.trying
                width: previewLabel.implicitWidth + 16; height: 24
                radius: Appearance.rounding.chip
                color: hovering ? Appearance.colors.colPrimary : Qt.rgba(0, 0, 0, 0.55)
                StyledText {
                    id: previewLabel
                    anchors.centerIn: parent
                    text: parent.hovering ? Translation.tr("Preview") : Translation.tr("In use")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: parent.hovering ? Appearance.colors.colOnPrimary : "white"
                }
            }
        }

        // The four parts, joined: the one being changed tinted, each saying where it comes from
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            Repeater {
                model: root.tabs
                RippleButton {
                    id: partRow
                    required property var modelData
                    required property int index
                    readonly property bool active: root.tab === modelData.key
                    readonly property bool settingsRow: true
                    Layout.fillWidth: true
                    implicitHeight: 44
                    GroupCorners { id: partCorners; item: partRow }
                    buttonRadiusTop: partCorners.top
                    buttonRadiusBottom: partCorners.bottom
                    padding: 0
                    colBackground: active ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
                    colBackgroundHover: active ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: root.tab = modelData.key
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 14 }
                        spacing: 10
                        Rectangle {
                            implicitWidth: 30; implicitHeight: 30; radius: 8
                            color: partRow.active ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75) : Appearance.colors.colLayer4
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: partRow.modelData.icon; iconSize: 17; fill: 1
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            text: partRow.modelData.label
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: root.partSource(partRow.modelData.key)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: partRow.active && root.trying ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        // Choose file (art) and back to the game's own, joined
        RowLayout {
            Layout.fillWidth: true
            spacing: 3
            PartButton {
                visible: root.isArt
                first: true; last: !resetPart.visible
                symbol: "folder_open"; caption: Translation.tr("Choose file")
                onClicked: root.chooseFile()
            }
            PartButton {
                id: resetPart
                visible: root.isCustom
                first: !root.isArt; last: true
                symbol: "restart_alt"
                caption: root.tab === "effect" ? Translation.tr("Back to Auto") : Translation.tr("Back to the game's own")
                onClicked: root.reset()
            }
        }
    }
    // The games beside this one in the library (as the grid shows it now), for the cover's preview
    readonly property var neighbours: {
        if (!game || tab !== "grid") return [];
        const list = GameLauncherService.filteredGames.length > 2 ? GameLauncherService.filteredGames : GameLauncherService.games;
        const i = list.findIndex(g => g.id === game.id);
        const n = list.length;
        if (n < 2) return [];
        const at = i < 0 ? 0 : i;
        return [list[(at - 1 + n) % n], list[(at + 1) % n]].filter(g => g.id !== game.id);
    }
    // The preview's moves between parts, on the shell's emphasized curve
    component PreviewAnim: NumberAnimation {
        duration: 320
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }
    component NeighbourCover: ClippingRectangle {
        id: neighbour
        property var game
        width: 108; height: 162
        anchors.verticalCenter: parent.verticalCenter
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        opacity: 0.35
        visible: !!game
        Image {
            anchors.fill: parent
            source: {
                if (!neighbour.game) return "";
                const _ = GameLauncherService.customArtRevision;
                const c = GameLauncherService.getCustomArt(neighbour.game.id);
                return root._src(root._file(c.boxArt) || root._file(neighbour.game.boxArt));
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 216
        }
    }
    // Where each part comes from, for its row ("Trying one" while one is hovered)
    function partSource(key) {
        if (key === tab && trying) return Translation.tr("Trying one");
        if (key === "effect") return effectNow === "auto" ? Translation.tr("Auto · from the art") : effectLabel(effectNow);
        const c = key === "hero" ? custom.heroArt : key === "grid" ? custom.boxArt : custom.logo;
        return _file(c) !== "" ? Translation.tr("Custom") : Translation.tr("The game's own");
    }
    component PartButton: RippleButton {
        id: partButton
        property string symbol
        property string caption
        property bool first: true
        property bool last: true
        Layout.fillWidth: true
        implicitHeight: 40
        padding: 0
        buttonRadiusLeft: first ? Appearance.rounding.small : Appearance.rounding.joined
        buttonRadiusRight: last ? Appearance.rounding.small : Appearance.rounding.joined
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        contentItem: Item {
            Row {
                anchors.centerIn: parent
                spacing: 7
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: partButton.symbol; iconSize: 17; color: Appearance.colors.colOnLayer3 }
                StyledText { anchors.verticalCenter: parent.verticalCenter; text: partButton.caption; font.weight: Font.Medium; color: Appearance.colors.colOnLayer3 }
            }
        }
    }

    // ── Right: SteamGridDB's art for the tab, or the effects ──
    RowLayout { // Search SteamGridDB by another name (a non-Steam game it matched wrongly, or another game's art)
        id: searchRow
        visible: root.isArt && root.hasKey
        anchors { verticalCenter: topRow.verticalCenter; left: topRow.left; right: topRow.right; rightMargin: 34 + 8 }
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer3
            border.width: searchField.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary
            MaterialSymbol {
                id: searchIcon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "search"; iconSize: 18
                color: Appearance.colors.colSubtext
            }
            ToolbarTextField {
                id: searchField
                anchors { left: searchIcon.right; leftMargin: 4; right: parent.right; rightMargin: 10; top: parent.top; bottom: parent.bottom }
                colBackground: "transparent"
                placeholderText: Translation.tr("Search SteamGridDB for another name")
                font.pixelSize: Appearance.font.pixelSize.small
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.search(text); event.accepted = true; }
                    else if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
                }
            }
        }
        StyledText { // Whose art this is, for a search
            visible: root.query !== "" && (root.entry?.matched ?? "") !== ""
            Layout.maximumWidth: 220
            elide: Text.ElideRight
            text: Translation.tr("Art for %1").arg(root.entry?.matched ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RippleButton { // Back to the game's own
            visible: root.query !== ""
            implicitHeight: 38
            implicitWidth: backRow.implicitWidth + 28
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: { searchField.text = ""; root.search(""); }
            contentItem: Row {
                id: backRow
                anchors.centerIn: parent; spacing: 6
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "undo"; iconSize: 16; color: Appearance.colors.colOnLayer1 }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Back to %1").arg(root.game?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    Item {
        id: content
        anchors { top: topRow.bottom; topMargin: 7; bottom: parent.bottom; bottomMargin: 12; left: side.right; leftMargin: 15; right: parent.right; rightMargin: 11 }

        // Art: states first
        SheetEmptyState {
            anchors.centerIn: parent
            visible: root.isArt && !root.hasKey
            icon: "key"
            text: Translation.tr("Needs a SteamGridDB API key")
            hint: Translation.tr("It's free: make one on SteamGridDB, then paste it in Settings → Games")
        }
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 70 }
            visible: root.isArt && !root.hasKey
            spacing: 8
            RippleButton {
                implicitHeight: 36; implicitWidth: getKeyLabel.implicitWidth + 32; buttonRadius: 12
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: Qt.openUrlExternally("https://www.steamgriddb.com/profile/preferences/api")
                contentItem: Item { StyledText { id: getKeyLabel; anchors.centerIn: parent; text: Translation.tr("Get a free key"); color: Appearance.colors.colOnLayer1; font.weight: Font.Medium } }
            }
            RippleButton {
                implicitHeight: 36; implicitWidth: openSettingsLabel.implicitWidth + 32; buttonRadius: 12
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh"), "games"])
                contentItem: Item { StyledText { id: openSettingsLabel; anchors.centerIn: parent; text: Translation.tr("Open settings"); color: Appearance.colors.colOnPrimary; font.weight: Font.Medium } }
            }
        }
        SheetEmptyState {
            anchors.centerIn: parent
            visible: root.isArt && root.hasKey && (root.loading || root.results.length === 0)
            icon: root.loading ? "hourglass_empty" : "image_not_supported"
            text: root.loading ? Translation.tr("Fetching art…")
                : root.query !== "" && (root.entry?.matched ?? "") === "" ? Translation.tr("No game called “%1” on SteamGridDB").arg(root.query)
                : Translation.tr("Nothing on SteamGridDB")
            hint: root.loading ? "" : root.query !== "" ? Translation.tr("Try another name") : Translation.tr("Search another name, or choose a file")
        }

        GridView {
            id: artGrid
            anchors.fill: parent
            visible: root.isArt && root.results.length > 0
            readonly property int columns: root.tab === "grid" ? 5 : root.tab === "logo" ? 4 : 3
            cellWidth: Math.floor(width / columns)
            cellHeight: root.tab === "grid" ? Math.round(cellWidth * 1.5) : root.tab === "logo" ? Math.round(cellWidth * 0.56) : Math.round(cellWidth * 0.42)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.results
            property real keepY: -1 // Where to stay once the longer list is in (Load more)
            onModelChanged: {
                if (keepY < 0) { contentY = 0; return; } // Another tab or search: from the top
                const y = keepY;
                keepY = -1;
                Qt.callLater(() => artGrid.contentY = y);
            }
            footer: Item { // Load more: the next page of this search
                width: artGrid.width
                height: root.entry?.hasMore ? 64 : 8
                RippleButton {
                    visible: root.entry?.hasMore ?? false
                    anchors.centerIn: parent
                    implicitHeight: 40
                    implicitWidth: moreRow.implicitWidth + 36
                    buttonRadius: Appearance.rounding.full
                    enabled: !root.loadingMore
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: root.loadMore()
                    contentItem: Row {
                        id: moreRow
                        anchors.centerIn: parent; spacing: 8
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.loadingMore ? "progress_activity" : "expand_more"; iconSize: 18
                            color: Appearance.colors.colOnLayer1
                            RotationAnimation on rotation { running: root.loadingMore; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.loadingMore ? Translation.tr("Loading…") : Translation.tr("Load more")
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
            delegate: Item {
                id: cell
                required property var modelData
                width: artGrid.cellWidth
                height: artGrid.cellHeight
                readonly property bool inUse: root.appliedUrl[root.tab] === modelData.url
                readonly property bool applying: root.applyingUrl === modelData.url
                ClippingRectangle {
                    id: tile
                    anchors { fill: parent; margins: 5 }
                    radius: Appearance.rounding.small
                    color: cellMa.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                    scale: cellMa.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Image {
                        id: thumb
                        anchors { fill: parent; margins: root.tab === "logo" ? 10 : 0 }
                        source: cell.modelData.thumb
                        fillMode: root.tab === "logo" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: artGrid.cellWidth * 2
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: thumb.status === Image.Loading
                        text: "hourglass_empty"; iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle { // In use (this opening), or downloading it
                        anchors { left: parent.left; top: parent.top; margins: 8 }
                        visible: cell.inUse || cell.applying
                        width: useRow.implicitWidth + 14; height: 22
                        radius: Appearance.rounding.chip
                        color: Appearance.colors.colPrimary
                        Row {
                            id: useRow
                            anchors.centerIn: parent
                            spacing: 3
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cell.applying ? "progress_activity" : "check"
                                iconSize: 14
                                color: Appearance.colors.colOnPrimary
                                RotationAnimation on rotation { running: cell.applying; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cell.applying ? Translation.tr("Saving") : Translation.tr("In use")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
                Rectangle { // The one in use: an accent ring; under the mouse: a light one
                    anchors { fill: tile; margins: -2 }
                    radius: tile.radius + 2
                    color: "transparent"
                    border.width: 2.5
                    border.color: cell.inUse ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.2)
                    opacity: cellMa.containsMouse || cell.inUse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (containsMouse) root.hoverArt = cell.modelData.thumb;
                        else if (root.hoverArt === cell.modelData.thumb) root.hoverArt = "";
                    }
                    onClicked: root.apply(cell.modelData)
                }
                StyledToolTip {
                    text: cell.modelData.author ? Translation.tr("By %1").arg(cell.modelData.author) : ""
                    visible: cellMa.containsMouse && text !== ""
                }
            }
        }
        SheetEdgeFade {
            anchors { left: artGrid.left; right: artGrid.right; top: artGrid.top }
            height: 20
            visible: artGrid.visible
            sheetColor: root.backgroundColor
            active: !artGrid.atYBeginning
        }
        SheetEdgeFade {
            anchors { left: artGrid.left; right: artGrid.right; bottom: artGrid.bottom }
            height: 28; reversed: true
            visible: artGrid.visible
            sheetColor: root.backgroundColor
            active: !artGrid.atYEnd
        }

        // Effects
        Flickable {
            id: effectFlick
            anchors.fill: parent
            visible: !root.isArt
            contentHeight: effectGrid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            GridLayout {
                id: effectGrid
                width: effectFlick.width
                columns: 4
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: root.effects
                    RippleButton {
                        id: effectTile
                        required property var modelData
                        readonly property bool inUse: root.effectNow === modelData.key
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1 // Equal columns
                        implicitHeight: 52
                        buttonRadius: Appearance.rounding.container
                        colBackground: inUse ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                        colBackgroundHover: inUse ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                        colRipple: inUse ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
                        onHoveredChanged: {
                            if (hovered) root.hoverEffect = modelData.key;
                            else if (root.hoverEffect === modelData.key) root.hoverEffect = "";
                        }
                        onClicked: if (root.game) GameLauncherService.setParticleOverride(root.game.id, modelData.key)
                        contentItem: RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 10
                            MaterialSymbol {
                                text: effectTile.modelData.icon
                                iconSize: 20
                                fill: effectTile.inUse ? 1 : 0
                                color: effectTile.inUse ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: effectTile.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: effectTile.inUse ? Font.DemiBold : Font.Normal
                                color: effectTile.inUse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    // A labelled slider for the effect, with its value as a percentage
    component EffectSlider: RowLayout {
        id: effectSlider
        property string label
        property real value
        property real from
        property real to
        signal moved(real v)
        signal released()
        Layout.fillWidth: true
        spacing: 10
        StyledText {
            Layout.preferredWidth: 70
            text: effectSlider.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
        }
        StyledSlider {
            id: slider
            Layout.fillWidth: true
            from: effectSlider.from; to: effectSlider.to
            value: effectSlider.value
            stopIndicatorValues: [1]
            tooltipContent: `${Math.round(value * 100)}%`
            focusPolicy: Qt.NoFocus
            onMoved: effectSlider.moved(value)
            onPressedChanged: if (!pressed) effectSlider.released()
        }
        StyledText {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(effectSlider.value * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.features: { "tnum": 1 }
            color: Appearance.colors.colSubtext
        }
    }
}
