import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A card on the in-game overlay, as the shell's popups: the base surface with its border, neutral colLayer2
// groups inside. Clicks on it don't reach the backdrop (which closes the overlay)
Rectangle {
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    MouseArea { anchors.fill: parent }
}
