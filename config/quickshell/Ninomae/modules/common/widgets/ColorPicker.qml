import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Pick any colour: a saturation/brightness square, a hue bar and a hex field. `color` is what it shows;
 * a change made here comes out as edited(color) for the owner to store (and feed back into `color`).
 * Drags don't scroll a Flickable it sits in.
 */
ColumnLayout {
    id: root
    property color color: "#ffffff"
    signal edited(color color)
    spacing: 10

    // Hue, saturation, value, kept here: a grey has no hue, so it isn't read back from `color` mid-drag
    property real h: 0
    property real s: 0
    property real v: 1
    readonly property bool dragging: svArea.pressed || hueArea.pressed
    function sync() {
        if (root.dragging) return;
        if (root.color.hsvHue >= 0) root.h = root.color.hsvHue;
        root.s = root.color.hsvSaturation;
        root.v = root.color.hsvValue;
    }
    onColorChanged: sync()
    Component.onCompleted: sync()
    function clamp(x) { return Math.max(0, Math.min(1, x)); }
    // The handles travel inset by their own radius (and a little), so at the extremes they stay inside the
    // rounded corners and ends instead of hanging off them
    readonly property real svPad: 11
    readonly property real huePad: 10
    readonly property string hex: Qt.hsva(root.h, root.s, root.v, 1).toString()
    function send() { root.edited(Qt.hsva(root.h, root.s, root.v, 1)); }
    // The field follows the colour, except while it's being typed in
    onHexChanged: if (!hexField.activeFocus) hexField.text = hex

    Rectangle { // Saturation left → right, brightness bottom → top
        id: sv
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        radius: Appearance.rounding.normal
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "white" }
            GradientStop { position: 1; color: Qt.hsva(root.h, 1, 1, 1) }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: "black" }
            }
        }
        Rectangle { // Handle
            width: 18; height: 18; radius: 9
            x: root.svPad + root.s * (sv.width - root.svPad * 2) - width / 2
            y: root.svPad + (1 - root.v) * (sv.height - root.svPad * 2) - height / 2
            color: Qt.hsva(root.h, root.s, root.v, 1)
            border.width: 2; border.color: "white"
            Rectangle { anchors.fill: parent; anchors.margins: -1; radius: width / 2; color: "transparent"; border.width: 1; border.color: "#60000000" }
        }
        MouseArea {
            id: svArea
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.CrossCursor
            function at(m) {
                root.s = root.clamp((m.x - root.svPad) / (width - root.svPad * 2));
                root.v = 1 - root.clamp((m.y - root.svPad) / (height - root.svPad * 2));
                root.send();
            }
            onPressed: m => at(m)
            onPositionChanged: m => { if (pressed) at(m); }
        }
    }

    Rectangle { // Hue
        id: hueBar
        // The colours laid along the handle's (inset) travel, so the one under it is the one picked
        function stop(f) { return width > 0 ? (root.huePad + f * (width - root.huePad * 2)) / width : f; }
        Layout.fillWidth: true
        Layout.preferredHeight: 16
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: hueBar.stop(0 / 6); color: Qt.hsva(0 / 6, 1, 1, 1) }
            GradientStop { position: hueBar.stop(1 / 6); color: Qt.hsva(1 / 6, 1, 1, 1) }
            GradientStop { position: hueBar.stop(2 / 6); color: Qt.hsva(2 / 6, 1, 1, 1) }
            GradientStop { position: hueBar.stop(3 / 6); color: Qt.hsva(3 / 6, 1, 1, 1) }
            GradientStop { position: hueBar.stop(4 / 6); color: Qt.hsva(4 / 6, 1, 1, 1) }
            GradientStop { position: hueBar.stop(5 / 6); color: Qt.hsva(5 / 6, 1, 1, 1) }
            GradientStop { position: hueBar.stop(6 / 6); color: Qt.hsva(0.999, 1, 1, 1) }
        }
        Rectangle { // Handle
            width: 20; height: 20; radius: 10
            anchors.verticalCenter: parent.verticalCenter
            x: root.huePad + root.h * (hueBar.width - root.huePad * 2) - width / 2
            color: Qt.hsva(root.h, 1, 1, 1)
            border.width: 2; border.color: "white"
        }
        MouseArea {
            id: hueArea
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function at(m) { root.h = Math.min(0.999, root.clamp((m.x - root.huePad) / (width - root.huePad * 2))); root.send(); }
            onPressed: m => at(m)
            onPositionChanged: m => { if (pressed) at(m); }
        }
    }

    RowLayout { // The colour, and its hex code to read or type
        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            Layout.preferredWidth: 40; Layout.preferredHeight: 40
            radius: Appearance.rounding.container
            color: Qt.hsva(root.h, root.s, root.v, 1)
            border.width: 1; border.color: "#30ffffff"
        }
        MaterialTextField {
            id: hexField
            Layout.fillWidth: true
            wrapMode: TextEdit.NoWrap
            placeholderText: "#rrggbb"
            Component.onCompleted: text = root.hex
            function apply() {
                const t = text.trim().replace(/^#?/, "#");
                if (/^#[0-9a-fA-F]{6}$/.test(t)) root.edited(t);
                text = /^#[0-9a-fA-F]{6}$/.test(t) ? t.toLowerCase() : root.hex; // Not a colour: back to the current one
            }
            onAccepted: apply()
            onEditingFinished: apply()
        }
    }
}
