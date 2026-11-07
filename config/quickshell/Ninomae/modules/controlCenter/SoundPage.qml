pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Sound: the output and the mic, the apps playing or recording, and the devices to pick from
ColumnLayout {
    id: page
    spacing: 14
    readonly property string subtitle: Translation.tr("Speakers, mic and app volumes")

    readonly property var audioNodes: Pipewire.nodes.values.filter(node => node.audio)
    readonly property var outputs: audioNodes.filter(node => node.isSink && !node.isStream)
    readonly property var inputs: audioNodes.filter(node => !node.isSink && !node.isStream)
    readonly property var playing: audioNodes.filter(node => node.isSink && node.isStream)
    readonly property var recording: audioNodes.filter(node => !node.isSink && node.isStream)

    ContentSection {
        title: Translation.tr("Volume")
        VolumeRow { node: Audio.sink; isOutput: true }
        VolumeRow { node: Audio.source; isOutput: false }
    }
    ContentSection {
        visible: page.playing.length > 0
        title: Translation.tr("Apps")
        Repeater {
            model: ScriptModel { values: page.playing }
            delegate: AppRow {}
        }
    }
    ContentSection {
        visible: page.recording.length > 0
        title: Translation.tr("Apps using the mic")
        Repeater {
            model: ScriptModel { values: page.recording }
            delegate: AppRow {}
        }
    }
    RowLayout { // The devices, outputs and inputs side by side
        Layout.fillWidth: true
        spacing: 10
        DeviceList {
            title: Translation.tr("Output device")
            devices: page.outputs
            isOutput: true
        }
        DeviceList {
            title: Translation.tr("Input device")
            devices: page.inputs
            isOutput: false
        }
    }
    ContentSection {
        RowButton {
            text: Translation.tr("Advanced mixer")
            description: Translation.tr("Every app and device, with more options")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                GlobalStates.controlCenterOpen = false;
            }
            MaterialSymbol {
                text: "open_in_new"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }

    // The device in use: its volume, Mute beside the figure, the slider under
    component VolumeRow: SliderRow {
        id: volumeRow
        required property var node
        required property bool isOutput
        readonly property bool muted: node?.audio?.muted ?? false
        visible: node?.audio !== undefined
        text: isOutput ? Translation.tr("Output") : Translation.tr("Mic")
        description: node?.description ?? ""
        level: node?.audio?.volume ?? 0
        dimmed: muted
        onMoved: value => { if (volumeRow.node?.audio) volumeRow.node.audio.volume = value; }
        trailing: RippleButton { // Mute: accent while muted
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.chip
            toggled: volumeRow.muted
            colBackground: Appearance.m3colors.m3surfaceContainerHigh
            colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
            onClicked: if (volumeRow.node?.audio) volumeRow.node.audio.muted = !volumeRow.node.audio.muted
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: volumeRow.muted ? (volumeRow.isOutput ? "volume_off" : "mic_off") : (volumeRow.isOutput ? "volume_up" : "mic")
                iconSize: 18
                fill: volumeRow.muted ? 1 : 0
                color: volumeRow.muted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }
            StyledToolTip {
                text: volumeRow.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            }
        }
    }

    // An app: its icon, name and what it's playing, its volume. Its node goes null for a moment as the app
    // stops (the row is on its way out): everything reads it with ?.
    component AppRow: SliderRow {
        id: appRow
        required property PwNode modelData
        readonly property PwNode node: modelData
        text: !node ? "" : node.properties["application.name"] ?? (node.description !== "" ? node.description : node.name)
        description: node?.properties["media.name"] ?? ""
        level: node?.audio?.volume ?? 0
        dimmed: node?.audio?.muted ?? false
        onMoved: value => { if (appRow.node?.audio) appRow.node.audio.volume = value; }
        PwObjectTracker { objects: [appRow.node] }
        leading: Image {
            visible: source != ""
            sourceSize: Qt.size(28, 28)
            source: {
                if (!appRow.node) return "";
                const named = AppSearch.guessIcon(appRow.node.properties["application.icon-name"]);
                if (AppSearch.iconExists(named)) return Quickshell.iconPath(named, "image-missing");
                return Quickshell.iconPath(AppSearch.guessIcon(appRow.node.properties["node.name"]), "image-missing");
            }
        }
    }

    // Click one to use it; the one in use has its name in accent and a check
    component DeviceList: ContentSection {
        id: deviceList
        required property var devices
        required property bool isOutput
        readonly property var inUse: isOutput ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        Layout.preferredWidth: 1 // Two equal halves
        Layout.alignment: Qt.AlignTop
        Repeater {
            model: ScriptModel { values: deviceList.devices }
            delegate: RowButton {
                id: deviceRow
                required property var modelData
                current: modelData.id === deviceList.inUse?.id
                text: modelData.description || modelData.name
                onClicked: {
                    if (deviceList.isOutput) Pipewire.preferredDefaultAudioSink = modelData;
                    else Pipewire.preferredDefaultAudioSource = modelData;
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
