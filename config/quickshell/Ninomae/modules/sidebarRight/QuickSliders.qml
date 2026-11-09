import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The sidebar's sliders in one card: an icon, a slim slider and the figure per row (volume, brightness, mic,
 * as Settings → Sidebar picks). Clicking the volume or mic icon mutes it, the icon goes accent while muted.
 * The corners are set from outside, so the card joins the tiles above it. While music plays it sits inside the
 * player's card instead (SidebarMedia, withSliders), with a clear background and the player's colour as ringColor.
 */
Rectangle {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    readonly property var options: Config.options.sidebar.quickSliders
    property color ringColor: color // The surface under the sliders' knobs
    color: Appearance.colors.colLayer3
    radius: Appearance.rounding.normal
    implicitHeight: rows.implicitHeight + 16

    ColumnLayout {
        id: rows
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 14 }
        spacing: 4
        SliderLine {
            visible: root.options.showVolume
            node: Audio.sink
            symbol: muted ? "volume_off" : "volume_up"
            tip: muted ? Translation.tr("Unmute") : Translation.tr("Mute")
        }
        SliderLine {
            // Only once there's a monitor to control (none yet while Brightness is still finding them)
            visible: root.options.showBrightness && !!root.brightnessMonitor
            symbol: "light_mode"
            level: root.brightnessMonitor?.brightness ?? 0
            apply: value => root.brightnessMonitor?.setBrightness(value)
        }
        SliderLine {
            visible: root.options.showMic
            node: Audio.source
            symbol: muted ? "mic_off" : "mic"
            tip: muted ? Translation.tr("Unmute the mic") : Translation.tr("Mute the mic")
        }
    }

    // A row: the icon (a mute button when it's a sound device), the slider, the figure
    component SliderLine: RowLayout {
        id: line
        property var node: null // A PipeWire device: volume and mute come from it
        property string symbol
        property string tip: ""
        property real level: node?.audio?.volume ?? 0
        readonly property bool muted: node?.audio?.muted ?? false
        // What a drag sets: the device's volume, unless a row says otherwise (brightness)
        property var apply: value => { if (line.node?.audio) line.node.audio.volume = value; }
        Layout.fillWidth: true
        spacing: 10
        IconButton {
            size: 30
            symbol: line.symbol
            tip: line.tip
            enabled: line.node !== null
            toggled: line.muted
            colBackground: "transparent" // A plain icon, a shade on hover
            colBackgroundHover: Appearance.colors.colLayer4Hover
            colRipple: Appearance.colors.colLayer4Active
            onClicked: if (line.node?.audio) line.node.audio.muted = !line.node.audio.muted
        }
        SlimSlider {
            Layout.fillWidth: true
            ringColor: root.ringColor
            level: line.level
            opacity: line.muted ? 0.5 : 1
            onMoved: line.apply(value)
        }
        StyledText {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(line.level * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.numbers
            font.variableAxes: ({})
            color: line.muted ? Appearance.colors.colOutline : Appearance.colors.colSubtext
        }
    }
}
