import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The sidebar's sliders (S2b): each a thick capsule filled to its level in a lit accent gradient with a light along
 * its top, the icon on the fill's left end and the figure at the right (volume, brightness, mic, as Settings →
 * Sidebar picks). Drag or scroll anywhere on it to set it. The volume and mic icons are Mute (the fill dims while
 * muted). The figure can be typed in.
 * Straight on the controls well, or inside the player's card while music plays (SidebarMedia, withSliders).
 */
Item {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    readonly property var options: Config.options.sidebar.quickSliders
    implicitHeight: rows.implicitHeight

    ColumnLayout {
        id: rows
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 6
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

    // A row: the capsule, filled to the level, the icon (Mute when it's a sound device) and the figure on it
    component SliderLine: Item {
        id: line
        property var node: null // A PipeWire device: volume and mute come from it
        property string symbol
        property string tip: ""
        property real level: node?.audio?.volume ?? 0
        readonly property bool muted: node?.audio?.muted ?? false
        // What a drag sets: the device's volume, unless a row says otherwise (brightness)
        property var apply: value => { if (line.node?.audio) line.node.audio.volume = value; }
        readonly property real inner: width - 6
        Layout.fillWidth: true
        implicitHeight: 42

        Rectangle { // The capsule
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.04)
            border { width: 1; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7) }
        }
        Rectangle { // The fill
            x: 3
            y: 3
            height: parent.height - 6
            width: Math.max(height, line.inner * Math.min(1, line.level))
            radius: height / 2
            opacity: line.muted ? 0.45 : 1
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) }
                GradientStop { position: 1; color: Appearance.colors.colPrimary }
            }
            Rectangle { // Its top light
                x: 12
                y: 1
                width: Math.max(0, parent.width - 24)
                height: 1
                color: Qt.rgba(1, 1, 1, 0.55)
            }
        }
        MouseArea { // Drag or click anywhere to set it, scroll to step it
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function set(x) { line.apply(Math.max(0, Math.min(1, (x - 3) / line.inner))); }
            onPressed: event => set(event.x)
            onPositionChanged: event => { if (pressed) set(event.x); }
            onWheel: event => line.apply(Math.max(0, Math.min(1, line.level + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
        MouseArea { // The icon: Mute
            id: muteArea
            x: 3
            y: 3
            width: parent.height - 6
            height: width
            enabled: line.node !== null
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (line.node?.audio) line.node.audio.muted = !line.node.audio.muted
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, muteArea.containsPress ? 0.2 : muteArea.containsMouse ? 0.12 : 0)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: line.symbol
                iconSize: 19
                fill: 1
                color: Appearance.colors.colOnPrimary
            }
            StyledToolTip { // A MouseArea has no `hovered`: say when it's pointed at (and shown)
                extraVisibleCondition: line.tip !== "" && line.visible && muteArea.containsMouse
                text: line.tip
            }
        }
        NumberField {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
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
