import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
WindowDialog {
    id: root
    readonly property var connected: Network.wifiNetworks.find(n => n.active) ?? null
    // Sized to what's there, up to 600 (the list scrolls past that)
    backgroundHeight: Math.min(600, body.implicitHeight + 36)

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        QuickDialogHeader {
            icon: "wifi"
            title: Translation.tr("Wi-Fi")
            subtitle: !Network.wifiEnabled ? Translation.tr("Off")
                : root.connected ? Translation.tr("Connected to %1").arg(root.connected.ssid)
                : Network.wifiScanning ? Translation.tr("Searching…") : Translation.tr("Not connected")
            showSwitch: true
            checked: Network.wifiEnabled
            onSwitchToggled: checked => Network.enableWifi(checked)
        }
        StyledIndeterminateProgressBar {
            visible: Network.wifiScanning
            Layout.fillWidth: true
        }

        // The network in use, in a card of its own
        QuickDialogGroup {
            visible: root.connected !== null
            WifiNetworkItem {
                Layout.fillWidth: true
                wifiNetwork: root.connected
            }
        }

        WindowDialogSectionHeader {
            visible: Network.wifiEnabled && available.count > 0
            text: Translation.tr("Available")
        }
        QuickDialogGroup {
            visible: Network.wifiEnabled && available.count > 0
            Layout.fillHeight: true
            Layout.preferredHeight: available.contentHeight + padding * 2
            ListView {
                id: available
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    values: [...Network.wifiNetworks].filter(n => !n.active).sort((a, b) => b.strength - a.strength)
                }
                delegate: WifiNetworkItem {
                    required property WifiAccessPoint modelData
                    wifiNetwork: modelData
                    width: ListView.view.width
                }
            }
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Settings")
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                    GlobalStates.sidebarRightOpen = false;
                }
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Done")
                primary: true
                onClicked: root.dismiss()
            }
        }
    }
}
