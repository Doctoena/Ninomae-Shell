import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A settings row: icon, label and an optional (i) on the left, then whatever you put inside on the right,
 * lined up with ConfigSwitch and ConfigSpinBox rows.
 *   SettingRow { icon: "folder"; text: "Folder"; StyledTextArea { … } }
 */
RowLayout {
    id: root
    property string text: ""
    property string icon
    property string tooltip: ""
    property color labelColor: Appearance.colors.colOnLayer1
    property color iconColor: Appearance.colors.colOnSurfaceVariant // As ConfigSwitch's icons
    default property alias controls: controlRow.data
    spacing: 10
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    OptionalMaterialSymbol {
        icon: root.icon
        iconSize: Appearance.font.pixelSize.larger
        color: root.iconColor
        opacity: root.enabled ? 1 : 0.4
    }
    StyledText {
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.labelColor
        opacity: root.enabled ? 1 : 0.4
    }
    InfoTip {
        tip: root.tooltip
    }
    Item { Layout.fillWidth: true }
    RowLayout {
        id: controlRow
        spacing: 8
    }
}
