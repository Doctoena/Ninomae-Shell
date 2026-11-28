import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with a few choices on the right. `option` and `options` as ConfigSelectionArray's.
 */
SettingRow {
    id: root
    property alias option: choices.option
    property alias options: choices.options
    ConfigSelectionArray {
        id: choices
        Layout.fillWidth: false
    }
}
