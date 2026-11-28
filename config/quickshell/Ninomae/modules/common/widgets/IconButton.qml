import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * A button with just an icon (the sidebar's system buttons, Do not disturb, Settings' Close): a squircle on the
 * cards' surface as the quick toggles, solid accent while `toggled`, `tip` on hover. `round: true` makes it a
 * circle (Settings' Close). `size` sets it, the icon scales with it.
 */
RippleButton {
    id: root
    property string symbol
    property string tip: ""
    property real size: 36
    property bool round: false
    implicitWidth: size
    implicitHeight: size
    buttonRadius: round ? size / 2 : size >= 36 ? Appearance.rounding.container : Appearance.rounding.segment
    colBackground: round ? Appearance.m3colors.m3surfaceContainerHigh : Appearance.colors.colLayer2
    colBackgroundHover: round ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.colors.colLayer2Hover
    colRipple: round ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.colors.colLayer2Active
    padding: 0
    contentItem: Item { // The button sizes this; the icon sits in its middle at its own size
        MaterialSymbol {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1 // The font's line box sits the glyph a pixel high
            text: root.symbol
            iconSize: Math.round(root.size * 0.275) * 2 // Even, so it centres on whole pixels
            fill: root.toggled ? 1 : 0
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        }
    }
    StyledToolTip {
        extraVisibleCondition: root.tip !== ""
        text: root.tip
    }
}
