import qs.modules.common
import qs.modules.common.widgets
import QtQuick
RippleButton {
    id: root
    property bool active: false
    // A row in a QuickDialogGroup card: no fill of its own (the row's icon squircle shows which one
    // is active), a light tint on hover
    horizontalPadding: 10
    verticalPadding: 8
    clip: true
    pointingHandCursor: !active
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    colBackground: "transparent"
    colBackgroundHover: active ? colBackground : Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    buttonRadius: Appearance.rounding.normal - 4 // Nested inside the group card's rounding
    Behavior on colBackground {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
}
