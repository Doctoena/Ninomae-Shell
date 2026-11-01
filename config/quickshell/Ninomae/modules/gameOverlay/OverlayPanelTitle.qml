import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A card's title on the in-game overlay: its icon on an accent squircle (as the shell's stat cards), its name
RowLayout {
    id: root
    property string icon
    property string text
    spacing: 10
    QuickDialogIcon { icon: root.icon; active: true; implicitWidth: 30; implicitHeight: 30; radius: Appearance.rounding.segment }
    StyledText { Layout.fillWidth: true; text: root.text; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
}
