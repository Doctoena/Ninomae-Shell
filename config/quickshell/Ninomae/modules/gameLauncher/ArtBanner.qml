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
 * when it has one. For several games (Tags), moreCovers stack behind the cover and moreArts split the art on a
 * slant. What goes on it is the children: anchor them to coverItem.right (coverEnd with a stack).
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
    property bool showCover: true // Off: the panel puts its own thing there (Achievements: a progress ring)
    readonly property string hero: GameLauncherService.bannerArt(game)
    readonly property string sharp: art || hero
    readonly property string cover: GameLauncherService.localArt(game, "boxArt")
    readonly property string logo: showLogo ? GameLauncherService.logoArt(game) : ""
    readonly property bool logoShown: logo !== "" && logoImage.status === Image.Ready
    readonly property alias coverItem: coverBox
    // More covers (paths), stacked behind the cover and peeking out to its right, each a step smaller (the Tags
    // panel: the tag's other games). Text goes from coverEnd then, not coverItem.right
    property var moreCovers: []
    readonly property real coverStep: 24
    readonly property real coverEnd: coverBox.x + coverBox.width + moreCovers.length * coverStep
    // More banner art (paths): the background split on a slant, the game's art first, then each of these (the Tags
    // panel: up to three of the tag's games)
    property var moreArts: []
    readonly property int slices: 1 + moreArts.length
    readonly property real slant: 14 // Degrees from upright
    readonly property real _sin: Math.sin(slant * Math.PI / 180)
    readonly property real _cos: Math.cos(slant * Math.PI / 180)
    // Where slice k's edge crosses half height: the left half stays the game's own (the cover and the text are
    // there), the other slices share the right half
    function sliceEdge(k) { return k >= slices ? width : width * (0.5 + 0.5 * (k - 1) / (slices - 1)); }

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    // Stacked under what the panel puts on the banner (its children, at 0): the art, its slices and shade at -3, the
    // stack's wash -2, the stacked covers below -1, the cover -1
    Image { // Sharp art, else the cover blurred
        anchors.fill: parent
        z: -3
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
    // The other slices: each clipped to all that's right of its slanted edge, over the one before. A clip turned by
    // the slant, holding the art turned back, so the art sits upright where it would without the clip
    Repeater {
        model: root.moreArts
        Item {
            id: slice
            required property string modelData
            required property int index
            readonly property real mid: root.sliceEdge(index + 1)
            readonly property real end: root.sliceEdge(index + 2)
            readonly property real extra: root.height // The clip reaches this far past the top and bottom
            readonly property real x0: mid + (root.height / 2 + extra) * root._sin / root._cos
            x: x0; y: -extra
            z: -3
            width: root.width + root.height * 2; height: root.height * 3
            rotation: root.slant
            transformOrigin: Item.TopLeft
            clip: true
            // In once its art has loaded (the art under it shows till then), the edge with it
            opacity: sliceArt.status === Image.Ready ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Item { // Turned back: its children are in the banner's own coordinates
                x: -slice.x0 * root._cos + slice.extra * root._sin
                y: slice.x0 * root._sin + slice.extra * root._cos
                width: root.width; height: root.height
                rotation: -root.slant
                transformOrigin: Item.TopLeft
                Image {
                    id: sliceArt
                    // As wide as the banner, centred on the slice, so each shows the middle of its art
                    x: (slice.mid + slice.end) / 2 - root.width / 2
                    width: root.width; height: root.height
                    source: slice.modelData.startsWith("/") ? "file://" + slice.modelData : slice.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.ceil(root.width * Screen.devicePixelRatio / 256) * 256 // In steps, as the main art
                }
            }
            Rectangle { // A thin light line along the edge
                width: 2; height: parent.height
                color: Qt.rgba(1, 1, 1, 0.22)
            }
        }
    }
    Rectangle { // Shade for the text (the background colour can be translucent: made solid)
        id: shade
        anchors.fill: parent
        z: -3
        readonly property color base: Appearance.m3colors.m3background
        function at(a) { return Qt.rgba(base.r, base.g, base.b, a); }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: shade.at(0.9) }
            GradientStop { position: 0.5; color: shade.at(root.shadeMid) }
            GradientStop { position: 1.0; color: shade.at(root.shadeEnd) }
        }
    }
    Rectangle { // With a stack: a dark wash behind it, so the covers stand off the art
        visible: root.moreCovers.length > 0
        z: -2
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: root.coverEnd + 70
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: shade.at(0.75) }
            GradientStop { position: 0.6; color: shade.at(0.5) }
            GradientStop { position: 1.0; color: shade.at(0) }
        }
    }
    Repeater { // The stack behind the cover
        model: root.moreCovers
        ClippingRectangle {
            id: back
            required property string modelData
            required property int index
            readonly property real shrink: 1 - 0.08 * (index + 1)
            x: coverBox.x + coverBox.width - width + (index + 1) * root.coverStep // Its right edge a step past the one in front
            z: -1.1 - index * 0.1 // Under the cover, further back lower
            anchors.verticalCenter: coverBox.verticalCenter
            height: Math.round(coverBox.height * shrink)
            width: Math.round(coverBox.width * shrink)
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            Image {
                anchors.fill: parent
                source: back.modelData.startsWith("/") ? "file://" + back.modelData : back.modelData
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(126, 168) // As the cover's
            }
            Rectangle { // Further back, darker
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.12 * (back.index + 1))
            }
        }
    }
    ClippingRectangle {
        id: coverBox
        z: -1
        anchors { left: parent.left; leftMargin: (root.height < 100 ? 12 : 16) + root.coverInset; verticalCenter: parent.verticalCenter }
        // A logo keeps its own shape, up to 220 wide (its height comes first: most are wide)
        height: root.logoShown ? Math.min(96, root.height - 40) : Math.min(84, root.height - 24)
        width: root.logoShown ? Math.min(220, Math.round(height * logoImage.implicitWidth / Math.max(1, logoImage.implicitHeight)))
            : root.showCover ? Math.round(height * 3 / 4) : 0
        visible: root.showCover
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
            // Cropped to what shows (GameLauncherService.logoClip, in the file's own pixels: so no sourceSize;
            // logos are small), so it sits centred rather than its transparent canvas
            sourceClipRect: GameLauncherService.logoClip(root.logo)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
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
