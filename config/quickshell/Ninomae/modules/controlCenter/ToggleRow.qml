import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A setting with an on/off switch: squircle icon (accent when on), title and a line under it
RowLayout {
    id: row
    property string icon
    property string title
    property string detail: ""
    property bool checked: false
    property string tip: "" // Shown while the pointer is over the row
    signal toggled(bool checked)
    Layout.fillWidth: true
    spacing: 12
    HoverHandler { id: rowHover }
    StyledToolTip {
        text: row.tip
        visible: row.tip !== "" && rowHover.hovered
    }
    QuickDialogIcon { icon: row.icon; active: row.checked }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        StyledText {
            Layout.fillWidth: true
            text: row.title
            font.weight: Font.Medium
            color: row.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: row.detail
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }
    StyledSwitch {
        checked: row.checked
        onClicked: row.toggled(checked)
    }
}
