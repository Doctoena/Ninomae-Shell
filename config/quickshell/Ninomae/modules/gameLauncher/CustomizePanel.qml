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
 * logo (from SteamGridDB, or a file) and the particle effect over its page. One tab each.
 * On the left, a preview as the page shows it: hover a result or an effect to see it there first. A click
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

    SheetHeader {
        id: header
        icon: "palette"
        title: Translation.tr("Customize")
        subtitle: root.game?.name ?? ""
        onCloseRequested: root.closeRequested()
        extras: Rectangle { // The tabs
            width: tabRow.width + 8; height: 36; radius: Appearance.rounding.segment
            color: Appearance.colors.colLayer1
            Row {
                id: tabRow
                anchors.centerIn: parent
                Repeater {
                    model: root.tabs
                    Rectangle {
                        id: tabPill
                        required property var modelData
                        readonly property bool active: root.tab === modelData.key
                        width: tabContent.implicitWidth + 28; height: 28; radius: Appearance.rounding.segment
                        color: active ? Appearance.colors.colPrimary : tabMa.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Row {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tabPill.modelData.icon; iconSize: 16
                                fill: tabPill.active ? 1 : 0
                                color: tabPill.active ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tabPill.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: tabPill.active ? Font.DemiBold : Font.Medium
                                color: tabPill.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tab = tabPill.modelData.key
                        }
                    }
                }
            }
        }
    }

    // ── Left: the preview, what it is, and its buttons ──
    ColumnLayout {
        id: side
        anchors { top: header.bottom; topMargin: 18; left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 20 }
        width: 380
        spacing: 14

        Item { // The card keeps its height across tabs; a cover sits in the middle of it
            Layout.fillWidth: true
            Layout.preferredHeight: 214
            ClippingRectangle {
                id: preview
                anchors.centerIn: parent
                width: root.tab === "grid" ? Math.round(height * 2 / 3) : parent.width
                height: parent.height
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                MaterialSymbol { // Nothing to show
                    anchors.centerIn: parent
                    visible: (root.tab === "grid" ? coverImage : heroImage).status !== Image.Ready
                    text: root.tab === "grid" ? "photo_library" : "panorama"
                    iconSize: 40
                    color: Appearance.colors.colSubtext
                }
                Image { // The background, as behind the page
                    id: heroImage
                    anchors.fill: parent
                    visible: root.tab !== "grid"
                    source: visible ? root.previewHero : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    retainWhileLoading: true
                    sourceSize.width: 800
                }
                Loader { // The effect, live: the hovered one, else the one in use
                    anchors.fill: parent
                    active: root.tab === "effect" && root.shownEffect !== "none" && root.shown
                    sourceComponent: GameParticles {
                        // No game id: it would use the saved choice instead of the one shown here
                        gameName: root.game?.name ?? ""
                        forcePreset: root.shownEffect === "auto" ? "" : root.shownEffect
                        imageSource: root.previewHero
                        densityScale: root.density
                        opacityScale: root.effectOpacity
                    }
                }
                Image { // The logo over it, as on the page
                    anchors.centerIn: parent
                    width: parent.width * 0.7; height: parent.height * 0.45
                    visible: root.tab !== "grid" && root.previewLogo !== ""
                    source: visible ? root.previewLogo : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    retainWhileLoading: true
                    sourceSize.width: 600
                }
                Image { // The cover, as in the library
                    id: coverImage
                    anchors.fill: parent
                    visible: root.tab === "grid"
                    source: visible ? root.previewCover : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    retainWhileLoading: true
                    sourceSize.width: 400
                }
                Rectangle { // Whether this is the hovered one or the one in use
                    anchors { left: parent.left; top: parent.top; margins: 10 }
                    readonly property bool hovering: root.hoverArt !== "" || root.hoverEffect !== ""
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
        }

        RowLayout { // What it is: custom or the game's own
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                text: root.tab === "effect" ? root.effectLabel(root.effectNow) : root.tabs.find(t => t.key === root.tab)?.label ?? ""
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            SheetInfoChip {
                icon: (root.tab === "effect" ? root.effectNow !== "auto" : root.isCustom) ? "edit" : "verified"
                text: root.tab === "effect" ? (root.effectNow !== "auto" ? Translation.tr("Chosen") : Translation.tr("From the game's name"))
                    : root.isCustom ? Translation.tr("Custom") : Translation.tr("The game's own")
            }
            Item { Layout.fillWidth: true }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.tab === "hero" ? Translation.tr("Behind the game's page, and its colours tint the particles.")
                : root.tab === "grid" ? Translation.tr("The game's tile in the library.")
                : root.tab === "logo" ? Translation.tr("Over the background, in place of the game's name.")
                : Translation.tr("Drifts over the background. Hover one to try it here.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        EffectSlider { // How many
            visible: root.tab === "effect" && root.effectNow !== "none"
            label: Translation.tr("Amount")
            value: root.density
            from: 0.25; to: 2
            onMoved: v => root.density = v
            onReleased: root.saveTweak()
        }
        EffectSlider { // How strong
            visible: root.tab === "effect" && root.effectNow !== "none"
            label: Translation.tr("Strength")
            value: root.effectOpacity
            from: 0.3; to: 1.2
            onMoved: v => root.effectOpacity = v
            onReleased: root.saveTweak()
        }
        Item { Layout.fillHeight: true }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            RippleButton {
                visible: root.isArt
                Layout.fillWidth: true
                implicitHeight: 40; buttonRadius: Appearance.rounding.container
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: root.chooseFile()
                contentItem: Row {
                    anchors.centerIn: parent; spacing: 8
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "folder_open"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: Translation.tr("Choose file"); font.weight: Font.Medium; color: Appearance.colors.colOnLayer1 }
                }
            }
            RippleButton {
                visible: root.isCustom
                Layout.fillWidth: true
                implicitHeight: 40; buttonRadius: Appearance.rounding.container
                colBackground: ColorUtils.transparentize(Appearance.colors.colError, 0.88)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.8)
                colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.65)
                onClicked: root.reset()
                contentItem: Row {
                    anchors.centerIn: parent; spacing: 8
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "restart_alt"; iconSize: 18; color: Appearance.colors.colError }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tab === "effect" ? Translation.tr("Reset effect") : Translation.tr("Reset")
                        font.weight: Font.Medium; color: Appearance.colors.colError
                    }
                }
            }
        }
    }

    // ── Right: SteamGridDB's art for the tab, or the effects ──
    RowLayout { // Search SteamGridDB by another name (a non-Steam game it matched wrongly, or another game's art)
        id: searchRow
        visible: root.isArt && root.hasKey
        anchors { top: header.bottom; topMargin: 18; left: side.right; leftMargin: 25; right: parent.right; rightMargin: 19 }
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1
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
        anchors { top: searchRow.visible ? searchRow.bottom : header.bottom; topMargin: searchRow.visible ? 10 : 18; bottom: parent.bottom; bottomMargin: 12; left: side.right; leftMargin: 20; right: parent.right; rightMargin: 14 }

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
                    Rectangle { // Downloading it, or in use
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        visible: cell.inUse || cell.applying
                        width: 26; height: 26; radius: 13
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: cell.applying ? "progress_activity" : "check"
                            iconSize: 16; fill: 1
                            color: Appearance.colors.colOnPrimary
                            RotationAnimation on rotation { running: cell.applying; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                }
                Rectangle { // Hover ring, as the library's tiles
                    anchors { fill: tile; margins: -3 }
                    radius: tile.radius + 3
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
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
