import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Bluetooth
AndroidQuickToggleButton {
    id: root
    name: Translation.tr("Bluetooth")
    statusText: BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("No device")
    toggled: BluetoothStatus.enabled
    buttonIcon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
    mainAction: () => {
        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter?.enabled
    }
    altAction: () => {
        root.openMenu()
    }
    StyledToolTip {
        text: (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Bluetooth"))
            + (BluetoothStatus.activeDeviceCount > 1 ? ` +${BluetoothStatus.activeDeviceCount - 1}` : "")
    }
}
