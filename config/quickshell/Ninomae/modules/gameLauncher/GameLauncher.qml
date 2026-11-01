import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
Scope {
    id: gameLauncherScope
    signal showGameRequested(var game, string sheet)
    signal showGridPanelRequested(string panel)
    function show(query, sheet) {
        const game = GameLauncherService.findGameByName(query);
        if (!game) return;
        GlobalStates.gameLauncherOpen = true;
        showGameRequested(game, sheet);
    }
    LaunchSplash { id: launchSplash }
    IpcHandler {
        target: "gameLauncher"
        function toggle(): void { GlobalStates.gameLauncherOpen = !GlobalStates.gameLauncherOpen; }
        function open(): void { GlobalStates.gameLauncherOpen = true; }
        function close(): void { GlobalStates.gameLauncherOpen = false; }
        function refresh(): void { GameLauncherService.refreshGames(); }
        // Open the launcher on a game's page (first name match, exact then partial), optionally with
        // one of its sheets: `qs -c Ninomae ipc call gameLauncher showNews terraria`
        function showGame(query: string): void { gameLauncherScope.show(query, ""); }
        function showScreenshots(query: string): void { GameLauncherService.screenshotsPage = "shots"; gameLauncherScope.show(query, "screenshots"); }
        function showClips(query: string): void { GameLauncherService.screenshotsPage = "clips"; gameLauncherScope.show(query, "screenshots"); }
        function showAchievements(query: string): void { gameLauncherScope.show(query, "achievements"); }
        function showNews(query: string): void { gameLauncherScope.show(query, "news"); }
        function showLaunchOptions(query: string): void { gameLauncherScope.show(query, "launchOptions"); }
        function showCustomize(query: string): void { gameLauncherScope.show(query, "customize"); }
        // The grid's Tags panel: `qs -c Ninomae ipc call gameLauncher showTags`
        function showTags(): void { GlobalStates.gameLauncherOpen = true; gameLauncherScope.showGridPanelRequested("tags"); }
        // The launch drawer for a game, without starting it
        function previewSplash(query: string): void {
            const game = GameLauncherService.findGameByName(query);
            if (game) launchSplash.preview(game); // Steps through every state, ending on a failure
        }
        function hideSplash(): void { launchSplash.dismiss(); }
    }
    Variants {
        id: gameLauncherVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            property var selectedGame: null
            // The game the details page shows. Kept after Back clears selectedGame, so the page can fade out
            // instead of vanishing; another game swaps in a fresh page (one tick without it)
            property var _detailsGame: null
            property bool _detailsRestart: false
            function _rebuildDetails() {
                if (!detailsLoader.item) return;
                _detailsRestart = true;
                Qt.callLater(() => { _detailsRestart = false; });
            }
            function _useDetailsGame(g) {
                if (!g || g === _detailsGame) return;
                _rebuildDetails();
                _detailsGame = g;
            }
            onSelectedGameChanged: _useDetailsGame(selectedGame)
            // Built ahead: a tile hovered (or keyed onto) for a moment gets its page made, hidden, so clicking it
            // shows at once. While the grid's up; closing the launcher lets the page go
            readonly property bool _prebuilding: GlobalStates.gameLauncherOpen && !showingDetails && !showingStats
            property var _prebuildWant: null
            function prebuild(g) { _prebuildWant = g; prebuildTimer.restart(); }
            Timer { // Not every tile a sweep across the row crosses
                id: prebuildTimer
                interval: 150
                onTriggered: if (root._prebuilding) root._useDetailsGame(root._prebuildWant)
            }
            property bool showingDetails: false
            property bool showingStats: false
            property bool _returningFromDetails: false // Suppress animations only when returning from details
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            readonly property real scaleFactor: root.screen ? Math.pow(root.screen.height / 1080.0, 0.4) : 1.0
            readonly property real tileSize: Math.round(160 * scaleFactor)
            readonly property real tileSpacing: Math.round(20 * scaleFactor)
            screen: modelData

            // ── Drawer rising out of the screen's bottom edge (same animation as the launcher,
            //    overview/SearchWidget.qml, with the blob background flipped) ──
            readonly property bool drawerWanted: GlobalStates.gameLauncherOpen && monitorIsFocused
            readonly property real drawerHiddenExtra: 60
            readonly property real drawerRadius: Appearance.rounding.windowRounding + 6
            readonly property real drawerFullHeight: animatedContainer.height
            readonly property bool drawerReady: readiness.ready // Slide only once the window is on screen
            // 0 = out, 1 = tucked below the screen edge
            property real drawerOffsetScale: (drawerWanted && drawerReady) ? 0 : 1
            Behavior on drawerOffsetScale {
                NumberAnimation {
                    duration: root.drawerWanted ? Appearance.animationCurves.drawerOpenDuration + Appearance.animationCurves.drawerLargeExtra : Appearance.animationCurves.drawerCloseDuration + Appearance.animationCurves.drawerLargeExtra
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.drawerWanted ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
                }
            }
            readonly property real drawerTop: -(drawerFullHeight + drawerHiddenExtra) * drawerOffsetScale
            readonly property real drawerY: Math.min(0, drawerTop)
            readonly property real drawerHeight: drawerFullHeight + Math.max(0, drawerTop) // Overshoot stretches
            readonly property real drawerVisibleHeight: Math.max(0, drawerY + drawerHeight)

            visible: drawerWanted || drawerOffsetScale < 1 // Stay mapped while sliding back down
            WlrLayershell.namespace: "quickshell:gamelauncher"
            WlrLayershell.layer: GameLauncherService.filePickerActive ? WlrLayer.Bottom : WlrLayer.Top
            WlrLayershell.keyboardFocus: GameLauncherService.filePickerActive ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    if (!active && !GlobalStates.gameLauncherFilePickerActive)
                        GlobalStates.gameLauncherOpen = false;
                }
            }
            Connections {
                target: GameLauncherService
                function onFilePickerActiveChanged() {
                    GlobalStates.gameLauncherFilePickerActive = GameLauncherService.filePickerActive;
                    if (GameLauncherService.filePickerActive) {
                        grab.active = false;
                    } else if (GlobalStates.gameLauncherOpen) {
                        delayedGrabTimer.start();
                    }
                }
            }
            Connections {
                target: GlobalStates
                function onGameLauncherOpenChanged() {
                    if (!GlobalStates.gameLauncherOpen) {
                        GameLauncherService.cancelFilePicker();
                        // The rest waits until the drawer has slid away (resetView): done now, the page under
                        // the closing drawer jumped to the grid (and the grid re-sorted) mid-animation
                    } else {
                        delayedGrabTimer.start();
                        if (!root.showingDetails) {
                            visibleSearchBar.forceActiveFocus();
                        }
                    }
                }
            }
            onShowingDetailsChanged: {
                if (showingDetails) gridPanel = ""; // Add a game and Tags are the grid's panels
                if (!showingDetails && GlobalStates.gameLauncherOpen) {
                    root._returningFromDetails = true;
                    // Only resort when the order could have changed
                    const sort = GameLauncherService.sortOrder;
                    if (sort === "recency" || sort === "playtime")
                        GameLauncherService.resortGames();
                    Qt.callLater(() => {
                        visibleSearchBar.forceActiveFocus();
                        root._returningFromDetails = false;
                    });
                }
            }
            onShowingStatsChanged: {
                if (!showingStats && GlobalStates.gameLauncherOpen && !showingDetails) {
                    Qt.callLater(() => { visibleSearchBar.forceActiveFocus(); });
                }
            }
            // `qs -c Ninomae ipc call gameLauncher showGame hytale`: open straight on a game's page
            Connections {
                target: gameLauncherScope
                function onShowGameRequested(game, panel) {
                    if (!root.monitorIsFocused) return;
                    root.showingStats = false;
                    root.openOnShow = panel; // First: a page built ahead reads it as it's shown
                    root.selectedGame = game;
                    root.showingDetails = true;
                }
                function onShowGridPanelRequested(panel) {
                    if (!root.monitorIsFocused) return;
                    root.showingStats = false;
                    root.showingDetails = false;
                    root.gridPanel = panel;
                }
            }
            property string openOnShow: "" // From the IPC calls: one of the page's panelTypes
            Connections {
                target: GameLauncherService
                function _refocusSearchBar() {
                    if (GlobalStates.gameLauncherOpen && !root.showingDetails && !root.showingStats)
                        Qt.callLater(() => { visibleSearchBar.forceActiveFocus(); });
                }
                function onSelectedLauncherChanged() { _refocusSearchBar(); }
                function onSortOrderChanged() { _refocusSearchBar(); }
                function onSelectedTagChanged() { _refocusSearchBar(); }
                function onLoadingChanged() { if (!GameLauncherService.loading) _refocusSearchBar(); }
            }
            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive)
                        return;
                    grab.active = GlobalStates.gameLauncherOpen;
                }
            }
            Timer {
                id: searchDebounce
                interval: 150
                property string _pendingQuery: ""
                // Spaces at the ends (or doubled) don't change what you're looking for: "fallout " used to
                // re-rank the results and drop the names without a space, so the tiles reshuffled mid-word
                onTriggered: GameLauncherService.searchQuery = _pendingQuery.trim().replace(/\s+/g, " ")
            }
            implicitWidth: root.screen ? Math.min(root.screen.width, gameLauncherBackground.width + Appearance.sizes.elevationMargin * 2) : gameLauncherBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: gameLauncherBackground.height + Appearance.sizes.elevationMargin * 2
            MouseArea {
                anchors.fill: parent; z: -1
                onClicked: { if (!GameLauncherService.filePickerActive) GlobalStates.gameLauncherOpen = false; }
            }
            Item { // Blob background, flipped so the drawer's joins meet the bottom screen edge
                id: drawerStage
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.ceil(root.drawerFullHeight * 1.12) + 40
                clip: true
                DrawerReadiness {
                    id: readiness
                    active: root.visible
                }
                DrawerBackground {
                    id: drawerBlob
                    anchors.fill: parent
                    active: root.visible
                    transform: Scale { yScale: -1; origin.y: drawerStage.height / 2 } // y = 0 is the screen edge
                    // Big panel over whatever is on screen: near-solid so busy content doesn't show through
                    fillColor: Appearance.m3colors.m3background
                    fillOpacity: 1.0
                    barHeight: 40
                    barRadius: 0
                    drawerX: animatedContainer.x
                    drawerY: root.drawerY
                    drawerWidth: animatedContainer.width
                    drawerHeight: root.drawerHeight
                    drawerRadius: Math.min(root.drawerRadius, root.drawerVisibleHeight / 2)
                    fallbackRadius: root.drawerRadius
                }
            }
            // ── The game page's Screenshots / Achievements / News / Customize / Launch options: a panel growing
            //    up out of the launcher's top edge (LauncherTopPanel), one at a time, named by the page's openPanel ──
            // A game's panel on its details page; on the grid, Add a game (the search bar's button)
            property string gridPanel: "" // "addGame" or "tags": the grid's panel open (from the search bar / tag buttons)
            readonly property string wantedTopPanel: root.showingDetails ? (detailsLoader.item?.openPanel ?? "")
                : root.gridPanel
            property string _topPanelLoaded: "" // Stays set while the closing slide plays
            property var _topPanelGame: null    // Kept while the launcher closes (selectedGame is cleared at once)
            // The game first: the panel is made as _topPanelLoaded changes, and loads for its game right away
            onWantedTopPanelChanged: if (wantedTopPanel !== "") { _topPanelGame = root.selectedGame; _topPanelLoaded = wantedTopPanel; }
            // Back to the grid, search cleared, once the drawer has slid away (not while it's closing)
            function resetView() {
                visibleSearchBar.text = "";
                GameLauncherService.searchQuery = "";
                GameLauncherService.selectedTag = "";
                searchDebounce.stop();
                root.showingDetails = false;
                root.showingStats = false;
                root.selectedGame = null;
                root._returningFromDetails = false;
                _launcherContainer.revealed = false;
                _sortContainer.revealed = false;
                root._topPanelLoaded = "";
                root.gridPanel = "";
                GameLauncherService.resortGames();
            }
            onVisibleChanged: if (!visible && !GlobalStates.gameLauncherOpen) resetView()
            Item {
                id: topPanelHost
                anchors { left: animatedContainer.left; right: animatedContainer.right; bottom: animatedContainer.top }
                height: topPanelLoader.item?.height ?? 0
                // Rides with the launcher's slide, so they leave as one when it closes. No fade on the whole
                // panel: like the launcher's, its background stays solid and only its contents fade
                transform: Translate { y: -root.drawerY }
                Loader {
                    id: topPanelLoader
                    // Reaches overlap px behind the launcher's top edge (see LauncherTopPanel)
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: -(item?.overlap ?? 0) }
                    active: root._topPanelLoaded !== ""
                    sourceComponent: ({ screenshots: screenshotsPanelComp, achievements: achievementsPanelComp, news: newsPanelComp,
                                       customize: customizePanelComp, launchOptions: launchOptionsPanelComp,
                                       addGame: addGamePanelComp, tags: tagsPanelComp })[root._topPanelLoaded] ?? null
                    onLoaded: {
                        // As much of the space above the launcher as there is, clear of the bar
                        item.maxHeight = Qt.binding(() => Math.min(Math.round(640 * root.scaleFactor), animatedContainer.y - Appearance.sizes.barHeight - 24));
                        item.maxWidth = Qt.binding(() => animatedContainer.width - 240);
                        // Made hidden, then shown, so it grows out. When the launcher closes it retracts into
                        // it while riding its slide: it sits above the launcher, so riding alone would leave it
                        // on screen after the launcher has gone
                        item.shown = Qt.binding(() => root._topPanelLoaded !== "" && root.wantedTopPanel === root._topPanelLoaded
                            && GlobalStates.gameLauncherOpen);
                    }
                }
                Connections {
                    target: topPanelLoader.item
                    function onCloseRequested() {
                        // The page's keys again (a box in the panel, as Launch options', may have taken them)
                        if (detailsLoader.item) { detailsLoader.item.openPanel = ""; if (root.showingDetails) detailsLoader.item.forceActiveFocus(); }
                        if (root._topPanelLoaded === "addGame" || root._topPanelLoaded === "tags") { root.gridPanel = ""; visibleSearchBar.forceActiveFocus(); }
                    }
                    function onVisibleChanged() { if (!topPanelLoader.item.visible && !topPanelLoader.item.shown) root._topPanelLoaded = ""; }
                }
                Component { id: screenshotsPanelComp; ScreenshotsPanel { game: root._topPanelGame } }
                Component { id: achievementsPanelComp; AchievementsPanel { game: root._topPanelGame } }
                Component { id: newsPanelComp; NewsPanel { game: root._topPanelGame } }
                Component { id: customizePanelComp; CustomizePanel { game: root._topPanelGame } }
                Component { id: launchOptionsPanelComp; LaunchOptionsPanel { game: root._topPanelGame } }
                Component { id: addGamePanelComp; AddGamePanel {} }
                Component { id: tagsPanelComp; TagsPanel {} }
            }
            Item {
                id: animatedContainer
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                // The screen, not the window: the window sizes itself from this, which made a binding loop
                implicitWidth: Math.min((root.screen?.width ?? 1920) - 48, Math.round(1800 * root.scaleFactor))
                property real targetHeight: (root.showingDetails || root.showingStats) ? Math.round(420 * root.scaleFactor) : Math.round(340 * root.scaleFactor) + 16 // +16: hover room inside each tile slot (GameGridItem), so tiles keep their full size
                implicitHeight: targetHeight
                Behavior on targetHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                opacity: 1 - root.drawerOffsetScale
                transform: [
                    Translate { y: -root.drawerY }, // Slides with the drawer
                    Matrix4x4 { // Wobble with the blob
                        matrix: drawerBlob.deformMatrix
                    }
                ]
                Rectangle {
                    id: gameLauncherBackground
                    anchors.fill: parent
                    color: "transparent" // The blob drawer draws the background
                    radius: Appearance.rounding.windowRounding
                    clip: true
                    focus: true
                    activeFocusOnTab: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (root.showingDetails) {
                                root.showingDetails = false;
                                root.selectedGame = null;
                            } else if (root.showingStats) {
                                root.showingStats = false;
                            } else {
                                GlobalStates.gameLauncherOpen = false;
                            }
                            event.accepted = true;
                        }
                    }
                    Item {
                        id: viewContainer
                        anchors.fill: parent
                        clip: true
                        Item {
                            id: gridView
                            anchors.fill: parent
                            opacity: (root.showingDetails || root.showingStats) ? 0.0 : 1.0
                            scale: (root.showingDetails || root.showingStats) ? 0.98 : 1.0
                            visible: true // Keep alive to preserve delegates
                            enabled: !root.showingDetails && !root.showingStats
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    radius: height / 3
                                    color: Appearance.colors.colLayer1
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        z: 2
                                        ToolbarPicker {
                                            id: _launcherContainer
                                            title: Translation.tr("Launchers")
                                            current: GameLauncherService.selectedLauncher
                                            options: [
                                                { value: "all", icon: "apps", label: Translation.tr("All launchers") },
                                                { value: "steam", icon: "cloud", label: Translation.tr("Steam") },
                                                { value: "lutris", icon: "sports_esports", label: Translation.tr("Lutris") }
                                            ]
                                            onPicked: value => GameLauncherService.selectedLauncher = value
                                        }
                                        ToolbarPicker {
                                            id: _sortContainer
                                            title: Translation.tr("Sort")
                                            current: GameLauncherService.sortOrder
                                            options: [
                                                { value: "recency", icon: "schedule", label: Translation.tr("Recent") },
                                                { value: "favorites", icon: "star", label: Translation.tr("Favorites") },
                                                { value: "playtime", icon: "timer", label: Translation.tr("Most played") },
                                                { value: "completed", icon: "check_circle", label: Translation.tr("Completed") }
                                            ]
                                            onPicked: value => GameLauncherService.sortOrder = value
                                        }
                                        // Tags: the Tags panel grows up out of the launcher (toggled while it's open); with one
                                        // picked, its name shows here, and a clear button
                                        ToolbarGroup {
                                            id: tagContainer
                                            readonly property bool open: root.gridPanel === "tags"
                                            readonly property bool active: GameLauncherService.selectedTag !== ""
                                            function toggle() { root.gridPanel = open ? "" : "tags"; }
                                            visible: GameLauncherService.allTags.length > 0
                                            IconToolbarButton {
                                                implicitHeight: 30
                                                implicitWidth: 30
                                                buttonRadius: Appearance.rounding.segment
                                                text: "sell"
                                                colText: toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                                                toggled: tagContainer.open
                                                onClicked: tagContainer.toggle()
                                                StyledToolTip { text: tagContainer.open ? Translation.tr("Close") : Translation.tr("Tags") }
                                            }
                                            StyledText { // The tag in use (opens the panel too); long names are cut short
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: tagContainer.active
                                                leftPadding: 4; rightPadding: 2
                                                width: Math.min(implicitWidth, 160)
                                                elide: Text.ElideRight
                                                text: GameLauncherService.selectedTag
                                                font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium
                                                color: Appearance.colors.colPrimary
                                                TapHandler { onTapped: tagContainer.toggle() }
                                            }
                                            ToolbarOption { // Back to every game in one click, without opening the panel
                                                visible: tagContainer.active
                                                text: "close"; tooltip: Translation.tr("Show all games")
                                                onClicked: { GameLauncherService.selectedTag = ""; if (tagContainer.open) root.gridPanel = ""; }
                                            }
                                        }
                                    }
                                // Centered search bar
                                Item {
                                    id: searchBarContainer
                                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                                    width: _focused ? 480 : 440
                                    height: 34
                                    z: 1
                                    property bool _focused: searchBarHover.hovered || visibleSearchBar.text.length > 0
                                    HoverHandler {
                                        id: searchBarHover
                                    }
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Appearance.rounding.verysmall
                                        color: searchBarContainer._focused
                                            ? Appearance.colors.colLayer2Hover
                                            : Appearance.colors.colLayer2
                                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
                                        spacing: 8
                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "search"
                                            iconSize: 20
                                            color: searchBarContainer._focused
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnSurfaceVariant
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        ToolbarTextField {
                                            id: visibleSearchBar
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            verticalAlignment: TextInput.AlignVCenter
                                            padding: 0
                                            colBackground: "transparent"
                                            placeholderText: Translation.tr("Search games...")
                                            text: ""
                                            onTextChanged: {
                                                searchDebounce._pendingQuery = text;
                                                searchDebounce.restart();
                                            }
                                            Keys.onPressed: event => {
                                                if (event.key === Qt.Key_Escape) {
                                                    GlobalStates.gameLauncherOpen = false;
                                                    event.accepted = true;
                                                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
                                                    if (gamesListView.count > 0) {
                                                        gamesListView.focusTile(0);
                                                        event.accepted = true;
                                                    }
                                                }
                                            }
                                            Component.onCompleted: {
                                                if (GlobalStates.gameLauncherOpen && !root.showingDetails) {
                                                    forceActiveFocus();
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            width: 26; height: 26
                                            radius: Appearance.rounding.chip
                                            visible: visibleSearchBar.text.length > 0
                                            color: clearMouseArea.containsMouse
                                                ? Appearance.colors.colSurfaceContainerHighestHover
                                                : Appearance.colors.colSurfaceContainerHighest
                                            opacity: visibleSearchBar.text.length > 0 ? 1.0 : 0.0
                                            scale: visibleSearchBar.text.length > 0 ? 1.0 : 0.6
                                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "close"
                                                iconSize: 14
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                            MouseArea {
                                                id: clearMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    visibleSearchBar.text = "";
                                                    visibleSearchBar.forceActiveFocus();
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            width: 1; height: 20
                                            color: Appearance.colors.colOutlineVariant
                                            opacity: 0.4
                                        }
                                        IconToolbarButton { // Any app into the library: AddGamePanel grows up out of the launcher
                                            id: addGameButton
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "library_add"
                                            toggled: root.gridPanel === "addGame"
                                            onClicked: root.gridPanel = root.gridPanel === "addGame" ? "" : "addGame"
                                            StyledToolTip { text: root.gridPanel === "addGame" ? Translation.tr("Close") : Translation.tr("Add a game") }
                                        }
                                        IconToolbarButton {
                                            id: refreshButton
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "refresh"
                                            enabled: !GameLauncherService.loading
                                            onClicked: GameLauncherService.refreshGames()
                                            RotationAnimation {
                                                id: spinAnimation
                                                target: refreshButton
                                                from: 0
                                                to: 360
                                                duration: 600
                                                easing.type: Easing.InOutCubic
                                                loops: Animation.Infinite
                                                running: GameLauncherService.loading && root.visible
                                                onStopped: {
                                                    refreshButton.rotation = 0;
                                                }
                                            }
                                            StyledToolTip {
                                                text: Translation.tr("Refresh game list")
                                            }
                                        }
                                    }
                                }
                                // Game count, and the way into Library statistics: hover tints it and slides out a label
                                Rectangle {
                                    id: statsPill
                                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    height: 34
                                    radius: height / 3
                                    clip: true // The label slides in from under the edge
                                    readonly property bool hovered: _statsPillHover.hovered
                                    // One value drives the whole reveal, so width, spacing and label move together
                                    property real reveal: hovered ? 1 : 0
                                    Behavior on reveal {
                                        NumberAnimation {
                                            duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                                        }
                                    }
                                    readonly property real _labelSpace: _statsLabel.implicitWidth + 7
                                    width: Math.round(_statsBase.implicitWidth + 24 + _labelSpace * Math.max(0, reveal)) // Overshoot only outwards
                                    color: ColorUtils.mix(ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8), Appearance.colors.colLayer2, Math.max(0, Math.min(1, reveal)))
                                    opacity: GameLauncherService.loading ? 0.0 : 1.0
                                    visible: opacity > 0
                                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    HoverHandler { id: _statsPillHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            root.showingStats = !root.showingStats;
                                            if (root.showingStats) { root.showingDetails = false; root.selectedGame = null; }
                                        }
                                    }
                                    StyledToolTip { text: Translation.tr("Library statistics") }
                                    Row { // Icon + count, pinned to the left so nothing re-centres while the pill grows
                                        id: _statsBase
                                        x: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 7
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "bar_chart"
                                            iconSize: 18
                                            fill: statsPill.reveal > 0.5 ? 1 : 0
                                            color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: {
                                                const filtered = GameLauncherService.filteredGames.length;
                                                const total = GameLauncherService.displayableCount;
                                                return filtered === total ? filtered.toString() : filtered + " / " + total;
                                            }
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.family: Appearance.font.family.numbers
                                            font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                                            font.weight: Font.Medium
                                            color: statsPill.hovered ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnSurfaceVariant
                                            Behavior on color { ColorAnimation { duration: Appearance.animationCurves.expressiveEffectsDuration } }
                                        }
                                    }
                                    StyledText { // "Stats": fades and slides in behind the count
                                        id: _statsLabel
                                        x: _statsBase.x + _statsBase.implicitWidth + 7 - 6 * (1 - statsPill.reveal)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Stats")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colPrimary
                                        opacity: Math.max(0, Math.min(1, statsPill.reveal * 1.6 - 0.4))
                                    }
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Rectangle {
                                    id: gamesBackground
                                    anchors.fill: parent
                                    color: Appearance.colors.colLayer1
                                    radius: Appearance.rounding.normal
                                    clip: true
                                    property real _gridOpacity: 1.0
                                    Connections {
                                        target: GameLauncherService
                                        // Only blank the grid when there's nothing to show yet;
                                        // background refreshes keep the current games on screen
                                        property bool _faded: false
                                        function onLoadingChanged() {
                                            if (GameLauncherService.loading) {
                                                if (gamesListView.count === 0) {
                                                    _faded = true;
                                                    gridFadeOut.start();
                                                }
                                            } else if (_faded) {
                                                _faded = false;
                                                gridFadeIn.start();
                                            }
                                        }
                                    }
                                    NumberAnimation {
                                        id: gridFadeOut
                                        target: gamesBackground
                                        property: "_gridOpacity"
                                        to: 0.0
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                    SequentialAnimation {
                                        id: gridFadeIn
                                        PauseAnimation { duration: 80 }
                                        ScriptAction {
                                            script: {
                                                gamesListView.positionViewAtBeginning();
                                            }
                                        }
                                        NumberAnimation {
                                            target: gamesBackground
                                            property: "_gridOpacity"
                                            to: 1.0
                                            duration: 350
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    ListView {
                                        id: gamesListView
                                        anchors.centerIn: parent
                                        readonly property int _maxVisible: 9
                                        readonly property real _maxWidth: _maxVisible * root.tileSize + (_maxVisible - 1) * spacing
                                        readonly property real _fitWidth: Math.min(parent.width - 10, _maxWidth, contentWidth)
                                        width: _fitWidth
                                        // Scrolling, measured from originX: adding and removing tiles while filtering moves
                                        // where the content starts, so it isn't always 0. Treating it as 0 shifted a row
                                        // that fits (typing "fallout", then scrolling) off its own tiles
                                        readonly property bool scrollable: contentWidth > _fitWidth + 1 // Not while the width eases
                                        readonly property real minScrollX: originX
                                        readonly property real maxScrollX: originX + Math.max(0, contentWidth - width)
                                        function clampScroll(x) { return scrollable ? Math.max(minScrollX, Math.min(x, maxScrollX)) : minScrollX; }
                                        function scrollTo(x) { snapAnimation.to = clampScroll(x); snapAnimation.restart(); }
                                        // Keyboard focus, tile by tile: the row scrolls just enough to show the tile. It didn't
                                        // scroll at all, so focus went off the row's end (where tiles fade out) and stopped at
                                        // the last tile the view had made
                                        function focusTile(i) {
                                            if (i < 0 || i >= count) return;
                                            let item = itemAtIndex(i);
                                            if (!item) { positionViewAtIndex(i, ListView.Contain); item = itemAtIndex(i); }
                                            if (!item) return;
                                            if (item.x < contentX) scrollTo(item.x);
                                            else if (item.x + item.width > contentX + width) scrollTo(item.x + item.width - width);
                                            item.forceActiveFocus();
                                        }
                                        function openGame(game) {
                                            root.selectedGame = game;
                                            root.showingDetails = true;
                                            GameLauncherService.updateAccessData(game.id);
                                        }
                                        interactive: scrollable
                                        Connections { // A new search starts at the first match (the old full rebuild did this by itself)
                                            target: GameLauncherService
                                            function onSearchQueryChanged() { Qt.callLater(() => gamesListView.scrollTo(gamesListView.minScrollX)); }
                                        }
                                        onScrollableChanged: if (!scrollable) { snapAnimation.stop(); contentX = minScrollX; }
                                        height: parent.height - 20
                                        orientation: ListView.Horizontal
                                        spacing: root.tileSpacing
                                        // Optimization: Dynamic cacheBuffer — larger when flicking, smaller when idle
                                        cacheBuffer: flicking ? root.tileSize * 8 : root.tileSize * 3
                                        clip: false; snapMode: ListView.NoSnap
                                        flickDeceleration: 1500; maximumFlickVelocity: 4000
                                        focus: true; keyNavigationEnabled: true; keyNavigationWraps: true
                                        highlightFollowsCurrentItem: true; highlightMoveDuration: 200
                                        opacity: gamesBackground._gridOpacity
                                        // Diffed by game id, so typing keeps the tiles that still match and only adds or
                                        // removes the rest (a plain array rebuilt every tile on each keystroke and replayed
                                        // the entrance stagger). Ids, not the games: ScriptModel copies its values, and the
                                        // tiles need the service's own game objects (looked up in _gameById).
                                        // Never a change of order, though: ScriptModel turns one into row moves, and Qt's
                                        // delegate model can crash applying them (SIGSEGV in QQmlDelegateModel::itemsMoved,
                                        // the whole shell down after a search). Tiles whose place changed go out and come
                                        // back in their new place instead, which is how the move transition looked anyway
                                        model: ScriptModel { values: gamesListView._gridIds }
                                        property var _gridIds: []
                                        function _syncGrid() {
                                            const next = GameLauncherService.filteredGames.map(g => g.id || g.name);
                                            if (next.length === _gridIds.length && next.every((id, i) => id === _gridIds[i])) return;
                                            const oldIndex = new Map(_gridIds.map((id, i) => [id, i]));
                                            // The tiles in both, in the new order, by their old place: the longest run
                                            // still in order stays put, the rest leave and come back
                                            const common = next.filter(id => oldIndex.has(id)).map(id => oldIndex.get(id));
                                            const kept = _inOrder(common);
                                            if (kept.size < common.length) _gridIds = _gridIds.filter((id, i) => kept.has(i)); // Removes only
                                            _gridIds = next; // Adds only
                                        }
                                        // The values of the longest increasing run in seq (patience sorting)
                                        function _inOrder(seq) {
                                            const tails = [], tailAt = [], prev = [];
                                            for (let i = 0; i < seq.length; i++) {
                                                let lo = 0, hi = tails.length;
                                                while (lo < hi) { const mid = (lo + hi) >> 1; if (tails[mid] < seq[i]) lo = mid + 1; else hi = mid; }
                                                tails[lo] = seq[i]; tailAt[lo] = i; prev[i] = lo > 0 ? tailAt[lo - 1] : -1;
                                            }
                                            const kept = new Set();
                                            for (let i = tails.length ? tailAt[tails.length - 1] : -1; i >= 0; i = prev[i]) kept.add(seq[i]);
                                            return kept;
                                        }
                                        Component.onCompleted: _syncGrid()
                                        Connections {
                                            target: GameLauncherService
                                            function onFilteredGamesChanged() { gamesListView._syncGrid(); }
                                        }
                                        readonly property var _gameById: {
                                            const byId = {};
                                            for (const g of GameLauncherService.filteredGames) byId[g.id || g.name] = g;
                                            return byId;
                                        }
                                        // Row width follows the matches; eased so the row re-centres with the tiles
                                        Behavior on width { animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this) }

                                        // Tiles stagger in, left to right, as the drawer rises. After that, filtering
                                        // only moves, adds and removes tiles (the transitions below)
                                        property bool tilesIn: false
                                        property bool staggering: false
                                        Timer { id: staggerEnd; interval: 700; onTriggered: gamesListView.staggering = false }
                                        Connections {
                                            target: root
                                            function onDrawerWantedChanged() {
                                                if (!root.drawerWanted) return;
                                                gamesListView.staggering = true;
                                                gamesListView.tilesIn = true;
                                                staggerEnd.restart();
                                            }
                                            function onVisibleChanged() {
                                                if (!root.visible) gamesListView.tilesIn = false; // Ready to stagger in next time
                                            }
                                        }
                                        WheelHandler {
                                            id: wheelHandler
                                            orientation: Qt.Vertical
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            onWheel: (event) => {
                                                if (!gamesListView.scrollable) return;
                                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                                                const step = root.tileSize + gamesListView.spacing;
                                                snapAnimation.stop();
                                                gamesListView.contentX = gamesListView.clampScroll(gamesListView.contentX + (delta > 0 ? -step : step));
                                            }
                                        }
                                        SmoothedAnimation {
                                            id: snapAnimation
                                            target: gamesListView; property: "contentX"
                                            velocity: -1; duration: 350; easing.type: Easing.OutQuint
                                        }
                                        onMovementEnded: {
                                            const itemWidth = root.tileSize + spacing;
                                            const target = clampScroll(originX + Math.round((contentX - originX) / itemWidth) * itemWidth);
                                            if (Math.abs(contentX - target) > 2) scrollTo(target);
                                        }
                                        // The shell's motion tokens: tiles that match again grow in where they belong, ones
                                        // that stop matching shrink away, and the rest slide over. Slides use the decelerating
                                        // curve, not StyledListView's springy one: a tile can cross half the screen here, and
                                        // the overshoot read as a bounce.
                                        // They animate the tile's _appear, not opacity/scale, which stay bindings
                                        add: Transition {
                                            enabled: !root._returningFromDetails
                                            NumberAnimation {
                                                property: "_appear"; from: 0; to: 1
                                                duration: Appearance.animation.elementMoveEnter.duration
                                                easing.type: Appearance.animation.elementMoveEnter.type
                                                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                            }
                                        }
                                        remove: Transition {
                                            NumberAnimation {
                                                property: "_appear"; to: 0
                                                duration: Appearance.animation.elementMoveExit.duration
                                                easing.type: Appearance.animation.elementMoveExit.type
                                                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                                            }
                                        }
                                        displaced: Transition {
                                            animations: [
                                                Appearance.animation.elementMoveEnter.numberAnimation.createObject(this, { property: "x" }),
                                                // Finishes a tile's grow-in if more typing moved it mid-way
                                                Appearance.animation.elementMoveEnter.numberAnimation.createObject(this, { property: "_appear", to: 1 })
                                            ]
                                        }
                                        // A tile the ranking moved (re-sorting, or "fallout 3" pulling Fallout 3 forward)
                                        // dips out and comes back in its new place rather than flying across the others:
                                        // several crossing at once read as the whole row jumping. Neighbours it pushes
                                        // over by a slot still slide (displaced, above)
                                        move: Transition {
                                            enabled: !root._returningFromDetails
                                            SequentialAnimation {
                                                NumberAnimation {
                                                    property: "_appear"; to: 0
                                                    duration: Appearance.animation.elementMoveExit.duration * 0.6
                                                    easing.type: Appearance.animation.elementMoveExit.type
                                                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                                                }
                                                PropertyAction { property: "x" } // Jump to the new slot while hidden
                                                NumberAnimation {
                                                    property: "_appear"; to: 1
                                                    duration: Appearance.animation.elementMoveEnter.duration
                                                    easing.type: Appearance.animation.elementMoveEnter.type
                                                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                                }
                                            }
                                        }
                                        StyledScrollBar.horizontal: StyledScrollBar {
                                            policy: ScrollBar.AlwaysOff
                                        }
                                        delegate: GameGridItem {
                                            id: tile
                                            onShowHoverEffectChanged: if (showHoverEffect && game) root.prebuild(game)
                                            required property var modelData // The game's id
                                            required property int index
                                            // The current game object; the last one is kept while the tile leaves
                                            readonly property var _lookup: gamesListView._gameById[modelData]
                                            property var _lastGame: null
                                            on_LookupChanged: if (_lookup) _lastGame = _lookup
                                            game: _lookup ?? _lastGame
                                            width: root.tileSize; height: gamesListView.height

                                            // Two factors make up how present a tile is: _shown (the opening stagger, and
                                            // fading off the ends of the row) and _appear (the add/remove transitions)
                                            property real _appear: 1
                                            readonly property real _viewPos: x - gamesListView.contentX
                                            readonly property bool _inView: _viewPos > -width && _viewPos < gamesListView.width
                                            // Place along the visible row, so the stagger runs across what's on screen
                                            readonly property int _slot: Math.max(0, Math.round(_viewPos / (root.tileSize + gamesListView.spacing)))
                                            property real _shown: gamesListView.tilesIn && _inView ? 1 : 0
                                            Behavior on _shown {
                                                SequentialAnimation {
                                                    PauseAnimation { duration: gamesListView.staggering ? Math.min(tile._slot, 8) * 35 : 0 }
                                                    NumberAnimation {
                                                        duration: Appearance.animation.elementMoveEnter.duration
                                                        easing.type: Appearance.animation.elementMoveEnter.type
                                                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                                    }
                                                }
                                            }
                                            opacity: _shown * _appear
                                            scale: 1 - 0.08 * (1 - _shown) - 0.08 * (1 - _appear)
                                            Component.onCompleted: {
                                                _lastGame = _lookup;
                                                if (index === 0 && gamesListView.focus) {
                                                    Qt.callLater(() => forceActiveFocus());
                                                }
                                            }
                                            activeFocusOnTab: true
                                            onGameLaunched: (game) => gamesListView.openGame(game)
                                            Keys.onPressed: event => {
                                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                    gamesListView.openGame(game);
                                                    event.accepted = true;
                                                } else if (event.key === Qt.Key_Left) {
                                                    gamesListView.focusTile(index - 1);
                                                    event.accepted = true;
                                                } else if (event.key === Qt.Key_Right) {
                                                    gamesListView.focusTile(index + 1);
                                                    event.accepted = true;
                                                } else if (event.key === Qt.Key_Up) {
                                                    visibleSearchBar.forceActiveFocus();
                                                    event.accepted = true;
                                                }
                                            }
                                        }
                                    }
                                    Column {
                                        anchors.centerIn: parent
                                        visible: gamesListView.count === 0 && !GameLauncherService.loading
                                        spacing: 12
                                        opacity: visible ? 1.0 : 0.0
                                        scale: visible ? 1.0 : 0.92
                                        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
                                        // ── Contextual state properties ──
                                        readonly property bool _isCompleted: GameLauncherService.sortOrder === "completed" && GameLauncherService.searchQuery === ""
                                        readonly property bool _isFavorites: GameLauncherService.sortOrder === "favorites" && GameLauncherService.searchQuery === ""
                                        readonly property bool _isTagFilter: GameLauncherService.selectedTag !== "" && GameLauncherService.searchQuery === ""
                                        readonly property bool _isSearch: GameLauncherService.searchQuery !== ""
                                        readonly property string _icon: _isCompleted ? "check_circle" : _isFavorites ? "star" : _isTagFilter ? "label_off" : _isSearch ? "search_off" : "videogame_asset_off"
                                        readonly property string _title: {
                                            if (_isCompleted) return Translation.tr("No completed games yet");
                                            if (_isFavorites) return Translation.tr("No favorites yet");
                                            if (_isTagFilter) return Translation.tr("No games tagged \"%1\"").arg(GameLauncherService.selectedTag);
                                            if (_isSearch) return Translation.tr("No results for \"%1\"").arg(GameLauncherService.searchQuery);
                                            return Translation.tr("No games found");
                                        }
                                        readonly property string _subtitle: {
                                            if (_isCompleted) return Translation.tr("Mark games as completed from their details page");
                                            if (_isFavorites) return Translation.tr("Star some games to see them here");
                                            if (_isTagFilter) return Translation.tr("Add tags from a game's details page");
                                            if (_isSearch) return Translation.tr("Try a different search term");
                                            return Translation.tr("Press Ctrl+R to refresh");
                                        }
                                        // ── Icon badge ──
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 56; height: 56
                                            radius: Appearance.rounding.small
                                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: parent.parent._icon
                                                iconSize: 28
                                                color: Appearance.colors.colPrimary
                                            }
                                        }
                                        // ── Title ──
                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: parent._title
                                            color: Appearance.colors.colOnSurface
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.DemiBold
                                        }
                                        // ── Subtitle ──
                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: parent._subtitle
                                            color: Appearance.colors.colOnSurfaceVariant
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                        }
                                    }
                                    Rectangle {
                                        id: loadingBar
                                        anchors { top: parent.top; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                                        width: parent.width * 0.4; height: 3
                                        radius: 1.5; color: "transparent"; clip: true
                                        visible: opacity > 0; z: 10
                                        opacity: GameLauncherService.loading ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 1.5
                                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                                        }
                                        Rectangle {
                                            id: loadingSlider
                                            width: parent.width * 0.35
                                            height: parent.height
                                            radius: 1.5
                                            color: Appearance.colors.colPrimary
                                            SequentialAnimation on x {
                                                running: GameLauncherService.loading && root.visible
                                                loops: Animation.Infinite
                                                NumberAnimation {
                                                    from: -loadingSlider.width
                                                    to: loadingBar.width
                                                    duration: 1200
                                                    easing.type: Easing.InOutCubic
                                                }
                                                PauseAnimation { duration: 200 }
                                            }
                                        }
                                    }
                                    // ── Gradient fade edges ──
                                    Rectangle {
                                        id: rightFade
                                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: 56; z: 4
                                        property bool shown: gamesListView.scrollable && !gamesListView.atXEnd
                                        opacity: shown ? 1.0 : 0.0
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 0.7; color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3) }
                                            GradientStop { position: 1.0; color: Appearance.colors.colLayer1 }
                                        }
                                    }
                                    Rectangle {
                                        id: leftFade
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 56; z: 4
                                        property bool shown: gamesListView.scrollable && !gamesListView.atXBeginning
                                        opacity: shown ? 1.0 : 0.0
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Appearance.colors.colLayer1 }
                                            GradientStop { position: 0.3; color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3) }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }
                                    }
                                    // ── Scroll arrow buttons ──
                                    Rectangle {
                                        id: rightArrow
                                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: 36; height: 36; radius: height / 3
                                        z: 5
                                        property bool shown: gamesListView.scrollable && !gamesListView.atXEnd
                                        property bool hovered: rightArrowMouse.containsMouse
                                        color: hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                                        opacity: shown ? 1.0 : 0.0
                                        scale: shown ? 1.0 : 0.7
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "chevron_right"
                                            iconSize: 20
                                            color: rightArrow.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        }
                                        MouseArea {
                                            id: rightArrowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                gamesListView.scrollTo(gamesListView.contentX + (root.tileSize + gamesListView.spacing) * 3);
                                            }
                                        }
                                    }
                                    Rectangle {
                                        id: leftArrow
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: 36; height: 36; radius: height / 3
                                        z: 5
                                        property bool shown: gamesListView.scrollable && !gamesListView.atXBeginning
                                        property bool hovered: leftArrowMouse.containsMouse
                                        color: hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                                        opacity: shown ? 1.0 : 0.0
                                        scale: shown ? 1.0 : 0.7
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "chevron_left"
                                            iconSize: 20
                                            color: leftArrow.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        }
                                        MouseArea {
                                            id: leftArrowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                gamesListView.scrollTo(gamesListView.contentX - (root.tileSize + gamesListView.spacing) * 3);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        id: detailsView
                        anchors.fill: parent
                        z: 3
                        // Comes in once the page has loaded (it's made asynchronously): starting on the click, the
                        // fade and settle were often over, or half done, before there was anything in it, so the
                        // menu popped in, or appeared enlarged and slid into place
                        readonly property bool shown: root.showingDetails && detailsLoader.status === Loader.Ready
                        opacity: shown ? 1.0 : 0.0
                        scale: shown ? 1.0 : 1.03
                        visible: opacity > 0; enabled: root.showingDetails
                        // Faded out after Back: a fresh page for that game, built ahead again (never a used one)
                        onVisibleChanged: if (!visible && !root.showingDetails && detailsLoader.item?._arrived) root._rebuildDetails()
                        // Block all mouse/hover events from reaching the grid below
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.AllButtons
                        }
                        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
                        Loader {
                            id: detailsLoader
                            anchors.fill: parent
                            // Kept while the page fades out after Back
                            active: root._detailsGame !== null && !root._detailsRestart && (root.showingDetails || detailsView.visible || root._prebuilding)
                            asynchronous: true
                            sourceComponent: GameDetailsPanel {
                                anchors.fill: parent
                                game: root._detailsGame
                                shown: root.showingDetails
                                topPanelItem: topPanelLoader.item
                                onArrived: {
                                    openPanel = root.openOnShow;
                                    root.openOnShow = "";
                                }
                                onBackPressed: {
                                    root.showingDetails = false;
                                    root.selectedGame = null;
                                }
                                onPlayPressed: (game, option) => {
                                    if (!GameLauncherService.isGameInstalled(game.id)) {
                                        // Install: stay on the page, it shows the download once Steam starts it
                                        GameLauncherService.installGame(game);
                                        return;
                                    }
                                    GameLauncherService.launchGame(game, option);
                                    GlobalStates.gameLauncherOpen = false;
                                    root.showingDetails = false;
                                    root.selectedGame = null;
                                }
                            }
                        }
                    }
                    // ── Stats view ──
                    Item {
                        id: statsView
                        anchors.fill: parent
                        z: 4
                        opacity: root.showingStats ? 1.0 : 0.0
                        scale: root.showingStats ? 1.0 : 0.92
                        visible: opacity > 0; enabled: root.showingStats
                        onEnabledChanged: if (enabled) gameLauncherBackground.forceActiveFocus()
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.AllButtons
                            onClicked: gameLauncherBackground.forceActiveFocus()
                        }
                        transform: Translate {
                            y: root.showingStats ? 0 : 12
                            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        }
                        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        Loader {
                            anchors.fill: parent
                            active: root.showingStats
                            asynchronous: true
                            sourceComponent: GameStatsPanel {
                                anchors.fill: parent
                                onBackPressed: root.showingStats = false
                                onGameSelected: function(game) {
                                    root.showingStats = false;
                                    root.selectedGame = game;
                                    root.showingDetails = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
    // ─── Inline Components ────────────────────────────────────
    // The grid toolbar's buttons (top left): a neutral box, a step up on hover, holding a row of 30 px buttons
    component ToolbarGroup: Rectangle {
        id: group
        default property alias content: groupRow.data
        property real contentWidth: groupRow.width // Pickers set it themselves, to shrink as their options fade
        anchors.verticalCenter: parent.verticalCenter
        width: contentWidth + 6
        height: 34
        radius: Appearance.rounding.verysmall
        color: groupHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        clip: true
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        HoverHandler { id: groupHover }
        Row { id: groupRow; anchors.centerIn: parent; spacing: 2 }
    }
    // One of them that picks a value (launcher, sort): shows the current option's icon; clicked, the others
    // slide out beside it. options: [{ value, icon, label }]
    component ToolbarPicker: ToolbarGroup {
        id: picker
        property string title // Tooltip while closed
        property var options: []
        property string current
        property bool revealed: false
        signal picked(string value)
        readonly property var currentOption: options.find(o => o.value === current) ?? options[0]
        contentWidth: pickerButton.width + (revealed ? pickerOptions.width + 2 : 0)
        IconToolbarButton {
            id: pickerButton
            implicitHeight: 30; implicitWidth: 30
            buttonRadius: Appearance.rounding.segment
            text: picker.currentOption?.icon ?? ""
            colText: toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
            toggled: picker.revealed
            onClicked: picker.revealed = !picker.revealed
            StyledToolTip { text: picker.revealed ? (picker.currentOption?.label ?? "") : picker.title }
        }
        Row {
            id: pickerOptions
            anchors.verticalCenter: parent.verticalCenter
            opacity: picker.revealed ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Repeater {
                model: picker.options
                ToolbarOption {
                    required property var modelData
                    text: modelData.icon; tooltip: modelData.label
                    visible: modelData.value !== picker.current
                    onClicked: { picker.picked(modelData.value); picker.revealed = false; }
                }
            }
        }
    }
    component ToolbarOption: IconToolbarButton {
        implicitHeight: 30; implicitWidth: 30
        buttonRadius: Appearance.rounding.segment
        property string tooltip: ""
        StyledToolTip {
            text: tooltip
        }
    }
}
