import qs.modules.common
import qs.modules.common.functions
import QtQuick

// B2: what lifts a soft-card button off the glass: a fine light rim, a touch brighter while it's pointed at (no top
// light: it looked off on buttons). Laid over the button (RippleButtonWithIcon, StyledComboBox, NumberField, DialogButton)
Rectangle {
    id: root
    property bool hovered: false
    property real leftRadius: radius // Joined buttons: their own corners each side
    property real rightRadius: radius
    anchors.fill: parent
    topLeftRadius: leftRadius; bottomLeftRadius: leftRadius
    topRightRadius: rightRadius; bottomRightRadius: rightRadius
    color: "transparent"
    border { width: 1; color: ColorUtils.transparentize("white", root.hovered ? 0.84 : 0.9) }
}
