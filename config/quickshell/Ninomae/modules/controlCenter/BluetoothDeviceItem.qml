import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
DialogListItem {
    id: root
    required property var device
    property bool expanded: false
    // Remembered by BlueZ (paired, bonded or trusted): it connects. Anything else is paired first
    readonly property bool known: (device?.paired || device?.bonded || device?.trusted) ?? false
    readonly property bool pairing: device?.pairing ?? false
    Connections { // Paired from here: trust it (so it reconnects by itself) and connect
        target: root.device
        function onPairedChanged() {
            if (!root.device?.paired || !root.pairRequested) return;
            root.pairRequested = false;
            root.device.trusted = true;
            root.device.connect();
        }
    }
    property bool pairRequested: false
    pointingHandCursor: !expanded
    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded
    component ActionButton: DialogButton {
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colText: Appearance.colors.colOnSurface
    }
    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0
        RowLayout {
            spacing: 12
            QuickDialogIcon {
                icon: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                active: root.device?.connected ?? false
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: (root.device?.connected) ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                    font.weight: (root.device?.connected) ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    text: root.device?.name || Translation.tr("Unknown device")
                }
                StyledText { // Only when it says something: unpaired devices sit under "Nearby" already
                    Layout.fillWidth: true
                    visible: text !== ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        let statusText = root.device?.connected ? Translation.tr("Connected")
                            : root.pairing ? Translation.tr("Pairing…")
                            : root.known ? Translation.tr("Paired") : "";
                        if (root.device?.connected && root.device?.batteryAvailable)
                            statusText += ` · ${Math.round(root.device.battery * 100)}%`;
                        return statusText;
                    }
                }
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: 20
                color: Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
        RowLayout {
            visible: root.expanded
            Layout.topMargin: 8
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                buttonText: root.device?.connected ? Translation.tr("Disconnect")
                    : root.pairing ? Translation.tr("Cancel")
                    : root.known ? Translation.tr("Connect") : Translation.tr("Pair")
                onClicked: {
                    if (root.device?.connected) root.device.disconnect();
                    else if (root.pairing) { root.pairRequested = false; root.device.cancelPair(); }
                    else if (root.known) root.device.connect();
                    else { root.pairRequested = true; root.device.pair(); } // Put it in pairing mode first
                }
            }
            ActionButton {
                visible: root.known
                buttonText: Translation.tr("Forget")
                onClicked: {
                    root.device?.forget();
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
