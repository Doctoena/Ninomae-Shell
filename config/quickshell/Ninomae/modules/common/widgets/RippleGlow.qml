import QtQuick
import QtQuick.Shapes

/**
 * Soft click-ripple disc for the ripple buttons, drawn with a native Shapes gradient
 * (replaces the Qt5Compat RadialGradient, whose stop positions run 0..1 over a full width,
 * so 0.5 is the edge). Solid to 60% of the radius, clear at the edge.
 */
Shape {
    id: root
    property color color
    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: root.width / 2
            centerY: root.height / 2
            centerRadius: root.width // Stop 1.0 is a full width out, as in the old effect
            focalX: centerX
            focalY: centerY
            GradientStop { position: 0.0; color: root.color }
            GradientStop { position: 0.3; color: root.color }
            GradientStop { position: 0.5; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
        }
        PathRectangle { width: root.width; height: root.height }
    }
}
