import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A settings row with a number on a slider: a card of its own, the name and the line about it on the left, the
 * value top right in a box you can type in (NumberField), the slider across under. Give it
 * `option: "dock.height"` to read and write that option (times `factor`: 100 shows a 0–1 option as a percentage, 0.001 shows milliseconds as seconds), or bind `value` and
 * handle `onValueChanged` yourself. `suffix` is the unit, in the name: "Height (px)". It saves when you let go,
 * not at every step of a drag. (Named for the number box it used to be.)
 */
SettingsCard {
    id: root
    property string text: ""
    property string tooltip: ""
    property string description: ""
    property string option: ""
    property real factor: 1
    property string suffix: ""
    property real value: 0
    property real stepSize: 1
    property real from: 0
    property real to: 100
    readonly property int decimals: Math.max(0, (String(stepSize).split(".")[1] ?? "").length)
    verticalPadding: 12
    Binding {
        when: root.option !== ""
        target: root
        property: "value"
        value: Math.round((Config.get(root.option) ?? 0) * root.factor * 1000) / 1000
    }
    function commit() {
        if (root.option === "") return;
        Config.set(root.option, root.factor < 1 ? Math.round(root.value / root.factor) // 7 / 0.001 can be 6999.99…
            : root.value / root.factor);
    }
    content: ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        opacity: root.enabled ? 1 : 0.4
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            RowText {
                text: root.suffix !== "" ? `${root.text} (${root.suffix})` : root.text
                description: root.description !== "" ? root.description : root.tooltip
            }
            NumberField { // Type it, or slide it below
                Layout.alignment: Qt.AlignTop
                value: root.value
                from: root.from
                to: root.to
                decimals: root.decimals
                stepSize: root.stepSize
                onAccepted: newValue => { root.value = newValue; root.commit(); }
            }
        }
        SlimSlider {
            Layout.fillWidth: true
            Layout.leftMargin: -4 // The knob's own room: the track lines up with the text
            Layout.rightMargin: -4
            ringColor: root.color
            from: root.from
            to: root.to
            stepSize: root.stepSize
            snapMode: Slider.SnapAlways
            wheelEnabled: false // The wheel scrolls the page: a slider under the pointer mustn't take it
            level: root.value
            onMoved: {
                root.value = Math.round(value / root.stepSize) * root.stepSize;
                if (!pressed) root.commit(); // A click on the track: done
            }
            onPressedChanged: if (!pressed) root.commit() // The end of a drag
        }
    }
}
