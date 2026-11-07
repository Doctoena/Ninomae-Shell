import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.services.network
import QtQuick
import QtQuick.Layouts

// A network in range: its name and state, its signal and a lock when it's secured. A click connects; one that
// needs a password asks for it under the name
RowButton {
    id: root
    required property WifiAccessPoint wifiNetwork
    readonly property int strength: wifiNetwork?.strength ?? 0
    readonly property bool connecting: Network.wifiConnectTarget === wifiNetwork && !wifiNetwork?.active
    enabled: !connecting
    current: wifiNetwork?.active ?? false
    text: wifiNetwork?.ssid ?? Translation.tr("Unknown")
    description: wifiNetwork?.active ? Translation.tr("Connected")
        : connecting ? Translation.tr("Connecting…")
        : wifiNetwork?.isSecure ? Translation.tr("Secured") : Translation.tr("Open")
    expanded: wifiNetwork?.askingPassword ?? false
    onClicked: Network.connectToWifiNetwork(wifiNetwork)

    MaterialSymbol {
        visible: (root.wifiNetwork?.isSecure && !root.wifiNetwork?.active) ?? false
        text: "lock"
        iconSize: 16
        color: Appearance.colors.colSubtext
    }
    MaterialSymbol {
        text: root.strength > 80 ? "signal_wifi_4_bar" : root.strength > 60 ? "network_wifi_3_bar"
            : root.strength > 40 ? "network_wifi_2_bar" : root.strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
        iconSize: 20
        color: root.current ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
    }

    below: RowLayout { // Password
        Layout.fillWidth: true
        spacing: 8
        StyledTextField {
            id: passwordField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Password")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            onAccepted: Network.changePassword(root.wifiNetwork, passwordField.text)
        }
        RippleButtonWithIcon {
            materialIcon: "close"
            mainText: Translation.tr("Cancel")
            onClicked: root.wifiNetwork.askingPassword = false
        }
        RippleButtonWithIcon {
            materialIcon: "login"
            mainText: Translation.tr("Connect")
            onClicked: Network.changePassword(root.wifiNetwork, passwordField.text)
        }
    }
}
