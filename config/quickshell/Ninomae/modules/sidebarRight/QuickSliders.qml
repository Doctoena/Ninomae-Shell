import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The sidebar's sliders in one card, as the control centre's rows: a squircle, a filled bar and the figure per row
 * (volume, brightness, mic, as Settings → Sidebar picks). The volume and mic squircles are Mute: accent while the
 * sound is on. The figure can be typed in.
 * The corners are set from outside, so the card joins the tiles above it. While music plays it sits inside the
 * player's card instead (SidebarMedia, withSliders), with a clear background and the player's colour as ringColor.
 */
Rectangle {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    readonly property var options: Config.options.sidebar.quickSliders
    property color ringColor: color // The surface under the sliders' knobs
    color: Appearance.colors.colGlass
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

    // A row: the squircle (Mute when it's a sound device), the bar, the figure
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
        spacing: 12
        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: 11
            enabled: line.node !== null
            toggled: line.node !== null && !line.muted
            // The light tint the toggles' squircles use (the glass's inner colour vanished over lighter wallpaper)
            colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.84)
            colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.78)
            onClicked: if (line.node?.audio) line.node.audio.muted = !line.node.audio.muted
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: line.symbol
                iconSize: 20
                fill: 1
                color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            StyledToolTip {
                extraVisibleCondition: line.tip !== ""
                text: line.tip
            }
        }
        SlimSlider {
            Layout.fillWidth: true
            filledBar: true
            ringColor: root.ringColor
            level: line.level
            opacity: line.muted ? 0.5 : 1
            onMoved: line.apply(value)
        }
        NumberField {
            plain: true
            unit: "%"
            value: Math.round(line.level * 100)
            from: 0
            to: 100
            opacity: line.muted ? 0.6 : 1
            onAccepted: newValue => line.apply(newValue / 100)
        }
    }
}
