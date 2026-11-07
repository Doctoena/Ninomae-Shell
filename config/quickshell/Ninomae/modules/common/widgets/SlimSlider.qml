import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * A slim slider (the control centre, Settings): a thin neutral track, an accent gradient filling it up to a
 * round knob that sits on a ring of the card's colour. Pointing at it or dragging shows a soft halo; a change
 * from elsewhere (media keys, another app) glides there. Drag, click or scroll (2 % a notch; Settings turns
 * the wheel off, where it scrolls the page).
 * Bind `level` (not `value`) to the setting and write it back in onMoved: while it's held the slider follows only
 * the pointer, so the setting's own echo (PipeWire rounds the volume, brightness is applied a beat later)
 * can't pull the knob back and forth.
 */
Slider {
    id: root
    property color ringColor: Appearance.colors.colLayer2 // The card it sits on
    property real level: 0 // The setting's current value
    Binding on value {
        when: !root.pressed
        value: root.level
        restoreMode: Binding.RestoreNone
    }
    implicitHeight: 28
    padding: 0
    leftPadding: 4
    rightPadding: 4
    wheelEnabled: true
    stepSize: Math.abs(to - from) / 50
    opacity: enabled ? 1 : 0.4

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: 6
        Rectangle { // Track
            anchors.fill: parent
            radius: height / 2
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.86)
        }
        Rectangle { // Fill, up to the knob's centre
            width: Math.max(height, knob.x + knob.width / 2 - root.leftPadding)
            height: parent.height
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) }
                GradientStop { position: 1; color: Appearance.colors.colPrimary }
            }
        }
    }

    handle: Item {
        id: knob
        width: 18
        height: 18
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        Behavior on x { // Glide to a change made elsewhere, follow the pointer exactly while dragging
            enabled: !root.pressed
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Rectangle { // Halo
            anchors.centerIn: parent
            width: root.pressed ? 34 : root.hovered ? 30 : 18
            height: width
            radius: width / 2
            color: Appearance.colors.colPrimary
            opacity: root.pressed ? 0.22 : root.hovered ? 0.14 : 0
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Rectangle { // Ring of the card's colour, so the knob sits above the track
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: 11
            color: root.ringColor
        }
        Rectangle { // Knob
            anchors.centerIn: parent
            width: root.pressed ? 14 : 16
            height: width
            radius: width / 2
            color: Appearance.colors.colPrimary
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
