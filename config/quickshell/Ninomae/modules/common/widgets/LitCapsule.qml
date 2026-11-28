import qs.modules.common
import qs.modules.common.functions
import QtQuick

// A lit capsule (W3, the bar player's first): round ends, its colour strongest at the left end and fading out by its
// middle, a fine rim of it. The bar's parts (the player's in its cover's colour, the rest in the accent) and the battery
// drawer's state
Rectangle {
    id: capsule
    property color colour: Appearance.colors.colPrimary
    // How much of the colour: the accent is more vivid than a cover's colour, so the accent ones are at 0.75, as soft
    // as the player's glow at 1
    property real strength: 0.75
    radius: height / 2
    color: "transparent"
    border { width: 1; color: ColorUtils.transparentize(capsule.colour, 1 - 0.25 * capsule.strength) }
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ColorUtils.transparentize(capsule.colour, 1 - 0.28 * capsule.strength) }
            GradientStop { position: 0.55; color: ColorUtils.transparentize(capsule.colour, 1 - 0.08 * capsule.strength) }
            GradientStop { position: 1; color: ColorUtils.transparentize(capsule.colour, 1 - 0.05 * capsule.strength) }
        }
    }
}
