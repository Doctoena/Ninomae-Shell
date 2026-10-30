import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick.Effects
MouseArea {
    id: root
    required property SystemTrayItem item
    signal menuOpened(qsWindow: var)
    signal menuClosed()
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: 28
    implicitHeight: 28
    cursorShape: Qt.PointingHandCursor
    onPressed: (event) => {
        switch (event.button) {
        case Qt.LeftButton:
            item.activate();
            break;
        case Qt.RightButton:
            if (item.hasMenu) menu.open();
            break;
        }
        event.accepted = true;
    }
    onEntered: {
        tooltip.text = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) tooltip.text += " • " + item.tooltipDescription;
        if (Config.options.bar.tray.showItemId) tooltip.text += "\n[" + item.id + "]";
    }
    Rectangle {
        id: itemBg
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: root.containsPress ? Appearance.colors.colLayer1Active
             : root.containsMouse ? Appearance.colors.colLayer1
             : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
    Loader {
        id: menu
        function open() {
            if (menu.active) {
                // Already loaded — just call open on the loaded item
                menu.item.open();
            } else {
                menu.active = true;
            }
        }
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            appTitle: root.item.tooltipTitle || root.item.title || root.item.id
            appIcon: root.item.icon
            screen: root.QsWindow.window?.screen ?? null
            centerX: root.QsWindow.window ? root.QsWindow.mapFromItem(root, root.width / 2, 0).x : 0
            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }
    IconImage {
        id: trayIcon
        visible: !Config.options.bar.tray.monochromeIcons
        source: root.item.icon
        anchors.centerIn: parent
        width: 16
        height: 16
    }
    Loader {
        active: Config.options.bar.tray.monochromeIcons
        anchors.fill: trayIcon
        sourceComponent: MultiEffect { // Desaturate + 10% tint in one pass
            source: trayIcon
            saturation: -0.8
            colorization: 0.1
            colorizationColor: Appearance.colors.colOnLayer0
        }
    }
    StyledToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
    }
}
