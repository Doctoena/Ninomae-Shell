import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The control centre window's content: the sections in a slim icon rail on the left (SectionRail), the open one on
 * the right under a header with its icon, a status line and, for Wi-Fi and Bluetooth, the on/off switch.
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

    Item {
        id: card
        readonly property real padding: 10
        readonly property real radius: Appearance.rounding.windowRounding
        anchors.fill: parent

        RowLayout {
            anchors { fill: parent; margins: card.padding }
            spacing: card.padding

            SectionRail {
                Layout.preferredWidth: 84
                Layout.fillWidth: false
                Layout.fillHeight: true
                content: root
            }

            Rectangle { // The open section
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: card.radius - card.padding
                clip: true

                RowLayout { // Header: icon on an accent squircle, name, status; the switch and close on the right
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 20; rightMargin: 14 }
                    spacing: 14
                    Rectangle {
                        implicitWidth: 46
                        implicitHeight: 46
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.current.icon
                            iconSize: 26
                            fill: 1
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            text: root.current.name
                            font.pixelSize: Appearance.font.pixelSize.title
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            elide: Text.ElideRight
                            text: root.page?.subtitle ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledSwitch {
                        visible: root.page?.hasSwitch ?? false
                        checked: root.page?.switchChecked ?? false
                        onClicked: root.page.setSwitch(checked)
                    }
                    RippleButton {
                        Layout.alignment: Qt.AlignTop
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
                }

                StyledFlickable {
                    id: flick
                    anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 16 }
                    contentHeight: pageLoader.height + 20
                    clip: true
                    Loader {
                        id: pageLoader
                        x: 20
                        width: flick.width - 40
                        source: root.current.page
                        onSourceChanged: flick.contentY = 0
                    }
                }
            }
        }
    }
}
