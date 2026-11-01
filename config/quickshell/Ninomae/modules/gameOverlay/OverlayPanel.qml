import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A card on the in-game overlay: solid, whatever the bar's transparency. Clicks on it don't reach the backdrop
// (which closes the overlay)
Rectangle {
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerLow
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    MouseArea { anchors.fill: parent }
}
