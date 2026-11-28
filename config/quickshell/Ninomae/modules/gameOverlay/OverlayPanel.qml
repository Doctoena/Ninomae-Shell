import qs.modules.common
import QtQuick

// The in-game overlay's panel, as the sidebar: the base surface with its border and corners, neutral colLayer2
// groups inside. Clicks on it don't reach the backdrop (which closes the overlay)
Rectangle {
    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    MouseArea { anchors.fill: parent }
}
