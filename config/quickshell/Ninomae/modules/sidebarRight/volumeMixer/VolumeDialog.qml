pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
WindowDialog {
    id: root
    property bool isSink: true
    function correctType(node) {
        return (node.isSink === root.isSink) && node.audio
    }
    readonly property list<var> appPwNodes: Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
        return root.correctType(node) && node.isStream
    })
    readonly property list<var> devices: Pipewire.nodes.values.filter(node => root.correctType(node) && !node.isStream)
    readonly property bool hasApps: appPwNodes.length > 0
    readonly property var defaultNode: root.isSink ? Audio.sink : Audio.source
    // The device actually in use (preferredDefault… is only set once one has been picked by hand)
    readonly property var activeDevice: root.isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
    // Sized to what's there, up to 600
    backgroundHeight: Math.min(600, body.implicitHeight + 36)

    function deviceIcon(node) {
        const text = `${node.description ?? ""} ${node.name ?? ""}`.toLowerCase();
        if (!root.isSink) return text.includes("bluez") || text.includes("headset") ? "headset_mic" : "mic";
        if (text.includes("hdmi") || text.includes("displayport")) return "tv";
        if (text.includes("bluez") || text.includes("headphone") || text.includes("headset")) return "headphones";
        return "speaker";
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        QuickDialogHeader {
            icon: root.isSink ? "volume_up" : "mic"
            title: root.isSink ? Translation.tr("Sound") : Translation.tr("Mic")
            subtitle: root.activeDevice?.description ?? ""
        }

        // Volume of the device in use; its squircle mutes
        QuickDialogGroup {
            visible: root.defaultNode?.audio !== undefined
            padding: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                QuickDialogIcon {
                    readonly property bool muted: root.defaultNode?.audio?.muted ?? false
                    icon: muted ? (root.isSink ? "volume_off" : "mic_off") : (root.isSink ? "volume_up" : "mic")
                    active: !muted
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.defaultNode?.audio) root.defaultNode.audio.muted = !root.defaultNode.audio.muted
                    }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.S
                    stopIndicatorValues: [] // The percentage beside it already says where it is
                    value: root.defaultNode?.audio?.volume ?? 0
                    onMoved: if (root.defaultNode?.audio) root.defaultNode.audio.volume = value
                }
                StyledText {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: Math.round((root.defaultNode?.audio?.volume ?? 0) * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        WindowDialogSectionHeader {
            visible: root.hasApps
            text: Translation.tr("Applications")
        }
        QuickDialogGroup {
            visible: root.hasApps
            padding: 10
            Layout.fillHeight: true
            Layout.preferredHeight: apps.contentHeight + padding * 2
            ListView {
                id: apps
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: root.appPwNodes }
                delegate: VolumeMixerEntry {
                    required property var modelData
                    node: modelData
                    width: ListView.view.width
                }
            }
        }

        WindowDialogSectionHeader {
            text: Translation.tr("Devices")
        }
        QuickDialogGroup {
            Repeater {
                model: ScriptModel { values: root.devices }
                delegate: DialogListItem {
                    id: deviceRow
                    required property var modelData
                    readonly property bool inUse: modelData.id === root.activeDevice?.id
                    Layout.fillWidth: true
                    active: inUse
                    onClicked: {
                        if (root.isSink) Pipewire.preferredDefaultAudioSink = modelData;
                        else Pipewire.preferredDefaultAudioSource = modelData;
                    }
                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: deviceRow.horizontalPadding; rightMargin: deviceRow.horizontalPadding
                            topMargin: deviceRow.verticalPadding; bottomMargin: deviceRow.verticalPadding
                        }
                        spacing: 12
                        QuickDialogIcon {
                            icon: root.deviceIcon(deviceRow.modelData)
                            active: deviceRow.inUse
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: deviceRow.modelData.description || deviceRow.modelData.name
                            color: deviceRow.inUse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                            font.weight: deviceRow.inUse ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            visible: deviceRow.inUse
                            text: "check"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Settings")
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
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
