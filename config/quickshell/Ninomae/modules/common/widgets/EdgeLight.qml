import qs.modules.common.functions
import QtQuick

/**
 * Glass's fine light along the top of a piece: 1 px, brightest in the middle, fading out toward the ends. Place it
 * with anchors (left, right and top, with margins for where it fades in); strength is how bright its middle is (0–1)
 */
Rectangle {
    id: root
    property real strength: 0.3
    height: 1
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.5; color: ColorUtils.transparentize("white", 1 - root.strength) }
        GradientStop { position: 1; color: "transparent" }
    }
}
