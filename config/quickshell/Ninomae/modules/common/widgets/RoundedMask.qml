import QtQuick
import QtQuick.Effects

/**
 * Rounded-corner clip for `layer.effect`, on Qt 6's MultiEffect. Replaces the Qt5Compat pattern
 * `OpacityMask { maskSource: Rectangle { width; height; radius } }`. Like OpacityMask, the mask is
 * stretched over the layer, so maskWidth/maskHeight only matter when they differ from its size.
 */
MultiEffect {
    id: root
    property real radius: 0
    property real maskWidth: width
    property real maskHeight: height

    maskEnabled: true
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0 // Soft threshold keeps the antialiased edge
    maskSource: maskShape

    Rectangle {
        id: maskShape
        width: root.maskWidth
        height: root.maskHeight
        radius: root.radius
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
}
