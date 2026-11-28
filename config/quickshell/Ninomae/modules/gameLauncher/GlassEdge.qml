import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

/**
 * The edge of a picture on the launcher's glass (Captures' art strip, News' post picture), smooth over bright and
 * dark: a soft dark falloff just outside it (3 px, darkest at the edge), and light as glass catches it, brightest
 * along the top, round the top corners and down the sides, fading out by halfway, none along the bottom. Fill it over
 * the picture (anchors.fill) with the picture's radius
 */
Item {
    id: root
    property real radius: Appearance.rounding.normal

    Repeater { // The falloff
        model: 3
        Rectangle {
            required property int index
            anchors { fill: parent; margins: -(index + 1) }
            radius: root.radius + index + 1
            color: "transparent"
            border { width: 1; color: ColorUtils.transparentize("black", [0.72, 0.86, 0.94][index]) }
        }
    }
    Item { // The light round the top corners and along the top: a rim clipped to the corners' height
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.radius
        clip: true
        Rectangle {
            width: parent.width; height: root.height
            radius: root.radius
            color: "transparent"
            border { width: 1; color: ColorUtils.transparentize("white", 0.86) }
        }
    }
    EdgeLight { // Brightest in the middle of the top
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.radius; rightMargin: root.radius }
        strength: 0.2
    }
    Repeater { // Down the sides from the corners, fading out by halfway
        model: 2
        Rectangle {
            required property int index
            x: index === 0 ? 0 : root.width - 1
            y: root.radius
            width: 1; height: root.height / 2 - root.radius
            gradient: Gradient {
                GradientStop { position: 0; color: ColorUtils.transparentize("white", 0.86) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
