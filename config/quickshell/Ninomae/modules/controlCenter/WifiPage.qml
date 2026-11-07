import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Wi-Fi: the network in use, then the others by signal (a click connects, asking for the password in the row).
// It scans while the page is open
ColumnLayout {
    id: page
    spacing: 10
    readonly property var connected: Network.wifiNetworks.find(n => n.active) ?? null
    readonly property var others: [...Network.wifiNetworks].filter(n => !n.active).sort((a, b) => b.strength - a.strength)
    readonly property string subtitle: !Network.wifiEnabled ? Translation.tr("Off")
        : connected ? Translation.tr("Connected to %1").arg(connected.ssid)
        : Network.wifiScanning ? Translation.tr("Searching…") : Translation.tr("Not connected")
    readonly property bool hasSwitch: true
    readonly property bool switchChecked: Network.wifiEnabled
    function setSwitch(on) {
        Network.enableWifi(on);
        if (on) Network.rescanWifi();
    }
    Component.onCompleted: if (Network.wifiEnabled) Network.rescanWifi()
    Component.onDestruction: Network.stopScan()

    StyledIndeterminateProgressBar {
        visible: Network.wifiEnabled && Network.wifiScanning
        Layout.fillWidth: true
    }
    PagePlaceholder {
        visible: !Network.wifiEnabled
        icon: "wifi_off"
        text: Translation.tr("Wi-Fi is off")
    }

    // The network in use: its signal large, Disconnect and Forget beside it
    HeroCard {
        visible: Network.wifiEnabled && page.connected !== null
        readonly property int strength: page.connected?.strength ?? 0
        symbol: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
        title: page.connected?.ssid ?? ""
        detail: page.connected?.isSecure ? Translation.tr("Connected · %1").arg(page.connected.security) : Translation.tr("Connected · open network")
        value: strength
        unit: Translation.tr("% signal")
        actions: [
            DialogButton {
                buttonText: Translation.tr("Disconnect")
                onClicked: page.connected?.network?.disconnect()
            },
            DialogButton {
                buttonText: Translation.tr("Forget")
                onClicked: page.connected?.network?.forget()
            }
        ]
    }

    WindowDialogSectionHeader {
        visible: Network.wifiEnabled && page.others.length > 0
        Layout.topMargin: 8
        text: Translation.tr("Available")
    }
    QuickDialogGroup {
        visible: Network.wifiEnabled && page.others.length > 0
        Repeater {
            model: ScriptModel { values: page.others }
            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                Layout.fillWidth: true
            }
        }
    }

    RowLayout {
        Layout.topMargin: 6
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Network settings")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.controlCenterOpen = false;
            }
        }
    }
}
