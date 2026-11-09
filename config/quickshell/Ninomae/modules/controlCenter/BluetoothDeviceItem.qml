import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell.Bluetooth

// A device: its name and state on the left, what you can do with it on the right (Connect, Forget, Pair…)
SettingRow {
    id: root
    required property var device
    // Remembered by BlueZ (paired, bonded or trusted): it connects. Anything else is paired first
    readonly property bool known: (device?.paired || device?.bonded || device?.trusted) ?? false
    readonly property bool pairing: device?.pairing ?? false
    // Mid-way: Connect pressed again then only logs "already connecting", so the button waits it out
    readonly property bool connecting: device?.state === BluetoothDeviceState.Connecting
    readonly property bool disconnecting: device?.state === BluetoothDeviceState.Disconnecting
    property bool pairRequested: false
    Connections { // Paired from here: trust it (so it reconnects by itself) and connect
        target: root.device
        function onPairedChanged() {
            if (!root.device?.paired || !root.pairRequested) return;
            root.pairRequested = false;
            root.device.trusted = true;
            root.device.connect();
        }
    }
    text: device?.name || Translation.tr("Unknown device")
    labelColor: device?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
    description: {
        if (device?.connected) return device?.batteryAvailable
            ? Translation.tr("Connected · %1 % battery").arg(Math.round(device.battery * 100)) : Translation.tr("Connected");
        if (connecting) return Translation.tr("Connecting… Is it on and nearby?");
        if (disconnecting) return Translation.tr("Disconnecting…");
        if (pairing) return Translation.tr("Pairing… Put it in pairing mode");
        return known ? Translation.tr("Paired") : Translation.tr("Not paired");
    }

    RippleButtonWithIcon {
        enabled: !root.connecting && !root.disconnecting
        opacity: enabled ? 1 : 0.5
        materialIcon: root.connecting ? "hourglass_top" : root.device?.connected ? "link_off" : root.pairing ? "close" : root.known ? "link" : "add_link"
        mainText: root.connecting ? Translation.tr("Connecting…")
            : root.device?.connected ? Translation.tr("Disconnect")
            : root.pairing ? Translation.tr("Cancel")
            : root.known ? Translation.tr("Connect") : Translation.tr("Pair")
        onClicked: {
            if (root.device?.connected) root.device.disconnect();
            else if (root.pairing) { root.pairRequested = false; root.device.cancelPair(); }
            else if (root.known) root.device.connect();
            else { root.pairRequested = true; root.device.pair(); }
        }
    }
    RippleButtonWithIcon {
        visible: root.known && !root.device?.connected
        materialIcon: "delete"
        mainText: Translation.tr("Forget")
        onClicked: root.device?.forget()
    }
}
