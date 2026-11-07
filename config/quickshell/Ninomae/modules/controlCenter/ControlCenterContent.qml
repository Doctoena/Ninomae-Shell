import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The control centre window's content, laid out as Settings: its page list on the left (SettingsNav: its name at
 * the top, a page each, Settings and Collapse at the bottom), the open page on the right under Settings' header, with the on/off
 * switch beside Close for Wi-Fi and Bluetooth.
 * A page is a ColumnLayout that can set `subtitle`, and `hasSwitch` / `switchChecked` / setSwitch(on)
 */
Item {
    id: root
    Component.onCompleted: forceActiveFocus()

    readonly property var sections: [
        { id: "sound", name: Translation.tr("Sound"), icon: "volume_up", page: "SoundPage.qml" },
        { id: "wifi", name: Translation.tr("Wi-Fi"), icon: "wifi", page: "WifiPage.qml" },
        { id: "bluetooth", name: Translation.tr("Bluetooth"), icon: "bluetooth", page: "BluetoothPage.qml" },
        { id: "display", name: Translation.tr("Display"), icon: "brightness_6", page: "DisplayPage.qml" },
    ]
    readonly property int currentIndex: Math.max(0, sections.findIndex(s => s.id === GlobalStates.controlCenterSection))
    readonly property var current: sections[currentIndex]
    readonly property var page: pageLoader.item
    function close() { GlobalStates.controlCenterOpen = false; }
    function go(step) {
        GlobalStates.controlCenterSection = sections[(currentIndex + step + sections.length) % sections.length].id;
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) root.close();
        else if (event.key === Qt.Key_Tab && event.modifiers & Qt.ControlModifier) root.go(1);
        else if (event.key === Qt.Key_Backtab && event.modifiers & Qt.ControlModifier) root.go(-1);
        else return;
        event.accepted = true;
    }

    RowLayout {
        anchors { fill: parent; margins: 8 }
        spacing: 8

        SettingsNav { // The page list, as Settings': its name where Settings shows you, Settings at the bottom
            id: nav
            pages: root.sections
            currentPage: root.currentIndex
            stateFile: `${FileUtils.trimFileProtocol(Directories.state)}/user/control_centre.json`
            narrow: root.width <= 760
            expandedWidth: 220
            title: Translation.tr("Control centre")
            subtitle: Translation.tr("Quick settings")
            badgeIcon: "tune"
            onPageChosen: index => GlobalStates.controlCenterSection = root.sections[index].id
            NavRow {
                Layout.fillWidth: true
                expanded: nav.expanded
                symbol: "settings"
                text: Translation.tr("Settings")
                onClicked: {
                    Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh")]);
                    root.close();
                }
            }
        }

        Item { // The open page, straight on the window as Settings'
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            SettingsHeader {
                id: header
                anchors { top: parent.top; topMargin: 20 } // Close sits as far from the top edge as from the right
                width: Math.min(parent.width - 40, 1260)
                x: (parent.width - width) / 2
                page: ({ name: root.current.name, group: Translation.tr("Control centre"), icon: root.current.icon,
                    description: root.page?.subtitle ?? "" })
                searchable: false
                onCloseClicked: root.close()
                StyledSwitch {
                    visible: root.page?.hasSwitch ?? false
                    checked: root.page?.switchChecked ?? false
                    onClicked: root.page.setSwitch(checked)
                }
            }
            StyledFlickable {
                id: flick
                anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 18 }
                contentHeight: pageLoader.height + 24
                clip: true
                Loader {
                    id: pageLoader
                    x: (flick.width - width) / 2
                    width: Math.min(flick.width - 40, 1260)
                    source: root.current.page
                    onSourceChanged: flick.contentY = 0
                }
            }
        }
    }
}
