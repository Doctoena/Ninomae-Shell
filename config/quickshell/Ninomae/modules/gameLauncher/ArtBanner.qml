import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

/**
 * A banner of a game's art, for the launcher's panels (Downloads, Achievements): the details page's
 * banner art, else the cover blurred, shaded for text (darkest on the left), with the cover on the left
 * (coverIcon stands in without one). What goes on it is the children: anchor them to coverItem.right.
 */
ClippingRectangle {
    id: root
    property var game: null
    property string coverIcon: "sports_esports"
    property real shadeMid: 0.78 // The shade's opacity in the middle and at the right edge
    property real shadeEnd: 0.6
    readonly property string hero: GameLauncherService.bannerArt(game)
    readonly property string cover: GameLauncherService.localArt(game, "boxArt")
    readonly property alias coverItem: coverBox

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    Image { // Sharp hero art, else the cover blurred
        anchors.fill: parent
        source: root.hero || root.cover
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.hero ? Math.ceil(root.width * Screen.devicePixelRatio) : 240
        visible: status === Image.Ready
        layer.enabled: visible && !root.hero
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32; saturation: 0.35 }
    }
    Rectangle { // Shade for the text (the background colour can be translucent: made solid)
        id: shade
        anchors.fill: parent
        readonly property color base: Appearance.m3colors.m3background
        function at(a) { return Qt.rgba(base.r, base.g, base.b, a); }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: shade.at(0.9) }
            GradientStop { position: 0.5; color: shade.at(root.shadeMid) }
            GradientStop { position: 1.0; color: shade.at(root.shadeEnd) }
        }
    }
    ClippingRectangle {
        id: coverBox
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        height: Math.min(84, root.height - 28); width: Math.round(height * 3 / 4)
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        Image {
            anchors.fill: parent
            source: root.cover
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(126, 168)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.cover === ""
            text: root.coverIcon
            iconSize: 24; fill: 1
            color: Appearance.colors.colPrimary
        }
    }
}
