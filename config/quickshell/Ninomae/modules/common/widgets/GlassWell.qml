import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * A well on the glass (the launcher's lists and grids, the sidebar's rings and notifications):
 * darker than the glass round it, set into it, outlined by a fine light rim all round (brighter in the middle of its
 * top), so it stands apart (a shadow didn't show on the dark glass, a lighter fill barely did). The same with Glass
 * panels off: then it's over a solid surface
 */
Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.4)
    border { width: 1; color: ColorUtils.transparentize("white", 0.9) }

    EdgeLight {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 24; rightMargin: 24 }
        strength: 0.22
    }
}
