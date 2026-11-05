import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

/**
 * A banner of a game's art, for the launcher's panels (Downloads, Achievements, Stats, News): art when given (a
 * news post's picture), else the details page's banner art, else the cover blurred, shaded for text (darkest on
 * the left), with the cover on the left (coverIcon stands in without one), or with showLogo, the game's logo
 * when it has one. What goes on it is the children: anchor them to coverItem.right.
 */
ClippingRectangle {
    id: root
    property var game: null
    property string coverIcon: "sports_esports"
    property real shadeMid: 0.78 // The shade's opacity in the middle and at the right edge
    property real shadeEnd: 0.6
    property bool showLogo: false // The game's logo in the cover's place (News), when it has one
    property real coverInset: 0 // Room left of the cover, for something of the panel's own (the stats page's back button)
    property string art: "" // A picture of its own (a URL or path), over the game's art
    readonly property string hero: GameLauncherService.bannerArt(game)
    readonly property string sharp: art || hero
    readonly property string cover: GameLauncherService.localArt(game, "boxArt")
    readonly property string logo: showLogo ? GameLauncherService.logoArt(game) : ""
    readonly property bool logoShown: logo !== "" && logoImage.status === Image.Ready
    readonly property alias coverItem: coverBox

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    Image { // Sharp art, else the cover blurred
        anchors.fill: parent
        source: root.sharp || root.cover
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // In steps, as the game page's banner: a decode size following the width exactly decodes it again as
        // the panel resizes, which flickers
        sourceSize.width: root.sharp ? Math.ceil(root.width * Screen.devicePixelRatio / 256) * 256 : 240
        visible: status === Image.Ready
        layer.enabled: visible && !root.sharp
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
        anchors { left: parent.left; leftMargin: (root.height < 100 ? 12 : 16) + root.coverInset; verticalCenter: parent.verticalCenter }
        // A logo keeps its own shape, up to 220 wide (its height comes first: most are wide)
        height: root.logoShown ? Math.min(96, root.height - 40) : Math.min(84, root.height - 24)
        width: root.logoShown ? Math.min(220, Math.round(height * logoImage.implicitWidth / Math.max(1, logoImage.implicitHeight)))
            : Math.round(height * 3 / 4)
        radius: Appearance.rounding.small
        color: root.logoShown ? "transparent" : Appearance.colors.colLayer2
        Image {
            anchors.fill: parent
            visible: !root.logoShown
            source: root.cover
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(126, 168)
        }
        Image {
            id: logoImage
            anchors.fill: parent
            visible: root.logoShown
            source: root.logo
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.height: 192 // Fixed: twice the most it's shown at
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.cover === "" && !root.logoShown
            text: root.coverIcon
            iconSize: 24; fill: 1
            color: Appearance.colors.colPrimary
        }
    }
}
