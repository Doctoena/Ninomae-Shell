import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
RippleButton {
    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    implicitWidth: implicitHeight - topInset - bottomInset
    buttonRadius: Appearance.rounding.normal
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
    background.implicitHeight: 50
}
