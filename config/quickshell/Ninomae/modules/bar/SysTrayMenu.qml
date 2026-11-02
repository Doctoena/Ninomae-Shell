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
// other bar drawers (BarDrawerPopup.qml); submenus open in place with a Back row.
// Assumes a horizontal bar at the top.
PanelWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    property string appTitle: "" // Shown as the header (with appIcon)
    property string appIcon: ""
    property real centerX: 0 // Screen x of the icon's centre, set by SysTrayItem
    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
    readonly property real padding: 8
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
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:trayMenu"
    WlrLayershell.layer: WlrLayer.Overlay
    implicitWidth: panelWidth + sideMargin * 2
    implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
    margins {
        top: root.barBottom // Directly below the bar, which skips its border here (BarJoin)
        left: Math.max(0, Math.min(root.centerX - root.implicitWidth / 2, (root.screen?.width ?? 0) - root.implicitWidth))
    }
    mask: Region { item: maskArea }

    Item {
        id: maskArea
        x: root.sideMargin
        width: root.panelWidth
        height: root.visibleHeight
    }

    Item {
        id: stage
        anchors.fill: parent
        clip: true

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
            transform: Matrix4x4 { // Wobble with the blob
                matrix: background.deformMatrix
            }
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
        spacing: 2
        // Header: app icon in a lavender badge + its name (top level only)
        RowLayout {
            visible: !submenu.isSubMenu && root.appTitle.length > 0
            Layout.fillWidth: true
            Layout.margins: 6
            Layout.bottomMargin: 8
            spacing: 10
            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                IconImage {
                    anchors.centerIn: parent
                    source: root.appIcon
                    implicitSize: 18
                    asynchronous: true
                    mipmap: true
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.appTitle
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
        }
        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: RippleButton {
                id: backButton
                buttonRadius: Appearance.rounding.segment
                horizontalPadding: 12
                implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
                implicitHeight: 38
                colBackground: "transparent"
                colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                colRipple: Appearance.m3colors.m3surfaceContainerHighest
                downAction: () => stackView.pop()
                contentItem: RowLayout {
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                        leftMargin: backButton.horizontalPadding
                        rightMargin: backButton.horizontalPadding
                    }
                    spacing: 8
                    MaterialSymbol {
                        iconSize: 20
                        text: "chevron_left"
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Back")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
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
            property bool specialInteractionColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].buttonType !== QsMenuButtonType.None)
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
                forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                menuEntry: modelData
                onDismiss: root.close()
                onOpenSubmenu: handle => {
                    stackView.push(subMenuComponent.createObject(null, {
                        handle: handle,
                        isSubMenu: true
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
