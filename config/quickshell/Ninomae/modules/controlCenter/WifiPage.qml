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
    spacing: 14
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

    ContentSection {
        visible: Network.wifiEnabled && page.connected !== null
        title: Translation.tr("Connected")
        SettingRow {
            text: page.connected?.ssid ?? ""
            labelColor: Appearance.colors.colPrimary
            description: Translation.tr("%1 · %2 % signal")
                .arg(page.connected?.isSecure ? page.connected.security : Translation.tr("Open network"))
                .arg(page.connected?.strength ?? 0)
            RippleButtonWithIcon { // An open network (a café's, a hotel's) may want you to sign in on a web page
                visible: !(page.connected?.isSecure ?? true)
                materialIcon: "open_in_browser"
                mainText: Translation.tr("Sign in")
                onClicked: {
                    Network.openPublicWifiPortal();
                    GlobalStates.controlCenterOpen = false;
                }
            }
            RippleButtonWithIcon {
                materialIcon: "link_off"
                mainText: Translation.tr("Disconnect")
                onClicked: page.connected?.network?.disconnect()
            }
            RippleButtonWithIcon {
                materialIcon: "delete"
                mainText: Translation.tr("Forget")
                onClicked: page.connected?.network?.forget()
            }
        }
    }
    ContentSection {
        visible: Network.wifiEnabled && page.others.length > 0
        title: Translation.tr("Available")
        Repeater {
            model: ScriptModel { values: page.others }
            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
            }
        }
    }
    ContentSection {
        RowButton {
            text: Translation.tr("Network settings")
            description: Translation.tr("Saved networks, VPN and wired connections")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.controlCenterOpen = false;
            }
            MaterialSymbol {
                text: "open_in_new"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }
}
