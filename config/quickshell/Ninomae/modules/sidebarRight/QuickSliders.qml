import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
Rectangle {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    implicitWidth: contentItem.implicitWidth + root.horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + root.verticalPadding * 2
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1 // Soft borderless card, like the bar popups
    property real verticalPadding: 4
    property real horizontalPadding: 12
    // Decorative accent dots — left side
    Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 8
        anchors.topMargin: 6
        spacing: 4
        z: 1
        Repeater {
            model: 3
            Rectangle {
                width: 4; height: 4; radius: 2
                color: index === 0
                    ? Appearance.colors.colPrimary
                    : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65 + index * 0.12)
            }
        }
    }
    Column {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
        }
        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            // Only once there's a monitor to control (none yet while Brightness is still finding them)
            active: Config.options.sidebar.quickSliders.showBrightness && !!root.brightnessMonitor
            sourceComponent: QuickSlider {
                materialSymbol: "brightness_6"
                value: root.brightnessMonitor.brightness
                onMoved: {
                    root.brightnessMonitor.setBrightness(value)
                }
            }
        }
        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showVolume
            sourceComponent: QuickSlider {
                materialSymbol: "volume_up"
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.sink?.audio) Audio.sink.audio.volume = value
                }
            }
        }
        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showMic
            sourceComponent: QuickSlider {
                materialSymbol: "mic"
                value: Audio.source?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.source?.audio) Audio.source.audio.volume = value
                }
            }
        }
    }
    component QuickSlider: StyledSlider {
        id: quickSlider
        required property string materialSymbol
        configuration: StyledSlider.Configuration.M
        stopIndicatorValues: []
        MaterialSymbol {
            id: icon
            property bool nearFull: quickSlider.value >= 0.9
            anchors {
                verticalCenter: parent.verticalCenter
                right: nearFull ? quickSlider.handle.right : parent.right
                rightMargin: quickSlider.nearFull ? 14 : 8
            }
            iconSize: 20
            color: nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: quickSlider.materialSymbol
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on anchors.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
