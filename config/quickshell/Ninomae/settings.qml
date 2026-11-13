//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
// Tells the services they're in the Settings window, not the shell (no battery warnings or notification server)
//@ pragma Env NINOMAE_SETTINGS_APP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.common.functions as CF
ApplicationWindow {
    id: root
    property real contentPadding: 8
    // In groups in the page list; the description goes under the page's title
    property var pages: [
        { name: Translation.tr("Appearance"), group: Translation.tr("Look"), icon: "palette", component: "modules/settings/AppearanceConfig.qml",
            description: Translation.tr("Wallpaper, colours and windows") },
        { name: Translation.tr("Bar & dock"), group: Translation.tr("Look"), icon: "toast", iconRotation: 180, component: "modules/settings/BarConfig.qml",
            description: Translation.tr("Shape, what's on it, the tray, weather and the dock") },
        { name: Translation.tr("Sidebar"), group: Translation.tr("Look"), icon: "side_navigation", component: "modules/settings/SidebarConfig.qml",
            description: Translation.tr("What's in it, notifications and quick toggles") },
        { name: Translation.tr("Display"), group: Translation.tr("Devices"), icon: "monitor", component: "modules/settings/DisplayConfig.qml",
            description: Translation.tr("Resolution, refresh rate, scale and night light") },
        { name: Translation.tr("Input"), group: Translation.tr("Devices"), icon: "mouse", component: "modules/settings/InputConfig.qml",
            description: Translation.tr("Keyboard, mouse and touchpad") },
        { name: Translation.tr("Lock & power"), group: Translation.tr("Devices"), icon: "lock", component: "modules/settings/LockPowerConfig.qml",
            description: Battery.available ? Translation.tr("The lock screen and the battery") : Translation.tr("The lock screen") },
        { name: Translation.tr("Games"), group: Translation.tr("Gaming"), icon: "sports_esports", component: "modules/settings/GameLauncherConfig.qml",
            description: Translation.tr("The launcher, your Steam library, artwork and GE-Proton") },
        { name: Translation.tr("In game"), group: Translation.tr("Gaming"), icon: "stadia_controller", component: "modules/settings/InGameConfig.qml",
            description: Translation.tr("The overlay, clips and backing them up to Immich") },
        { name: Translation.tr("Crosshair"), group: Translation.tr("Gaming"), icon: "my_location", component: "modules/settings/CrosshairConfig.qml",
            description: Translation.tr("Its look, part by part, with a live preview") },
        { name: Translation.tr("Keybinds"), group: Translation.tr("System"), icon: "keyboard", component: "modules/settings/KeybindsConfig.qml",
            description: Translation.tr("Every shortcut, read live from Hyprland. Change them here") },
        { name: Translation.tr("Window rules"), group: Translation.tr("System"), icon: "select_window", component: "modules/settings/WindowRulesConfig.qml",
            description: Translation.tr("How chosen apps' windows open") },
        { name: Translation.tr("Advanced"), group: Translation.tr("System"), icon: "construction", component: "modules/settings/AdvancedConfig.qml",
            description: Translation.tr("Search, screenshots and expert options") },
        { name: Translation.tr("About"), group: Translation.tr("System"), icon: "info", component: "modules/settings/About.qml",
            description: Translation.tr("Versions and system info") }
    ]
    // NINOMAE_SETTINGS_PAGE=keybinds (page name, any case) opens straight on that page
    property int currentPage: {
        const wanted = (Quickshell.env("NINOMAE_SETTINGS_PAGE") ?? "").toLowerCase();
        const index = pages.findIndex(page => page.name.toLowerCase() === wanted);
        return Math.max(0, index);
    }
    visible: true
    // For checking the design: NINOMAE_SETTINGS_SNAPSHOT=/dir renders every page, all of it, to /dir/NN-name.png
    // and quits. It takes no input meanwhile, so a click meant for something else can't change a setting
    readonly property string snapshotDir: Quickshell.env("NINOMAE_SETTINGS_SNAPSHOT") ?? ""
    flags: snapshotDir !== "" ? (Qt.Window | Qt.WindowTransparentForInput) : Qt.Window
    property int snapshotPage: -1
    Timer {
        running: root.snapshotDir !== "" && Config.ready
        interval: 1500
        repeat: true
        onTriggered: {
            if (root.snapshotPage >= 0) {
                const page = pageLoader.item;
                const target = page?.column ?? page;
                const n = root.snapshotPage;
                const file = `${root.snapshotDir}/${String(n + 1).padStart(2, "0")}-${root.pages[n].name.replace(/[^A-Za-z]+/g, "-")}.png`;
                target?.grabToImage(result => result.saveToFile(file));
            }
            root.snapshotPage += 1;
            if (root.snapshotPage >= root.pages.length) { stop(); Qt.callLater(Qt.quit); return; }
            root.currentPage = root.snapshotPage;
        }
    }
    onClosing: Qt.quit()
    title: "Ninomae Settings"
    // scripts/open-settings.sh calls this when Settings is already open: switch page and come forward
    IpcHandler {
        target: "settings"
        // `qs -p settings.qml ipc call settings search "blur"`: fills the search box
        function search(text: string): void {
            headerBar.searchField.text = text;
            headerBar.searchField.forceActiveFocus();
        }
        // Opens the best match for `text`, like pressing Enter in the search box
        function jump(text: string): void {
            root.openResult(search.results(text)[0]);
        }
        function open(page: string): void {
            const index = root.pages.findIndex(p => p.name.toLowerCase() === page.toLowerCase());
            if (index >= 0) root.currentPage = index;
            root.raise();
            root.requestActivate();
            Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "title:^${root.title}$" })`]);
        }
    }
    // ── Search ──
    SettingsSearch {
        id: search
        pages: root.pages
    }
    readonly property string query: headerBar.searchField.text
    property string shownQuery: "" // What the results panel shows: the last query, kept while the panel folds away
    readonly property var shownResults: search.results(shownQuery)
    readonly property var results: query !== "" ? shownResults : [] // What Up, Down and Enter act on
    property int selectedResult: 0
    onQueryChanged: {
        if (query === "") return; // Folding away: the panel keeps its rows and highlight
        shownQuery = query;
        selectedResult = 0;
        resultsList.contentY = 0;
    }
    property var pendingJump: null // { label, section, keybind }: found and highlighted once its page has loaded
    function openResult(result) {
        if (!result) return;
        root.pendingJump = { label: result.label, section: result.section ?? "", keybind: result.keybind, tries: 0, opened: false };
        if (root.currentPage !== result.page) root.currentPage = result.page; // The page loads, then jumpTimer runs
        else jumpTimer.restart();
        headerBar.searchField.text = "";
    }
    // After a page change (or right away on the same page): find the option, scroll to it and flash it
    Timer {
        id: jumpTimer
        interval: 120
        onTriggered: {
            const jump = root.pendingJump;
            const page = pageLoader.item;
            if (!jump || !page) return;
            if (jump.keybind) {
                page.applyQuery?.(jump.label);
                root.pendingJump = null;
                return;
            }
            // A page whose sections fold (the crosshair's parts) opens the result's first, then it's found a
            // moment later. Within its section: two options can share a name ("Gap from the centre")
            if (!jump.opened) { // The result's section, or the result when it's a section itself
                jump.opened = true;
                if (page.openSection?.(jump.section || jump.label)) { restart(); return; }
            }
            const scope = jump.section ? root.findItem(page, jump.section) : null;
            const target = (scope ? root.findItem(scope, jump.label) : null) ?? root.findItem(page, jump.label);
            if (!target && ++jump.tries < 10) { restart(); return; } // Not built yet (monitors, keyring): try again
            root.pendingJump = null;
            if (target) root.reveal(target);
        }
    }
    // The first visible item showing `label` (a row, a section's title, a field's placeholder)
    function findItem(item, label) {
        const stack = [item];
        while (stack.length > 0) {
            const node = stack.shift();
            if (node !== item && [node.text, node.title, node.placeholderText, node.mainText].includes(label)) {
                let shown = node;
                while (shown && !shown.visible) shown = shown.parent; // Hidden until something above is on: show that
                return shown;
            }
            for (const child of node.children ?? []) stack.push(child);
        }
        return null;
    }
    function reveal(target) {
        let flick = target.parent;
        while (flick && flick.contentY === undefined) flick = flick.parent;
        if (!flick) return;
        const pos = target.mapToItem(flick.contentItem, 0, 0);
        flick.contentY = Math.max(0, Math.min(pos.y - 60, flick.contentHeight - flick.height));
        highlightComponent.createObject(flick.contentItem, {
            x: pos.x - 6, y: pos.y - 4, width: target.width + 12, height: target.height + 8
        });
    }
    // An accent glow over the found option: in the page's own content, so it scrolls with it
    Component {
        id: highlightComponent
        Rectangle {
            id: glow
            radius: Appearance.rounding.normal
            color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
            border.width: 2
            border.color: Appearance.colors.colPrimary
            opacity: 0
            SequentialAnimation on opacity {
                running: true
                NumberAnimation { to: 1; duration: 150 }
                PauseAnimation { duration: 1100 }
                NumberAnimation { to: 0; duration: 500 }
                ScriptAction { script: glow.destroy() }
            }
        }
    }
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
    }
    minimumWidth: 750
    minimumHeight: 500
    width: 1477 // As the window rule "settings-window" floats it
    height: 859
    color: Appearance.colors.colLayer0
    // Ctrl K / Ctrl F: search. Ctrl Page Up / Down: the page before / after. Ctrl Tab: round and round
    Shortcut { sequences: ["Ctrl+K", "Ctrl+F"]; onActivated: headerBar.searchField.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+PgDown"; onActivated: root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1) }
    Shortcut { sequence: "Ctrl+PgUp"; onActivated: root.currentPage = Math.max(root.currentPage - 1, 0) }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: root.currentPage = (root.currentPage + 1) % root.pages.length }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length }
    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }
        RowLayout { // Sidebar + content
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding
            SettingsNav { // You, the pages in their groups, Collapse
                pages: root.pages
                currentPage: root.currentPage
                stateFile: `${CF.FileUtils.trimFileProtocol(Directories.state)}/user/settings_app.json`
                narrow: root.width <= 900
                onPageChosen: index => root.currentPage = index
            }
            Item { // The open page
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Item { // Lined up with the page's cards (ContentPage's column: 20 px margin, 1260 at most)
                    id: pageHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 20 } // Close sits as far from the top edge as from the right
                    height: headerBar.implicitHeight + 18
                    SettingsHeader {
                        id: headerBar
                        width: Math.min(parent.width - 40, 1260)
                        x: (parent.width - width) / 2
                        page: root.pages[root.currentPage]
                        onCloseClicked: root.close()
                        onSearchMoved: step => root.selectedResult = Math.max(0, Math.min(root.selectedResult + step, root.results.length - 1))
                        onSearchAccepted: root.openResult(root.results[root.selectedResult])
                    }
                }
                Loader {
                    id: pageLoader
                    anchors {
                        top: pageHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    active: Config.ready
                    Component.onCompleted: {
                        source = root.pages[root.currentPage].component
                    }
                    onLoaded: if (root.pendingJump) jumpTimer.restart()
                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }
                    SequentialAnimation {
                        id: switchAnim
                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
                StyledRectangularShadow {
                    target: resultsPanel
                    visible: resultsPanel.visible
                }
                Rectangle { // Search results, under the search box: each setting with its page's icon and where it is
                    id: resultsPanel
                    readonly property bool open: root.query !== ""
                    // Unfolds down out of the search box on the drawers' curves (as the tray menu and bar drawers)
                    property real reveal: open ? 1 : 0
                    Behavior on reveal {
                        NumberAnimation {
                            duration: resultsPanel.open ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: resultsPanel.open ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
                        }
                    }
                    readonly property real fullHeight: Math.min(resultColumn.implicitHeight + 16, parent.height - pageHeader.height - 20)
                    visible: reveal > 0
                    clip: true
                    anchors { top: pageHeader.top; topMargin: headerBar.searchBox.y + headerBar.searchBox.height + 8; right: pageHeader.right; rightMargin: headerBar.x }
                    width: Math.min(420, parent.width - 40)
                    height: fullHeight * reveal
                    radius: Math.min(Appearance.rounding.large, height / 2)
                    color: Appearance.m3colors.m3surfaceContainer
                    StyledFlickable {
                        id: resultsList
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                        height: resultsPanel.fullHeight - 16 // Full size from the start: the panel uncovers it
                        opacity: Math.min(1, resultsPanel.reveal * 1.4)
                        contentHeight: resultColumn.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: resultColumn
                            width: parent.width
                            spacing: 2
                            StyledText {
                                visible: root.shownResults.length === 0
                                Layout.fillWidth: true
                                Layout.margins: 10
                                wrapMode: Text.Wrap
                                text: Translation.tr("Nothing matches \"%1\"").arg(root.shownQuery)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: root.shownResults
                                delegate: RippleButton {
                                    id: resultButton
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 52
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.selectedResult === index
                                    onToggledChanged: if (toggled) { // Up / Down past the edge: scroll it into view
                                        const top = y, bottom = y + height;
                                        if (top < resultsList.contentY) resultsList.contentY = top;
                                        else if (bottom > resultsList.contentY + resultsList.height) resultsList.contentY = bottom - resultsList.height;
                                    }
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                                    colBackgroundToggled: Appearance.m3colors.m3surfaceContainerHigh
                                    colBackgroundToggledHover: Appearance.m3colors.m3surfaceContainerHighest
                                    colRippleToggled: Appearance.m3colors.m3surfaceContainerHighest
                                    onClicked: root.openResult(modelData)
                                    contentItem: RowLayout {
                                        spacing: 12
                                        Rectangle { // The page's icon (a keyboard for a keybind), accent on the selected one
                                            Layout.leftMargin: 4
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            radius: Appearance.rounding.segment
                                            color: resultButton.toggled ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerHighest
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: resultButton.modelData.keybind ? "keyboard" : root.pages[resultButton.modelData.page].icon
                                                rotation: resultButton.modelData.keybind ? 0 : (root.pages[resultButton.modelData.page].iconRotation || 0)
                                                iconSize: Appearance.font.pixelSize.larger
                                                fill: resultButton.toggled ? 1 : 0
                                                color: resultButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: resultButton.modelData.label
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Medium
                                                color: resultButton.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: resultButton.modelData.where
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                            }
                                        }
                                        MaterialSymbol { // Enter opens the selected one
                                            visible: resultButton.toggled
                                            Layout.rightMargin: 6
                                            text: "keyboard_return"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
