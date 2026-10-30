import QtQuick
import Quickshell.Networking
// One Wi-Fi network (Quickshell.Networking groups access points by name), in the shape the Wi-Fi
// dialog uses. Network.qml makes one per network the Wi-Fi device can see
QtObject {
    id: root
    required property WifiNetwork network
    readonly property string ssid: network?.name ?? ""
    readonly property int strength: Math.round((network?.signalStrength ?? 0) * 100)
    readonly property bool active: network?.connected ?? false
    readonly property bool known: network?.known ?? false
    readonly property bool isSecure: network !== null && network.security !== WifiSecurityType.Open
        && network.security !== WifiSecurityType.Unknown
    readonly property string security: isSecure ? WifiSecurityType.toString(network.security) : ""
    property bool askingPassword: false
    signal connectFinished(bool needsPassword)
    readonly property Connections _events: Connections {
        target: root.network
        function onConnectedChanged() {
            if (root.network.connected) {
                root.askingPassword = false;
                root.connectFinished(false);
            }
        }
        // A wrong or missing password ends in NoSecrets (or an auth failure/timeout): ask for it
        function onConnectionFailed(reason) {
            root.connectFinished(root.isSecure && reason !== ConnectionFailReason.WifiNetworkLost);
        }
    }
}
