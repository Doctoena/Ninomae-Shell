import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item { // Wrapper
    id: root
    property string searchingText: ""
    property string mathResult: ""
    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) { // Invalid if doesn't start with numbers
                    Quickshell.execDetached([
                        "notify-send",
                        Translation.tr("Superpaste"),
                        Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action),
                        "-a", "Shell"
                    ]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath]);
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
    ]
    function focusFirstItem() {
        appResults.currentIndex = 0;
    }
    function focusSearchInput() {
        searchBar.forceFocus();
    }
    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }
    function cancelSearch() { // Opening starts with an empty search (it used to keep the last query, selected)
        searchBar.searchInput.text = "";
        root.searchingText = "";
        searchBar.animateWidth = true;
    }
    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        root.searchingText = text;
    }
    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.searchingText;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProcess.calculateExpression(expr);
        }
    }
    Process {
        id: mathProcess
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProcess.running = false;
            mathProcess.command = baseCommand.concat(expression);
            mathProcess.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
                root.focusFirstItem();
            }
        }
    }
    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;
        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }
        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }
    // ════════════════════════════════════════════════════════════════════
    // Drawer that slides out of the bar (inspired by caelestia-dots/shell):
    // same colour and border as the bar, joined to it by concave corners.
    // ════════════════════════════════════════════════════════════════════
    // Games have their own launcher (Super+Shift+O): hide Steam/Lutris game shortcuts here.
    // The Steam and Lutris apps themselves still show.
    function isGameShortcut(entry) {
        const cmd = (entry?.execString ?? entry?.command?.join(" ") ?? "");
        return cmd.includes("steam://rungameid/") || cmd.includes("lutris:rungame");
    }
    readonly property real panelWidth: 860
    readonly property real panelPadding: 14
    readonly property real cornerRadius: Appearance.rounding.windowRounding // matches the bar's rounding
    readonly property real sideMargin: 40 // Room for the gooey bulge beside the drawer
    readonly property bool useBlobs: blobBg.status === Loader.Ready
    readonly property real bottomRadius: 28
    readonly property int maxShown: 8
    readonly property real itemHeight: 50
    readonly property real fullHeight: content.implicitHeight
    // 0 = fully out, 1 = tucked behind the bar. Overview.qml keeps the window
    // mapped while this animates so the drawer can slide back in on close.
    property bool windowReady: true // Set by Overview.qml once the window has rendered
    property real offsetScale: (GlobalStates.overviewOpen && windowReady) ? 0 : 1
    Behavior on offsetScale {
        NumberAnimation {
            // Open: gentle start so it visibly eases out of the bar (the expressive curve put the drawer
            // ~60px out on its first frame), then a slight overshoot. Close: decelerate into the bar.
            duration: GlobalStates.overviewOpen ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: GlobalStates.overviewOpen ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
        }
    }
    // When hidden, tuck the drawer this far past the bar edge so the blob merge leaves no bump
    readonly property real hiddenExtra: 60
    readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
    // The open curve overshoots (offsetScale < 0): stretch the drawer instead of pulling it off the bar
    readonly property real drawerY: Math.min(0, drawerTop)
    readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop)
    readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

    implicitWidth: panelWidth + sideMargin * 2
    BarJoin { // Lets the bar skip its bottom border where the drawer joins it
        name: "launcher"
        active: root.visibleHeight > 0
        joinX: active ? root.mapToItem(null, root.sideMargin, 0).x : 0
        joinWidth: root.panelWidth
    }
    implicitHeight: fullHeight

    Item { // Clips everything above the bar's bottom edge, so the drawer emerges from under it
        id: clipper
        anchors.fill: parent
        clip: true

        // Preferred: caelestia's blob renderer, so the drawer oozes out of the bar
        Loader {
            id: blobBg
            anchors.fill: parent
            source: "BlobDrawerBackground.qml"
            onLoaded: {
                // The clipper starts on the bar's 1px bottom border row. End the stand-in just
                // above it so only the drawer covers that row (hiding the seam), not the whole width
                item.barBottom = 0;
                item.barHeight = Appearance.sizes.baseBarHeight;
                item.barRadius = Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0;
                item.drawerX = Qt.binding(() => root.sideMargin);
                item.drawerY = Qt.binding(() => root.drawerY);
                item.drawerWidth = Qt.binding(() => root.panelWidth);
                item.drawerHeight = Qt.binding(() => root.drawerHeight);
                // While only a sliver is out, shrink the corners so it reads as a strip leaving
                // the bar rather than a shallow bump (rounded corners meeting the joins)
                item.drawerRadius = Qt.binding(() => Math.min(root.bottomRadius, root.visibleHeight / 2));
            }
        }

        Item { // Fallback background (no plugin): corners + panel as one translucent surface
            visible: !root.useBlobs
            anchors.fill: parent
            opacity: 0.92
            layer.enabled: visible // Group opacity, so the corners and panel don't double up where they meet

            ConcaveCorner {
                anchors { top: parent.top; right: drawer.left }
                size: Math.min(root.cornerRadius, root.visibleHeight)
            }
            ConcaveCorner {
                anchors { top: parent.top; left: drawer.right }
                size: Math.min(root.cornerRadius, root.visibleHeight)
                transform: Scale { xScale: -1; origin.x: root.cornerRadius / 2 }
            }
            Shape {
                id: drawer
                x: root.sideMargin
                y: root.drawerY
                width: root.panelWidth
                height: root.drawerHeight
                preferredRendererType: Shape.CurveRenderer
                readonly property real r: Math.min(root.bottomRadius, height / 2)
                // The side border begins where the concave corner's arc ends
                readonly property real borderStart: height - root.visibleHeight + Math.min(root.cornerRadius, root.visibleHeight)
                ShapePath { // Fill
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: Appearance.colors.colLayer0
                    startX: 0; startY: 0
                    PathLine { x: 0; y: drawer.height - drawer.r }
                    PathArc { x: drawer.r; y: drawer.height; radiusX: drawer.r; radiusY: drawer.r; direction: PathArc.Counterclockwise }
                    PathLine { x: drawer.width - drawer.r; y: drawer.height }
                    PathArc { x: drawer.width; y: drawer.height - drawer.r; radiusX: drawer.r; radiusY: drawer.r; direction: PathArc.Counterclockwise }
                    PathLine { x: drawer.width; y: 0 }
                }
                ShapePath { // Border on the sides and bottom only, continuing the bar's outline
                    strokeWidth: 1
                    strokeColor: Appearance.colors.colLayer0Border
                    fillColor: "transparent"
                    startX: 0; startY: drawer.borderStart
                    PathLine { x: 0; y: drawer.height - drawer.r }
                    PathArc { x: drawer.r; y: drawer.height; radiusX: drawer.r; radiusY: drawer.r; direction: PathArc.Counterclockwise }
                    PathLine { x: drawer.width - drawer.r; y: drawer.height }
                    PathArc { x: drawer.width; y: drawer.height - drawer.r; radiusX: drawer.r; radiusY: drawer.r; direction: PathArc.Counterclockwise }
                    PathLine { x: drawer.width; y: drawer.borderStart }
                }
            }
        }

        Item { // Content slides with the drawer
            id: content
            x: root.sideMargin
            y: root.drawerY
            width: root.panelWidth
            implicitHeight: columnLayout.implicitHeight + root.panelPadding * 2
            opacity: 1 - root.offsetScale // Fade in step with the drawer so it never slides in empty
            transform: Matrix4x4 { // Wobble with the blob, as caelestia does for its panels
                matrix: root.useBlobs ? blobBg.item.deformMatrix : Qt.matrix4x4()
            }

            ColumnLayout {
                id: columnLayout
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: root.panelPadding
                }
                spacing: 10

                SearchBar {
                    id: searchBar
                    Layout.fillWidth: true
                    Synchronizer on searchingText {
                        property alias source: root.searchingText
                    }
                }

                RowLayout { // Results list | preview of the selected result
                    id: resultsRow
                    visible: appResults.count > 0
                    Layout.fillWidth: true
                    spacing: 12

                    ListView { // Results (all apps when the query is empty)
                        id: appResults
                        Layout.preferredWidth: 330
                        Layout.fillHeight: true
                        // Keep at least 5 rows tall so the preview has room even with few results
                        implicitHeight: (root.itemHeight + spacing) * Math.max(5, Math.min(root.maxShown, count)) - spacing
                        clip: true
                        spacing: 2
                        KeyNavigation.up: searchBar
                        highlightFollowsCurrentItem: false
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: height
                        highlight: Rectangle { // Faint highlight that slides between rows
                            y: appResults.currentItem?.y ?? 0
                            width: appResults.width
                            height: appResults.currentItem?.height ?? 0
                            radius: 14
                            color: Appearance.colors.colPrimary
                            opacity: 0.14
                            Behavior on y {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                                }
                            }
                        }
                        Behavior on implicitHeight {
                            enabled: GlobalStates.overviewOpen
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                            }
                        }
                        onFocusChanged: {
                            if (focus)
                                appResults.currentIndex = 1;
                        }
                        Connections {
                            target: root
                            function onSearchingTextChanged() {
                                if (appResults.count > 0)
                                    appResults.currentIndex = 0;
                            }
                        }
                        model: ScriptModel {
                            id: model
                            objectProp: "key"
                            values: {
                                // Search results are handled here
                                ////////////////// Skip? //////////////////
                                if (root.searchingText == "") // Like caelestia: show every app right away, the most used first (then A–Z)
                                    return AppSearch.list.filter(e => !root.isGameShortcut(e))
                                        .map(entry => ({ entry: entry, score: AppSearch.usageScore(entry) }))
                                        .sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name))
                                        .map(({ entry }) => {
                                        entry.clickActionName = Translation.tr("Launch");
                                        entry.type = Translation.tr("App");
                                        entry.key = entry.execute;
                                        return entry;
                                    });
                                ///////////// Special cases ///////////////
                                if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) {
                                    // Clipboard
                                    const searchString = StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.clipboard);
                                    return Cliphist.fuzzyQuery(searchString).map(entry => {
                                        const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`
                                        return {
                                            key: type,
                                            cliphistRawString: entry,
                                            name: StringUtils.cleanCliphistEntry(entry),
                                            clickActionName: "",
                                            type: type,
                                            execute: () => {
                                                Cliphist.copy(entry)
                                            },
                                            actions: [
                                                {
                                                    name: "Copy",
                                                    materialIcon: "content_copy",
                                                    execute: () => {
                                                        Cliphist.copy(entry);
                                                    }
                                                },
                                                {
                                                    name: "Delete",
                                                    materialIcon: "delete",
                                                    execute: () => {
                                                        Cliphist.deleteEntry(entry);
                                                    }
                                                }
                                            ]
                                        };
                                    }).filter(Boolean);
                                }
                                else if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) {
                                    // Clipboard
                                    const searchString = StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.emojis);
                                    return Emojis.fuzzyQuery(searchString).map(entry => {
                                        const emoji = entry.match(/^\s*(\S+)/)?.[1] || ""
                                        return {
                                            key: emoji,
                                            cliphistRawString: entry,
                                            bigText: emoji,
                                            name: entry.replace(/^\s*\S+\s+/, ""),
                                            clickActionName: "",
                                            type: "Emoji",
                                            execute: () => {
                                                Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                                            }
                                        };
                                    }).filter(Boolean);
                                }
                                ////////////////// Init ///////////////////
                                // qalc only when the result is shown (a number or the maths prefix), not on every keystroke
                                if (/^\d/.test(root.searchingText) || root.searchingText.startsWith(Config.options.search.prefix.math))
                                    nonAppResultsTimer.restart();
                                const mathResultObject = {
                                    key: `Math result: ${root.mathResult}`,
                                    name: root.mathResult,
                                    clickActionName: Translation.tr("Copy"),
                                    type: Translation.tr("Math result"),
                                    fontType: "monospace",
                                    materialSymbol: 'calculate',
                                    execute: () => {
                                        Quickshell.clipboardText = root.mathResult;
                                    }
                                };
                                const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.app)).filter(e => !root.isGameShortcut(e)).map(entry => {
                                    entry.clickActionName = Translation.tr("Launch");
                                    entry.type = Translation.tr("App");
                                    entry.key = entry.execute
                                    return entry;
                                })
                                const commandResultObject = {
                                    key: `cmd ${root.searchingText}`,
                                    name: StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.shellCommand).replace("file://", ""),
                                    clickActionName: Translation.tr("Run"),
                                    type: Translation.tr("Run command"),
                                    fontType: "monospace",
                                    materialSymbol: 'terminal',
                                    execute: () => {
                                        let cleanedCommand = root.searchingText.replace("file://", "");
                                        cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                                        if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                                            cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                                        }
                                        // sudo needs a terminal for the password; the command goes in as an argument so
                                        // quotes in it reach fish intact
                                        if (cleanedCommand.trim().startsWith("sudo"))
                                            Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} fish -C "$1"`, "run-in-terminal", cleanedCommand]);
                                        else
                                            Quickshell.execDetached(["bash", "-c", cleanedCommand]);
                                    }
                                };
                                const webSearchResultObject = {
                                    key: `website ${root.searchingText}`,
                                    name: StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.webSearch),
                                    clickActionName: Translation.tr("Search"),
                                    type: Translation.tr("Search the web"),
                                    materialSymbol: 'travel_explore',
                                    execute: () => {
                                        let query = StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.webSearch);
                                        for (let site of Config.options.search.excludedSites) {
                                            query += ` -site:${site}`;
                                        }
                                        // Encoded, so "c++", "a & b" or "#tag" reach the search engine as typed
                                        Qt.openUrlExternally(Config.options.search.engineBaseUrl + encodeURIComponent(query));
                                    }
                                }
                                const launcherActionObjects = root.searchActions.map(action => {
                                    const actionString = `${Config.options.search.prefix.action}${action.action}`;
                                    if (actionString.startsWith(root.searchingText) || root.searchingText.startsWith(actionString)) {
                                        return {
                                            key: `Action ${actionString}`,
                                            name: root.searchingText.startsWith(actionString) ? root.searchingText : actionString,
                                            clickActionName: Translation.tr("Run"),
                                            type: Translation.tr("Action"),
                                            materialSymbol: 'settings_suggest',
                                            execute: () => {
                                                action.execute(root.searchingText.split(" ").slice(1).join(" "));
                                            }
                                        };
                                    }
                                    return null;
                                }).filter(Boolean);
                                //////// Prioritized by prefix /////////
                                let result = [];
                                const startsWithNumber = /^\d/.test(root.searchingText);
                                const startsWithMathPrefix = root.searchingText.startsWith(Config.options.search.prefix.math);
                                const startsWithShellCommandPrefix = root.searchingText.startsWith(Config.options.search.prefix.shellCommand);
                                const startsWithWebSearchPrefix = root.searchingText.startsWith(Config.options.search.prefix.webSearch);
                                if (startsWithNumber || startsWithMathPrefix) {
                                    result.push(mathResultObject);
                                } else if (startsWithShellCommandPrefix) {
                                    result.push(commandResultObject);
                                } else if (startsWithWebSearchPrefix) {
                                    result.push(webSearchResultObject);
                                }
                                //////////////// Apps //////////////////
                                result = result.concat(appResultObjects);
                                ////////// Launcher actions ////////////
                                result = result.concat(launcherActionObjects);
                                /// Math result, command, web search ///
                                if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
                                    if (!startsWithShellCommandPrefix) result.push(commandResultObject);
                                    if (!startsWithNumber && !startsWithMathPrefix) result.push(mathResultObject);
                                    if (!startsWithWebSearchPrefix) result.push(webSearchResultObject);
                                }
                                return result;
                            }
                        }
                        delegate: SearchItem {
                            // The selectable item for each search result
                            required property var modelData
                            anchors.left: parent?.left
                            anchors.right: parent?.right
                            minHeight: root.itemHeight
                            entry: modelData
                            query: StringUtils.cleanOnePrefix(root.searchingText, [
                                Config.options.search.prefix.action,
                                Config.options.search.prefix.app,
                                Config.options.search.prefix.clipboard,
                                Config.options.search.prefix.emojis,
                                Config.options.search.prefix.math,
                                Config.options.search.prefix.shellCommand,
                                Config.options.search.prefix.webSearch
                            ])
                        }
                    }

                    PreviewPane {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        item: appResults.currentItem
                    }
                }

                StyledText { // Empty state
                    visible: appResults.count === 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 18
                    Layout.bottomMargin: 18
                    text: Translation.tr("No results")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    // Quarter-circle cut-out that blends the drawer into the bar's bottom edge
    component ConcaveCorner: Shape {
        id: corner
        property real size: 18
        width: root.cornerRadius
        height: root.cornerRadius
        preferredRendererType: Shape.CurveRenderer
        // Anchored to the drawer's top corner; grows with the visible drawer height
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Appearance.colors.colLayer0
            startX: corner.width - corner.size; startY: 0
            PathLine { x: corner.width; y: 0 }
            PathLine { x: corner.width; y: corner.size }
            PathArc {
                x: corner.width - corner.size; y: 0
                radiusX: corner.size; radiusY: corner.size
                direction: PathArc.Counterclockwise
            }
        }
        ShapePath {
            strokeWidth: 1
            strokeColor: Appearance.colors.colLayer0Border
            fillColor: "transparent"
            startX: corner.width; startY: corner.size
            PathArc {
                x: corner.width - corner.size; y: 0
                radiusX: corner.size; radiusY: corner.size
                direction: PathArc.Counterclockwise
            }
        }
    }
}
