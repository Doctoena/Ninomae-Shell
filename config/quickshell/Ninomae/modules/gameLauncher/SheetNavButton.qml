import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// The previous/next arrows at a sheet viewer's sides (screenshots, clips); faded out when there's none
RippleButton {
    id: nb
    property string iconName
    focusPolicy: Qt.NoFocus // The details page keeps the keys
    width: 44; height: 44; buttonRadius: Appearance.rounding.container; padding: 0
    opacity: enabled ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }
    colBackground: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.3)
    colBackgroundHover: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.1)
    colRipple: Appearance.colors.colLayer1Active
    contentItem: Item { MaterialSymbol { anchors.centerIn: parent; text: nb.iconName; iconSize: 24; color: Appearance.colors.colOnLayer0 } }
}
