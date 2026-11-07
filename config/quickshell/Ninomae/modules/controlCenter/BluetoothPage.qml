import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Bluetooth: what's connected, what's paired, then everything else in range. It searches while the page is open
ColumnLayout {
    id: page
    spacing: 10
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    // Named devices only (some just show a MAC address): connected, then paired, then the rest
    readonly property var devices: [...Bluetooth.devices.values].filter(device => {
        const macRegex = /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/;
        return !macRegex.test(device.name);
    }).sort((a, b) => (b.connected - a.connected) || (page.known(b) - page.known(a)) || a.name.localeCompare(b.name))
    readonly property var connectedDevices: devices.filter(d => d.connected)
    // Paired = remembered by BlueZ: paired, bonded or trusted (a device can be trusted without a pairing)
    function known(d) { return d.paired || d.bonded || d.trusted; }
    readonly property var pairedDevices: devices.filter(d => known(d) && !d.connected)
    readonly property var nearbyDevices: devices.filter(d => !known(d) && !d.connected)

    readonly property string subtitle: !adapter ? Translation.tr("No Bluetooth adapter")
        : !on ? Translation.tr("Off")
        : connectedDevices.length === 1 ? Translation.tr("Connected to %1").arg(connectedDevices[0].name)
        : connectedDevices.length > 1 ? Translation.tr("%1 devices connected").arg(connectedDevices.length)
        : adapter.discovering ? Translation.tr("Searching…") : Translation.tr("No device connected")
    readonly property bool hasSwitch: adapter !== null
    readonly property bool switchChecked: on
    function setSwitch(enabled) { if (adapter) adapter.enabled = enabled; }

    // Search while the page is open (and from the moment it's turned on here)
    function search() { if (adapter?.enabled) adapter.discovering = true; }
    Component.onCompleted: search()
    Component.onDestruction: if (adapter?.enabled) adapter.discovering = false
    Connections {
        target: page.adapter
        function onEnabledChanged() { page.search(); }
    }

    StyledIndeterminateProgressBar {
        visible: page.on && (page.adapter?.discovering ?? false)
        Layout.fillWidth: true
    }
    PagePlaceholder {
        visible: !page.on
        icon: "bluetooth_disabled"
        text: page.adapter ? Translation.tr("Bluetooth is off") : Translation.tr("No Bluetooth adapter")
    }

    // What's connected: a big card each, two to a row, battery large where the device reports it
    GridLayout {
        visible: page.on && page.connectedDevices.length > 0
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: ScriptModel { values: page.connectedDevices }
            delegate: HeroCard {
                required property BluetoothDevice modelData
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                symbol: Icons.getBluetoothDeviceMaterialSymbol(modelData?.icon || "")
                title: modelData?.name ?? ""
                detail: Translation.tr("Connected")
                value: modelData?.batteryAvailable ? Math.round(modelData.battery * 100) : ""
                unit: Translation.tr("% battery")
                actions: DialogButton {
                    buttonText: Translation.tr("Disconnect")
                    onClicked: modelData?.disconnect()
                }
            }
        }
    }
    Section {
        visible: page.on && page.pairedDevices.length > 0
        text: Translation.tr("Paired")
    }
    DeviceGroup { devices: page.pairedDevices }
    Section {
        visible: page.on && page.nearbyDevices.length > 0
        text: Translation.tr("Nearby")
    }
    DeviceGroup { devices: page.nearbyDevices }

    RowLayout {
        Layout.topMargin: 6
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Bluetooth settings")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.controlCenterOpen = false;
            }
        }
    }

    component Section: WindowDialogSectionHeader {
        Layout.topMargin: 8
    }
    component DeviceGroup: QuickDialogGroup {
        id: group
        required property var devices
        visible: page.on && devices.length > 0
        Repeater {
            model: ScriptModel { values: group.devices }
            delegate: BluetoothDeviceItem {
                required property BluetoothDevice modelData
                device: modelData
                Layout.fillWidth: true
            }
        }
    }
}
