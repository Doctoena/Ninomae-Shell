//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
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
            description: Translation.tr("The launcher, clips, Immich backup and API keys") },
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
    onClosing: Qt.quit()
    title: "Ninomae Settings"
    // scripts/open-settings.sh calls this when Settings is already open: switch page and come forward
    IpcHandler {
        target: "settings"
        // `qs -p settings.qml ipc call settings search "blur"`: fills the search box
        function search(text: string): void {
            searchField.text = text;
            searchField.forceActiveFocus();
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
    property string query: ""
    readonly property var results: search.results(query)
    property int selectedResult: 0
    onQueryChanged: selectedResult = 0
    property var pendingJump: null // { label, keybind }: found and highlighted once its page has loaded
    function openResult(result) {
        if (!result) return;
        root.pendingJump = { label: result.label, keybind: result.keybind, tries: 0 };
        if (root.currentPage !== result.page) root.currentPage = result.page; // The page loads, then jumpTimer runs
        else jumpTimer.restart();
        searchField.text = "";
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
            const target = root.findItem(page, jump.label);
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
    width: 1100
    height: 750
    color: Appearance.colors.colLayer0
    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }
        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_F) {
                    searchField.forceActiveFocus();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }
        RowLayout { // Sidebar + content
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding
            Rectangle { // Sidebar
                id: sidebar
                readonly property bool expanded: root.width > 900
                Layout.fillHeight: true
                implicitWidth: expanded ? 210 : 60
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true
                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    spacing: 2
                    // Header: badge + title
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 2
                        Layout.bottomMargin: 12
                        spacing: 10
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 12
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "settings"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                        ColumnLayout {
                            visible: sidebar.expanded
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Settings")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: "Ninomae"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                    // Search: finds any option on any page, and keybinds
                    Rectangle {
                        visible: sidebar.expanded
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        implicitHeight: 36
                        radius: Appearance.rounding.container
                        color: Appearance.m3colors.m3surfaceContainerHigh
                        border.width: searchField.activeFocus ? 2 : 0
                        border.color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
                        MaterialSymbol {
                            id: searchIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "search"
                            iconSize: 18
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        TextField {
                            id: searchField
                            anchors {
                                left: searchIcon.right; leftMargin: 6
                                right: clearButton.visible ? clearButton.left : parent.right; rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            background: null
                            padding: 0
                            color: Appearance.colors.colOnLayer1
                            placeholderText: Translation.tr("Search settings")
                            placeholderTextColor: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            selectionColor: Appearance.colors.colSecondaryContainer
                            onTextChanged: root.query = text
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down) root.selectedResult = Math.min(root.selectedResult + 1, root.results.length - 1);
                                else if (event.key === Qt.Key_Up) root.selectedResult = Math.max(root.selectedResult - 1, 0);
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.openResult(root.results[root.selectedResult]);
                                else if (event.key === Qt.Key_Escape && text !== "") text = "";
                                else return;
                                event.accepted = true;
                            }
                        }
                        RippleButton {
                            id: clearButton
                            visible: searchField.text !== ""
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.segment
                            colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
                            onClicked: searchField.text = ""
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "close"
                                iconSize: 16
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                    StyledText {
                        visible: root.query !== "" && root.results.length === 0
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        text: Translation.tr("Nothing matches \"%1\"").arg(root.query)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledFlickable { // Results: the option, and where it is
                        visible: root.query !== ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: resultColumn.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: resultColumn
                            width: parent.width
                            spacing: 2
                            Repeater {
                                model: root.results
                                delegate: RippleButton {
                                    id: resultButton
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: resultText.implicitHeight + 16
                                    buttonRadius: 13
                                    toggled: root.selectedResult === index
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                                    colBackgroundToggled: Appearance.m3colors.m3surfaceContainerHigh
                                    colBackgroundToggledHover: Appearance.m3colors.m3surfaceContainerHighest
                                    colRippleToggled: Appearance.m3colors.m3surfaceContainerHighest
                                    onClicked: root.openResult(modelData)
                                    contentItem: RowLayout {
                                        spacing: 10
                                        MaterialSymbol {
                                            Layout.leftMargin: 4
                                            text: resultButton.modelData.keybind ? "keyboard" : root.pages[resultButton.modelData.page].icon
                                            rotation: resultButton.modelData.keybind ? 0 : (root.pages[resultButton.modelData.page].iconRotation || 0)
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: resultButton.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                        }
                                        ColumnLayout {
                                            id: resultText
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: resultButton.modelData.label
                                                wrapMode: Text.Wrap
                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                color: resultButton.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: resultButton.modelData.where
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Repeater {
                        model: root.query === "" ? root.pages : []
                        // A group's name over its first page (a gap when the list is folded to icons). Squircle style
                        // like the rest of the shell: the current page stays on the neutral surface, with its icon on
                        // an accent squircle and its name in accent
                        delegate: ColumnLayout {
                            id: pageEntry
                            required property int index
                            required property var modelData
                            readonly property bool startsGroup: index === 0 || root.pages[index - 1].group !== modelData.group
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout { // The group's name in small capitals, then a hairline out to the edge
                                visible: pageEntry.startsGroup && sidebar.expanded
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 8
                                Layout.topMargin: pageEntry.index === 0 ? 2 : 14
                                Layout.bottomMargin: 4
                                spacing: 10
                                StyledText {
                                    text: pageEntry.modelData.group.toUpperCase()
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.4
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Appearance.colors.colOutlineVariant
                                    opacity: 0.6
                                }
                            }
                            Item {
                                visible: pageEntry.startsGroup && !sidebar.expanded && pageEntry.index > 0
                                implicitHeight: 10
                            }
                            RippleButton {
                                id: pageButton
                                Layout.fillWidth: true
                                implicitHeight: 42
                                buttonRadius: 13
                                toggled: root.currentPage === pageEntry.index
                                onClicked: root.currentPage = pageEntry.index
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                                colBackgroundToggled: Appearance.m3colors.m3surfaceContainerHigh
                                colBackgroundToggledHover: Appearance.m3colors.m3surfaceContainerHighest
                                colRippleToggled: Appearance.m3colors.m3surfaceContainerHighest
                                contentItem: RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        Layout.leftMargin: sidebar.expanded ? 4 : 0
                                        Layout.alignment: sidebar.expanded ? Qt.AlignVCenter : Qt.AlignCenter
                                        implicitWidth: 30
                                        implicitHeight: 30
                                        radius: Appearance.rounding.segment
                                        color: pageButton.toggled ? Appearance.colors.colPrimary : CF.ColorUtils.transparentize(Appearance.colors.colPrimary) // Not black: no dark flash
                                        Behavior on color {
                                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                        }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: pageEntry.modelData.icon
                                            rotation: pageEntry.modelData.iconRotation || 0
                                            iconSize: Appearance.font.pixelSize.larger
                                            fill: pageButton.toggled ? 1 : 0
                                            color: pageButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                    StyledText {
                                        visible: sidebar.expanded
                                        Layout.fillWidth: true
                                        text: pageEntry.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: pageButton.toggled ? Font.DemiBold : Font.Normal
                                        color: pageButton.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        visible: root.query === ""
                        Layout.fillHeight: true
                    }
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true
                // Page header: lined up with the page's cards (ContentPage's column), icon on an accent squircle
                Item {
                    id: pageHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 20 }
                    height: headerRow.implicitHeight + 6
                    RowLayout {
                        id: headerRow
                        width: Math.min(parent.width - 40, 1260) // As ContentPage's margin and maxWidth
                        x: (parent.width - width) / 2
                        spacing: 14
                        Rectangle {
                            implicitWidth: 46
                            implicitHeight: 46
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colPrimary
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.pages[root.currentPage].icon
                                rotation: root.pages[root.currentPage].iconRotation || 0
                                iconSize: 26
                                fill: 1
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                text: root.pages[root.currentPage].name
                                font.pixelSize: Appearance.font.pixelSize.title
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.pages[root.currentPage].description
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
                RippleButton {
                    anchors { top: parent.top; right: parent.right; margins: 14 }
                    buttonRadius: Appearance.rounding.container
                    implicitWidth: 34
                    implicitHeight: 34
                    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnSurfaceVariant
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
                    opacity: 1.0
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
            }
        }
    }
}
