pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Sound: the output and the mic side by side, the apps playing or recording, and the devices to pick from
ColumnLayout {
    id: page
    spacing: 10
    readonly property string subtitle: Translation.tr("Speakers, mic and app volumes")

    readonly property var audioNodes: Pipewire.nodes.values.filter(node => node.audio)
    readonly property var outputs: audioNodes.filter(node => node.isSink && !node.isStream)
    readonly property var inputs: audioNodes.filter(node => !node.isSink && !node.isStream)
    readonly property var playing: audioNodes.filter(node => node.isSink && node.isStream)
    readonly property var recording: audioNodes.filter(node => !node.isSink && node.isStream)

    function deviceIcon(node, isOutput) {
        const text = `${node?.description ?? ""} ${node?.name ?? ""}`.toLowerCase();
        if (!isOutput) return text.includes("bluez") || text.includes("headset") ? "headset_mic" : "mic";
        if (text.includes("hdmi") || text.includes("displayport")) return "tv";
        if (text.includes("bluez") || text.includes("headphone") || text.includes("headset")) return "headphones";
        return "speaker";
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        VolumeCard {
            title: Translation.tr("Output")
            node: Audio.sink
            isOutput: true
        }
        VolumeCard {
            title: Translation.tr("Input")
            node: Audio.source
            isOutput: false
        }
    }

    Section {
        visible: page.playing.length > 0
        text: Translation.tr("Apps")
    }
    AppList { nodes: page.playing }
    Section {
        visible: page.recording.length > 0
        text: Translation.tr("Apps using the mic")
    }
    AppList { nodes: page.recording }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 10
        DeviceList {
            title: Translation.tr("Output devices")
            devices: page.outputs
            isOutput: true
        }
        DeviceList {
            title: Translation.tr("Input devices")
            devices: page.inputs
            isOutput: false
        }
    }

    RowLayout {
        Layout.topMargin: 6
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Advanced mixer")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                GlobalStates.controlCenterOpen = false;
            }
        }
    }

    component Section: WindowDialogSectionHeader {
        Layout.topMargin: 8
    }

    // The device in use: its volume large, a Mute button beside it, the slider under
    component VolumeCard: HeroCard {
        id: card
        required property var node
        required property bool isOutput
        readonly property bool muted: node?.audio?.muted ?? false
        Layout.preferredWidth: 1 // Two equal halves
        visible: node?.audio !== undefined
        symbol: muted ? (isOutput ? "volume_off" : "mic_off") : (isOutput ? "volume_up" : "mic")
        active: !muted
        detail: node?.description ?? ""
        value: Math.round((node?.audio?.volume ?? 0) * 100)
        unit: "%"
        dimmed: muted
        actions: DialogButton {
            buttonText: card.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            onClicked: if (card.node?.audio) card.node.audio.muted = !card.node.audio.muted
        }
        SlimSlider {
            Layout.fillWidth: true
            level: card.node?.audio?.volume ?? 0
            onMoved: if (card.node?.audio) card.node.audio.volume = value
        }
    }

    // An app per row: its icon, name and what it's playing, a slider and the percentage
    component AppList: QuickDialogGroup {
        id: appList
        required property var nodes
        visible: nodes.length > 0
        padding: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: ScriptModel { values: appList.nodes }
                delegate: VolumeMixerEntry {
                    required property var modelData
                    node: modelData
                    Layout.fillWidth: true
                }
            }
        }
    }

    // Click one to use it; the one in use has its icon in accent and a check
    component DeviceList: ColumnLayout {
        id: deviceList
        required property string title
        required property var devices
        required property bool isOutput
        readonly property var inUse: isOutput ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: 8
        WindowDialogSectionHeader { text: deviceList.title }
        QuickDialogGroup {
            Repeater {
                model: ScriptModel { values: deviceList.devices }
                delegate: DialogListItem {
                    id: deviceRow
                    required property var modelData
                    readonly property bool current: modelData.id === deviceList.inUse?.id
                    Layout.fillWidth: true
                    active: current
                    onClicked: {
                        if (deviceList.isOutput) Pipewire.preferredDefaultAudioSink = modelData;
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
                            icon: page.deviceIcon(deviceRow.modelData, deviceList.isOutput)
                            active: deviceRow.current
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: deviceRow.modelData.description || deviceRow.modelData.name
                            color: deviceRow.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                            font.weight: deviceRow.current ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            visible: deviceRow.current
                            text: "check"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
