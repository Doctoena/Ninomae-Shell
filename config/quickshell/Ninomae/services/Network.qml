pragma Singleton
pragma ComponentBehavior: Bound
// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)
import Quickshell
import Quickshell.Networking
import QtQuick
import qs
import qs.services.network
import qs.modules.common
/**
 * Network state and Wi-Fi control, from Quickshell.Networking (NetworkManager over D-Bus). Event
 * driven: no nmcli processes. Wi-Fi scanning only runs while the Wi-Fi dialog is open.
 */
Singleton {
    id: root
    readonly property WifiDevice wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property WiredDevice wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected)
        ?? null
    readonly property bool limited: Networking.connectivity === NetworkConnectivity.Limited
        || Networking.connectivity === NetworkConnectivity.Portal

    readonly property bool ethernet: wiredDevice !== null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifi: (wifiDevice?.connected ?? false) && !limited
    property bool wifiScanning: false
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: networkVariants.instances
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property string wifiStatus: !Networking.wifiEnabled || !wifiDevice ? "disabled"
        : wifiDevice.connected ? (limited ? "limited" : "connected")
        : wifiDevice.state === ConnectionState.Connecting ? "connecting"
        : "disconnected"
    readonly property string networkName: ethernet ? (wiredDevice.network?.name ?? "") : (active?.ssid ?? "")
    readonly property int networkStrength: active?.strength ?? 0
    property string materialSymbol: root.ethernet
        ? "lan"
        : root.wifiEnabled
            ? (
                root.networkStrength > 83 ? "signal_wifi_4_bar" :
                root.networkStrength > 67 ? "network_wifi" :
                root.networkStrength > 50 ? "network_wifi_3_bar" :
                root.networkStrength > 33 ? "network_wifi_2_bar" :
                root.networkStrength > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        Networking.wifiEnabled = enabled;
    }
    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }
    // Scans while the Wi-Fi dialog is open (NetworkManager rescans on its own while the scanner is on);
    // the progress bar shows for the first pass
    property bool scanRequested: false
    function rescanWifi(): void {
        root.scanRequested = true;
        root.wifiScanning = true;
        scanningTimer.restart();
    }
    function stopScan(): void {
        root.scanRequested = false;
        root.wifiScanning = false;
    }
    Binding {
        target: root.wifiDevice
        when: root.wifiDevice !== null
        property: "scannerEnabled"
        value: root.scanRequested && (GlobalStates?.sidebarRightOpen ?? false)
    }
    Timer {
        id: scanningTimer
        interval: 4000
        onTriggered: root.wifiScanning = false
    }
    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        // A secured network with no saved profile can't connect without its password: ask first
        if (accessPoint.isSecure && !accessPoint.known) {
            accessPoint.askingPassword = true;
            return;
        }
        root.wifiConnectTarget = accessPoint;
        accessPoint.network.connect();
    }
    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }
    // Connects with this password (saved with the network's profile, or a new one)
    function changePassword(accessPoint: WifiAccessPoint, password: string, username = ""): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        accessPoint.network.connectWithPsk(password);
    }

    Variants {
        id: networkVariants
        model: (root.wifiDevice?.networks.values ?? []).filter(n => n.name.length > 0) // Hidden networks have no name
        WifiAccessPoint {
            id: accessPoint
            required property WifiNetwork modelData
            network: modelData
            onConnectFinished: needsPassword => {
                if (root.wifiConnectTarget === accessPoint) root.wifiConnectTarget = null;
                accessPoint.askingPassword = needsPassword;
            }
        }
    }
}
