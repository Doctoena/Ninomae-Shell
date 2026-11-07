import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings row: a card of its own, the name and the line about it on the left, whatever you put inside on
 * the right. `description` (or else `tooltip`) is the line under the name.
 *   SettingRow { text: "Folder"; description: "Where clips are saved"; StyledTextArea { … } }
 */
SettingsCard {
    id: root
    property string text: ""
    property string tooltip: ""
    property string description: ""
    property color labelColor: Appearance.colors.colOnLayer1
    default property alias controls: controlRow.data
    leftPadding: 16
    rightPadding: 14
    verticalPadding: 12
    minHeight: 52
    content: RowLayout {
        Layout.fillWidth: true
        spacing: 14
        RowText {
            opacity: root.enabled ? 1 : 0.4
            text: root.text
            description: root.description !== "" ? root.description : root.tooltip
            color: root.labelColor
        }
        RowLayout {
            id: controlRow
            Layout.fillWidth: false
            spacing: 8
        }
    }
}
