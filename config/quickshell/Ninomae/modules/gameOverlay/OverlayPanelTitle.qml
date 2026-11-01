import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A card's title on the in-game overlay: its icon in the accent, then its name
RowLayout {
    id: root
    property string icon
    property string text
    spacing: 8
    MaterialSymbol { text: root.icon; iconSize: 18; color: Appearance.colors.colPrimary }
    StyledText { Layout.fillWidth: true; text: root.text; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
}
