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
    property real leftRadius: radius // One side's corners apart (a split button's)
    property real rightRadius: radius
    property real topRadius: -1 // Top and bottom apart instead (a settings row in its group); -1: as the sides
    property real bottomRadius: -1
    // Each corner apart (a piece at a corner of a joined group); -1: as above
    property real topLeftRadius: -1
    property real topRightRadius: -1
    property real bottomLeftRadius: -1
    property real bottomRightRadius: -1
    function _corner(own, edge, side) { return own >= 0 ? own : edge >= 0 ? edge : side; }
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
        topLeftRadius: root._corner(root.topLeftRadius, root.topRadius, root.leftRadius)
        bottomLeftRadius: root._corner(root.bottomLeftRadius, root.bottomRadius, root.leftRadius)
        topRightRadius: root._corner(root.topRightRadius, root.topRadius, root.rightRadius)
        bottomRightRadius: root._corner(root.bottomRightRadius, root.bottomRadius, root.rightRadius)
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
}
