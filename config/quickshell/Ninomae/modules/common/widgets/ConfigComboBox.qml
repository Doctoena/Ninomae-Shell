import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with a dropdown: icon and label on the left (with an optional info tooltip), the
 * menu on the right, lined up with ConfigSwitch and ConfigSpinBox rows. See StyledComboBox.
 */
RowLayout {
    id: root
    property string text: ""
    property string icon
    property string tooltip: ""
    property alias options: comboBox.options
    property alias currentValue: comboBox.value
    property alias fallbackText: comboBox.fallbackText
    signal selected(var newValue)
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText { // Wraps like ConfigSpinBox's label
            id: labelWidget
            Layout.fillWidth: true
            Layout.preferredWidth: Math.ceil(labelMetrics.advanceWidth)
            Layout.maximumWidth: Math.ceil(labelMetrics.advanceWidth)
            wrapMode: Text.Wrap
            text: root.text
            color: Appearance.colors.colOnLayer1
            opacity: root.enabled ? 1 : 0.4
        }
        TextMetrics {
            id: labelMetrics
            font: labelWidget.font
            text: labelWidget.text
        }
        InfoTip {
            tip: root.tooltip
        }
        Item { Layout.fillWidth: true }
    }
    StyledComboBox {
        id: comboBox
        onSelected: newValue => root.selected(newValue)
    }
}
