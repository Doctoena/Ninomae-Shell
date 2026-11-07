import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with a dropdown: a card of its own, the name and the line about it on the left, the menu on the
 * right. `description` (or else `tooltip`) is the line under the name. See StyledComboBox.
 */
SettingRow {
    id: root
    property alias options: comboBox.options
    property alias currentValue: comboBox.value
    property alias fallbackText: comboBox.fallbackText
    signal selected(var newValue)
    StyledComboBox {
        id: comboBox
        Layout.fillWidth: false
        onSelected: newValue => root.selected(newValue)
    }
}
