import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick

/**
 * The colours a player takes from its cover (the bar's player, the media drawer): the cover's most vivid colour
 * (IconColours), and from it a light accent, the text on that accent, a soft line colour and surfaces mixed
 * towards it. A cover with no colour of its own (black and white, grey) or none leaves everything as the shell's
 * own: neutral surfaces and the accent, not surfaces washed in the accent.
 */
QtObject {
    id: root
    property string cover: "" // The cover's file
    onCoverChanged: IconColours.request(cover)
    Component.onCompleted: IconColours.request(cover)

    readonly property bool vivid: IconColours.hasColour(cover)
    readonly property color source: vivid ? IconColours.colourFor(cover) : Appearance.colors.colPrimary
    readonly property real hue: Math.max(0, source.hslHue)
    readonly property real saturation: Math.min(source.hslSaturation, 0.85)
    // Light, for buttons and fills on dark
    readonly property color accent: vivid ? Qt.hsla(hue, saturation, 0.8, 1) : Appearance.colors.colPrimary
    readonly property color onAccent: vivid ? Qt.hsla(hue, saturation, 0.14, 1) : Appearance.colors.colOnPrimary
    readonly property color subtext: vivid ? Qt.hsla(hue, Math.min(saturation, 0.3), 0.8, 1) : Appearance.colors.colSubtext
    // A surface leaning towards the cover (`amount` of its colour in `base`), or just `base` without one
    function surface(base, amount) { return vivid ? ColorUtils.mix(base, root.source, 1 - amount) : base; }
}
