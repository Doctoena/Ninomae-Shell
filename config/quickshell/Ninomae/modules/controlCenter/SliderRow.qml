import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A control centre row with a level on a slider, as Settings' number rows: the name and the line about it on the
 * left, the value top right in a box you can type in, the slider across under. It follows the pointer while it's
 * dragged and reports every step in moved(), so the volume or brightness changes as you go.
 * `factor` turns the level into the figure shown (100: 0–1 as a percentage). `leading` goes before the name
 * (an app's icon), `trailing` after the value (Mute).
 */
SettingsCard {
    id: root
    property string text
    property string description
    property real level: 0
    property real from: 0
    property real to: 1
    property real factor: 100
    property bool dimmed: false // Muted: the name and figure grey out
    property alias leading: leadingRow.data
    property alias trailing: trailingRow.data
    signal moved(real value)
    verticalPadding: 12
    content: ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        opacity: root.enabled ? 1 : 0.4
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            RowLayout {
                id: leadingRow
                visible: children.length > 0
                spacing: 8
            }
            RowText {
                text: root.text
                description: root.description
                color: root.dimmed ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
            }
            NumberField { // Type it, or slide it below
                Layout.alignment: Qt.AlignTop
                value: Math.round(root.level * root.factor)
                from: root.from * root.factor
                to: root.to * root.factor
                onAccepted: newValue => root.moved(newValue / root.factor)
            }
            RowLayout {
                id: trailingRow
                Layout.alignment: Qt.AlignTop
                visible: children.length > 0
                spacing: 6
            }
        }
        SlimSlider {
            Layout.fillWidth: true
            Layout.leftMargin: -4 // The knob's own room: the track lines up with the text
            Layout.rightMargin: -4
            ringColor: root.color
            from: root.from
            to: root.to
            wheelEnabled: false // The wheel scrolls the page
            level: root.level
            onMoved: root.moved(value)
        }
    }
}
