import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell
WindowDialog {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    // Named devices only (some just show a MAC address): connected, then paired, then the rest
    readonly property var devices: [...Bluetooth.devices.values].filter(device => {
        const macRegex = /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/;
        return !macRegex.test(device.name);
    }).sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property var connectedDevices: devices.filter(d => d.connected)
    readonly property var pairedDevices: devices.filter(d => d.paired && !d.connected)
    readonly property var nearbyDevices: devices.filter(d => !d.paired && !d.connected)
    // Sized to what's there, up to 600 (the list scrolls past that)
    backgroundHeight: Math.min(600, body.implicitHeight + 36)

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        QuickDialogHeader {
            icon: "bluetooth"
            title: Translation.tr("Bluetooth")
            subtitle: !root.on ? Translation.tr("Off")
                : root.connectedDevices.length === 1 ? Translation.tr("Connected to %1").arg(root.connectedDevices[0].name)
                : root.connectedDevices.length > 1 ? Translation.tr("%1 devices connected").arg(root.connectedDevices.length)
                : (root.adapter?.discovering ?? false) ? Translation.tr("Searching…") : Translation.tr("No device connected")
            showSwitch: root.adapter !== null
            checked: root.on
            onSwitchToggled: checked => { if (root.adapter) root.adapter.enabled = checked; }
        }
        StyledIndeterminateProgressBar {
            visible: root.on && (root.adapter?.discovering ?? false)
            Layout.fillWidth: true
        }

        // What's connected, in a card of its own
        QuickDialogGroup {
            visible: root.on && root.connectedDevices.length > 0
            Repeater {
                model: ScriptModel { values: root.connectedDevices }
                delegate: BluetoothDeviceItem {
                    required property BluetoothDevice modelData
                    device: modelData
                    Layout.fillWidth: true
                }
            }
        }

        // Paired before but not connected now: usually a few, so they all show
        WindowDialogSectionHeader {
            visible: root.on && root.pairedDevices.length > 0
            text: Translation.tr("Paired")
        }
        QuickDialogGroup {
            visible: root.on && root.pairedDevices.length > 0
            Repeater {
                model: ScriptModel { values: root.pairedDevices }
                delegate: BluetoothDeviceItem {
                    required property BluetoothDevice modelData
                    device: modelData
                    Layout.fillWidth: true
                }
            }
        }

        // Everything else in range (neighbours' TVs and lights too): this one scrolls
        WindowDialogSectionHeader {
            visible: root.on && nearby.count > 0
            text: Translation.tr("Nearby")
        }
        QuickDialogGroup {
            visible: root.on && nearby.count > 0
            Layout.fillHeight: true
            Layout.preferredHeight: nearby.contentHeight + padding * 2
            ListView {
                id: nearby
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: root.nearbyDevices }
                delegate: BluetoothDeviceItem {
                    required property BluetoothDevice modelData
                    device: modelData
                    width: ListView.view.width
                }
            }
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Settings")
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
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
