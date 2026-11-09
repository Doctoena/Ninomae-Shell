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
// other bar drawers (BarDrawerPopup.qml). Compact, in the sidebar's joined pieces: a slim header card tinted by
// the app's icon (its name, its status line if it sends one, Open), then the app's sections as joined groups of
// rows (SysTrayMenuEntry). Submenus open in place, the header becoming Back with where you are.
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
    WlrLayershell.layer: WlrLayer.Overlay
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
        spacing: 2
        // Header: a slim card tinted by the app's icon. Top level: the icon (with a glow), the name, the status, Open.
        // A submenu: Back, where you are and in which app
        Rectangle {
            id: header
            visible: submenu.isSubMenu || root.appTitle.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 2 // A section's gap
            implicitHeight: !submenu.isSubMenu && root.appStatus !== "" ? 52 : 46
            topLeftRadius: Appearance.rounding.normal
            topRightRadius: Appearance.rounding.normal
            bottomLeftRadius: Appearance.rounding.small
            bottomRightRadius: Appearance.rounding.small
            color: ColorUtils.mix(Appearance.colors.colLayer3, root.tint, 0.84)
            clip: true
            Halo {
                visible: !submenu.isSubMenu
                colour: root.tint
                strength: 0.45
                reach: 22
                centreX: headerLead.x + headerLead.width / 2
                centreY: header.height / 2
            }
            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                spacing: 10
                Item { // The app's icon on a tile, or Back
                    id: headerLead
                    implicitWidth: 30
                    implicitHeight: 30
                    Rectangle {
                        visible: !submenu.isSubMenu
                        anchors.fill: parent
                        radius: 10
                        color: Appearance.colors.colLayer4
                        IconImage {
                            anchors.centerIn: parent
                            source: root.appIcon
                            implicitSize: 18
                            asynchronous: true
                            mipmap: true
                        }
                    }
                    RippleButton {
                        visible: submenu.isSubMenu
                        anchors.fill: parent
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
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
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
                        text: submenu.isSubMenu ? root.appTitle : root.appStatus
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: ColorUtils.mix(Appearance.colors.colSubtext, root.tint, 0.6)
                    }
                }
                RippleButton { // Open: the same as left-clicking the icon
                    visible: !submenu.isSubMenu && root.trayItem !== null && !(root.trayItem?.onlyMenu ?? false)
                    implicitHeight: 30
                    implicitWidth: openRow.implicitWidth + 20
                    buttonRadius: 10
                    colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.91)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.84)
                    colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.76)
                    releaseAction: () => {
                        root.trayItem.activate();
                        root.close();
                    }
                    contentItem: Item {
                        RowLayout {
                            id: openRow
                            anchors.centerIn: parent
                            spacing: 4
                            StyledText {
                                text: Translation.tr("Open")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer3
                            }
                            MaterialSymbol {
                                text: "north_east"
                                iconSize: 14
                                color: Appearance.colors.colOnLayer3
                            }
                        }
                    }
                }
            }
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
            // The rows shown, in order (separators too): a row's neighbours decide its corners
            readonly property var shownIndices: {
                const out = [];
                for (let i = 0; i < menuOpener.children.values.length; i++)
                    if (!isRedundant(i)) out.push(i);
                return out;
            }
            function neighbourIsBreak(i, step) { // Nothing there, or a separator: the section ends on this side
                const at = shownIndices.indexOf(i) + step;
                if (at < 0 || at >= shownIndices.length) return true;
                return menuOpener.children.values[shownIndices[at]].isSeparator;
            }
            readonly property int lastRowIndex: { // The last real row: it rounds the menu off
                const rows = shownIndices.filter(j => !menuOpener.children.values[j].isSeparator);
                return rows.length > 0 ? rows[rows.length - 1] : -1;
            }
            model: menuOpener.children
            delegate: SysTrayMenuEntry {
                required property QsMenuEntry modelData
                required property int index
                visible: !menuEntriesRepeater.isRedundant(index)
                forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                firstInSection: menuEntriesRepeater.neighbourIsBreak(index, -1)
                lastInSection: menuEntriesRepeater.neighbourIsBreak(index, 1)
                lastInMenu: menuEntriesRepeater.lastRowIndex === index
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
    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
