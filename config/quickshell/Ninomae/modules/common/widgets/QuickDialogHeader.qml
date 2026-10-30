import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Header of the sidebar's quick-setting dialogs (Wi-Fi, Bluetooth, sound, mic), styled like the quick
 * toggles: the accent squircle with the icon, the title, a status line under it, and optionally the
 * on/off switch for the whole thing.
 */
RowLayout {
    id: root
    property string icon
    property string title
    property string subtitle: ""
    property bool showSwitch: false
    property bool checked: false
    signal switchToggled(bool checked)

    Layout.fillWidth: true
    spacing: 12

    Rectangle {
        implicitWidth: 40
        implicitHeight: 40
        radius: 13
        color: root.showSwitch && !root.checked ? Appearance.colors.colLayer3 : Appearance.colors.colPrimary
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 22
            fill: 1
            color: root.showSwitch && !root.checked ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.subtitle
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }
    StyledSwitch {
        visible: root.showSwitch
        checked: root.checked
        onClicked: root.switchToggled(checked)
    }
}
