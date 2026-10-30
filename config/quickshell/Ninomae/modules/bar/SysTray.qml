import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
Item {
    id: root
    implicitWidth: gridLayout.implicitWidth
    implicitHeight: gridLayout.implicitHeight
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showSeparator: true
    property bool showOverflowMenu: true
    property var activeMenu: null
    property bool smartTray: Config.options.bar.tray.filterPassive
    property list<var> itemsInUserList: SystemTray.items.values.filter(i => (Config.options.bar.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))
    property list<var> itemsNotInUserList: SystemTray.items.values.filter(i => (!Config.options.bar.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))
    property bool invertPins: Config.options.bar.tray.invertPinnedItems
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList
    onUnpinnedItemsChanged: {
        if (unpinnedItems.length == 0) root.closeOverflowMenu();
    }
    function grabFocus() {
        focusGrab.active = true;
    }
    function setExtraWindowAndGrabFocus(window) {
        root.activeMenu = window;
        root.grabFocus();
    }
    function releaseFocus() {
        focusGrab.active = false;
    }
    function closeOverflowMenu() {
        focusGrab.active = false;
    }
    onTrayOverflowOpenChanged: {
        if (root.trayOverflowOpen) {
            root.grabFocus();
        }
    }
    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [trayOverflowLayout.QsWindow?.window, root.activeMenu]
        onCleared: {
            root.trayOverflowOpen = false;
            if (root.activeMenu) {
                root.activeMenu.close();
                root.activeMenu = null;
            }
        }
    }
    GridLayout {
        id: gridLayout
        columns: -1
        anchors.fill: parent
        rowSpacing: 6
        columnSpacing: 6
        // Overflow button
        RippleButton {
            id: trayOverflowButton
            visible: root.showOverflowMenu && root.unpinnedItems.length > 0
            toggled: root.trayOverflowOpen
            property bool containsMouse: hovered
            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen
            Layout.fillHeight: true
            background.implicitWidth: 22
            background.implicitHeight: 22
            background.anchors.centerIn: this
            buttonRadius: 8
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: "transparent"
            colBackgroundToggled: "transparent"
            colBackgroundToggledHover: "transparent"
            colRippleToggled: "transparent"
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.normal
                text: "more_horiz"
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colSubtext
                opacity: root.trayOverflowOpen || trayOverflowButton.hovered ? 1.0 : 0.6
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            BarDrawerPopup { // Drops out of the bar like the other bar drawers; opened by clicking the button
                id: overflowPopup
                hoverTarget: trayOverflowButton
                openOnHover: false
                wanted: root.trayOverflowOpen && root.unpinnedItems.length > 0
                GridLayout {
                    id: trayOverflowLayout
                    anchors.centerIn: parent
                    columns: Math.ceil(Math.sqrt(root.unpinnedItems.length))
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: root.unpinnedItems
                        delegate: SysTrayItem {
                            required property SystemTrayItem modelData
                            item: modelData
                            Layout.fillHeight: true
                            onMenuClosed: root.releaseFocus();
                            onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow);
                        }
                    }
                }
            }
        }
        // Pinned tray icons
        Repeater {
            model: ScriptModel {
                values: root.pinnedItems
            }
            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.fillHeight: true
                onMenuClosed: root.releaseFocus();
                onMenuOpened: (qsWindow) => {
                    root.setExtraWindowAndGrabFocus(qsWindow);
                }
            }
        }
        Rectangle {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            visible: root.showSeparator && SystemTray.items.values.length > 0
            width: 1
            height: 20
            color: Appearance.colors.colOutlineVariant
            opacity: 0.5
        }
    }
}
