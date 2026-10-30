import qs.modules.common
import QtQuick
import QtQuick.Controls
/**
 * Material 3 switch. See https://m3.material.io/components/switch/overview
 */
Switch {
    id: root
    property real sizeScale: 0.6 // Default in m3 spec is huge af
    implicitHeight: 32 * root.sizeScale
    implicitWidth: 52 * root.sizeScale
    property color activeColor: Appearance?.colors.colPrimary ?? "#685496"
    property color inactiveColor: Appearance?.colors.colSurfaceContainerHighest ?? "#45464F"
    PointingHandInteraction {}
    // Custom track styling
    background: Rectangle {
        width: parent.width
        height: parent.height
        radius: Appearance?.rounding.full ?? 9999
        color: root.checked ? root.activeColor : root.inactiveColor
        border.width: 2 * root.sizeScale
        border.color: root.checked ? root.activeColor : Appearance.colors.colOutline
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
    // Custom thumb styling
    indicator: Rectangle {
        width: (root.pressed || root.down) ? (28 * root.sizeScale) : root.checked ? (24 * root.sizeScale) : (16 * root.sizeScale)
        height: (root.pressed || root.down) ? (28 * root.sizeScale) : root.checked ? (24 * root.sizeScale) : (16 * root.sizeScale)
        radius: Appearance.rounding.full
        color: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOutline
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.checked ? ((root.pressed || root.down) ? (22 * root.sizeScale) : 24 * root.sizeScale) : ((root.pressed || root.down) ? (2 * root.sizeScale) : 8 * root.sizeScale)
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
