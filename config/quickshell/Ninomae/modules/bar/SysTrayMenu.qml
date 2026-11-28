import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Right-click menu of a tray icon. Drops out of the bar under the icon as a gooey drawer, like the
// other bar drawers (BarDrawerPopup.qml). T2b: a header centred over the menu (the app's icon on a squircle of its
// colour, its name, its status line if it sends one; Open at the right), then every row in one well, the app's
// sections split by hairlines (SysTrayMenuEntry). Submenus open in place, the header becoming Back with where you are.
PanelWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    property string appTitle: "" // Shown as the header (with appIcon)
    property string appIcon: ""
    property string appStatus: "" // The app's own status line (its tooltip's description), if any
    property string appId: "" // For its colour: the main icon of the app, not the (often grey) tray one
    property var trayItem: null // Open: the same as left-clicking its icon
    readonly property color tint: IconColours.colourFor(appId.toLowerCase())
    Component.onCompleted: IconColours.request(appId.toLowerCase())
    property real centerX: 0 // Screen x of the icon's centre, set by SysTrayItem
    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
    readonly property real padding: 10
    readonly property real bottomRadius: Appearance.rounding.large
    readonly property real hiddenExtra: 60
    readonly property real barBottom: GlobalStates.drawerTopOn(screen) // Below the bar, or near the top without one
    // Content size, animated when a submenu opens or closes (but not while the menu first fills in)
    property real contentWidth: stackView.implicitWidth
    property real contentHeight: stackView.implicitHeight
    Behavior on contentWidth {
        enabled: root.contentSettled && root.offsetScale <= 0
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    Behavior on contentHeight {
        enabled: root.contentSettled && root.offsetScale <= 0
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    readonly property real panelWidth: contentWidth + padding * 2
    readonly property real fullHeight: contentHeight + padding * 2

    // Apps send their menu entries over D-Bus a moment after it opens (Steam in several batches), so
    // the size keeps changing at first. Wait until it has held still briefly before sliding out,
    // or the drawer jumps and the rows shift while it moves
    property bool contentSettled: false
    Timer {
        id: settleTimer
        interval: 70
        onTriggered: root.contentSettled = true
    }
    Timer { // Don't wait forever on an app that keeps changing its menu
        interval: 350
        running: root.visible && !root.contentSettled
        onTriggered: root.contentSettled = true
    }
    Connections {
        target: stackView
        enabled: root.visible && !root.contentSettled
        function onImplicitWidthChanged() { settleTimer.restart(); }
        function onImplicitHeightChanged() { settleTimer.restart(); }
    }

    readonly property bool ready: readiness.ready // Slide only once the window is on screen (resets when hidden)
    property bool wanted: false

    // 0 = out, 1 = tucked under the bar
    property real offsetScale: (wanted && ready && contentSettled) ? 0 : 1
    Behavior on offsetScale {
        NumberAnimation {
            duration: root.wanted ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.wanted ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
        }
    }
    onOffsetScaleChanged: if (offsetScale >= 1 && !wanted && visible) finishClose()
    readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
    readonly property real drawerY: Math.min(0, drawerTop)
    readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
    readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

    function open() {
        settleTimer.restart();
        root.visible = true;
        root.wanted = true;
        root.menuOpened(root);
    }
    function close() { // Slides back in; finishClose() runs once it's under the bar
        if (!root.wanted) return;
        root.wanted = false;
        if (root.offsetScale >= 1) finishClose();
    }
    function finishClose() {
        root.visible = false;
        root.contentSettled = false;
        while (stackView.depth > 1)
            stackView.pop();
        root.menuClosed();
    }

    visible: false
    color: "transparent"
    anchors { top: !GlobalStates.barAtBottom; bottom: GlobalStates.barAtBottom; left: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:trayMenu"
    WlrLayershell.layer: GlobalStates.drawerLayer(screen)
    implicitWidth: panelWidth + sideMargin * 2
    implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
    margins {
        bottom: GlobalStates.barAtBottom ? root.barBottom : 0 // Or right above it, along the bottom
        top: GlobalStates.barAtBottom ? 0 : root.barBottom // Directly below the bar, which skips its border here (BarJoin)
        left: Math.max(0, Math.min(root.centerX - root.implicitWidth / 2, (root.screen?.width ?? 0) - root.implicitWidth))
    }
    mask: Region { item: maskArea }

    Item {
        id: maskArea
        x: root.sideMargin
        y: GlobalStates.barAtBottom ? root.height - height : 0
        width: root.panelWidth
        height: root.visibleHeight
    }

    Item {
        id: stage
        anchors.fill: parent
        clip: true
        transform: BarSideFlip { size: stage.height } // Bar along the bottom: rises from it

        DrawerReadiness {
            id: readiness
            active: root.visible
        }
        BarJoin { // Lets the bar skip its bottom border where the drawer joins it
            name: "trayMenu"
            active: root.visible && root.visibleHeight > 0
            joinX: root.margins.left + root.sideMargin
            joinWidth: root.panelWidth
        }

        DrawerBackground { // Shared with the other drawers. Made with the window (it's created per right-click),
            followBar: true // A card while there's no bar (a fullscreen game)
            // so the blob is there for the first frame instead of the unjoined fallback
            id: background
            anchors.fill: parent
            screenWidth: root.screen?.width ?? 0
            windowScreenX: root.margins.left
            drawerX: root.sideMargin
            drawerY: root.drawerY
            drawerWidth: root.panelWidth
            drawerHeight: root.drawerHeight
            drawerRadius: Math.min(root.bottomRadius, root.visibleHeight / 2)
            fallbackRadius: root.bottomRadius
        }

        Item {
            id: contentHolder
            x: root.sideMargin + root.padding
            y: root.drawerY + root.padding
            width: root.contentWidth
            height: root.contentHeight
            clip: true // While resizing for a submenu
            opacity: 1 - root.offsetScale
            transform: [
                BarSideFlip { size: contentHolder.height }, // Upright in a flipped stage
                Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob
            ]
            MouseArea { // Back / right click inside a submenu goes up a level
                anchors.fill: parent
                acceptedButtons: Qt.BackButton | Qt.RightButton
                onPressed: event => {
                    if (stackView.depth > 1) stackView.pop();
                }
            }
            StackView {
                id: stackView
                anchors.fill: parent
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}
                implicitWidth: currentItem.implicitWidth
                implicitHeight: currentItem.implicitHeight
                initialItem: SubMenu {
                    handle: root.trayItemMenuHandle
                }
            }
        }
    }
    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }
    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false
        opacity: shown ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()
        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }
        property string title: "" // A submenu's: the entry it came from
        spacing: 6
        // Header, straight on the glass and centred over the menu: the app's icon on a squircle of its colour (with a
        // glow), its name and status line (Open is the well's first row, so nothing beside it pulls it off centre).
        // A submenu: Back at the left, where you are and in which app
        Item {
            id: header
            visible: submenu.isSubMenu || root.appTitle.length > 0
            Layout.fillWidth: true
            implicitHeight: !submenu.isSubMenu && root.appStatus !== "" ? 50 : 44
            // A submenu: room either side for Back, so the centred middle never runs under it
            readonly property real sideRoom: backButton.visible ? backButton.implicitWidth + 8 : 0
            implicitWidth: middle.implicitWidth + sideRoom * 2
            Halo {
                visible: !submenu.isSubMenu
                colour: root.tint
                strength: 0.45
                reach: 22
                centreX: middle.x + appTile.x + appTile.width / 2
                centreY: header.height / 2
            }
            RippleButton { // Back, in a submenu
                id: backButton
                visible: submenu.isSubMenu
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: 10
                colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.91)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.84)
                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.76)
                downAction: () => stackView.pop()
                StyledToolTip { text: Translation.tr("Back") }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "chevron_left"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer3
                }
            }
            RowLayout { // The middle: the app's tile, its name and status (a submenu: where you are, in which app)
                id: middle
                anchors.centerIn: parent
                width: Math.min(implicitWidth, header.width - header.sideRoom * 2)
                spacing: 10
                Rectangle {
                    id: appTile
                    visible: !submenu.isSubMenu
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 10
                    color: ColorUtils.transparentize(root.tint, 0.78)
                    IconImage {
                        anchors.centerIn: parent
                        source: root.appIcon
                        implicitSize: 18
                        asynchronous: true
                        mipmap: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: submenu.isSubMenu ? Text.AlignHCenter : Text.AlignLeft
                        text: submenu.isSubMenu ? submenu.title : root.appTitle
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.title
                        font.weight: Font.Black
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        horizontalAlignment: submenu.isSubMenu ? Text.AlignHCenter : Text.AlignLeft
                        text: submenu.isSubMenu ? root.appTitle : root.appStatus
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtextGlass
                    }
                }
            }
        }
        // Every row in one well, the app's sections split by hairlines
        Item {
            Layout.fillWidth: true
            implicitWidth: rows.implicitWidth + 8
            implicitHeight: rows.implicitHeight + 8
            GlassWell {
                anchors.fill: parent
            }
            ColumnLayout {
                id: rows
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                spacing: 0
                RippleButton { // Open: the same as left-clicking the icon. A row like the app's, a hairline under it
                    id: openRow
                    visible: !submenu.isSubMenu && root.trayItem !== null && !(root.trayItem?.onlyMenu ?? false)
                    Layout.fillWidth: true
                    implicitWidth: openLabel.implicitWidth + 60
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.normal - 4
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colWellRowHover
                    colRipple: Appearance.colors.colWellRowActive
                    releaseAction: () => {
                        root.trayItem.activate();
                        root.close();
                    }
                    LitBar {
                        shown: openRow.hovered
                        color: Appearance.colors.colPrimary
                    }
                    contentItem: RowLayout {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 10 }
                        spacing: 10
                        StyledText {
                            id: openLabel
                            Layout.fillWidth: true
                            text: Translation.tr("Open %1").arg(root.appTitle)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: openRow.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                        }
                        MaterialSymbol {
                            text: "north_east"
                            iconSize: 16
                            color: openRow.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                    }
                }
                Rectangle {
                    visible: openRow.visible
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    implicitHeight: 1
                    color: Appearance.colors.colWellHairline
                }
                Repeater {
                    id: menuEntriesRepeater
                    // The top level's disabled "app name" row duplicates the header; hide it and its separator
                    function isRedundant(i) {
                        const v = menuOpener.children.values;
                        const isNameRow = e => e && !e.isSeparator && e.enabled === false && e.text === root.appTitle;
                        if (submenu.isSubMenu || root.appTitle.length === 0) return false;
                        if (isNameRow(v[i])) return true;
                        return v[i]?.isSeparator && i > 0 && isNameRow(v[i - 1]) && v.slice(0, i - 1).every(e => isNameRow(e));
                    }
                    property bool iconColumnNeeded: {
                        for (let i = 0; i < menuOpener.children.values.length; i++) {
                            if (menuOpener.children.values[i].icon.length > 0 && !isRedundant(i))
                                return true;
                        }
                        return false;
                    }
                    model: menuOpener.children
                    delegate: SysTrayMenuEntry {
                        required property QsMenuEntry modelData
                        required property int index
                        visible: !menuEntriesRepeater.isRedundant(index)
                        forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                        menuEntry: modelData
                        onDismiss: root.close()
                        onOpenSubmenu: (handle, title) => {
                            stackView.push(subMenuComponent.createObject(null, {
                                handle: handle,
                                isSubMenu: true,
                                title: title
                            }));
                        }
                    }
                }
            }
        }
    }
    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
