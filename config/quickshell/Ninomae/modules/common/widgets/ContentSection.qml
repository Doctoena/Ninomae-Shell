import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A group of settings: its name small above, then its rows, each a card of its own (ConfigSwitch, SettingRow…,
 * or SettingsCard for anything else). `toggleOption: "crosshair.dot"` puts the group's on/off switch beside its
 * name and hides the rows while it's off.
 */
ColumnLayout {
    id: root
    property string title
    property string toggleOption: ""
    readonly property bool toggledOn: toggleOption === "" || !!Config.get(toggleOption)
    default property alias contentData: sectionContent.data
    Layout.fillWidth: true
    Layout.topMargin: 4
    spacing: 8
    RowLayout {
        visible: root.title.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
        }
        StyledSwitch {
            visible: root.toggleOption !== ""
            sizeScale: 0.6
            checked: root.toggledOn
            onClicked: Config.set(root.toggleOption, checked)
        }
    }
    ColumnLayout {
        id: sectionContent
        visible: root.toggledOn // Switched off from the name: just the name
        Layout.fillWidth: true
        spacing: 4
    }
}
