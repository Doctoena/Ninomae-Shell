import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes

/**
 * A soft round glow behind something, in its colour (the app search's chosen result, the sidebar's cards, the
 * password prompt). Centred on centreX / centreY (the parent's coordinates); gone by `reach`, so keep that within
 * the distance to a clipping card's edge, or it shows as a straight cut. No layer: a radial gradient on a Shape.
 */
Shape {
    id: root
    property color colour
    property real strength: 0.4 // How opaque it is in the middle
    property real reach: 40
    property real centreX: 0
    property real centreY: 0
    x: centreX - reach
    y: centreY - reach
    width: reach * 2
    height: reach * 2
    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: root.reach; centerY: root.reach
            focalX: centerX; focalY: centerY
            centerRadius: root.reach
            GradientStop { position: 0.0; color: ColorUtils.transparentize(root.colour, 1 - root.strength) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        PathRectangle { width: root.width; height: root.height }
    }
}
