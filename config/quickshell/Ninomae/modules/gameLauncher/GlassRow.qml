import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * A row (or tab, or tile) straight on a GlassWell: clear at rest, a soft card when pointed at, the accent squircle
 * while it's the one on. usable: false keeps it still (no card, no ripple, no hand) for a row that can't be used
 */
RippleButton {
    property bool on: false
    property bool usable: true
    padding: 0
    buttonRadius: 12
    pointingHandCursor: usable
    colBackground: on ? Appearance.colors.colLayer3Accent : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
    colBackgroundHover: !usable ? colBackground
        : on ? Appearance.colors.colLayer3AccentHover : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.93)
    colRipple: usable ? ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.85) : "transparent"
}
