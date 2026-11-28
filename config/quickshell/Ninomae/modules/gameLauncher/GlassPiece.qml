import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * A glass piece on a picture (the launcher panels' banners): a rounded holder of see-through glass with a fine edge,
 * holding a row of segments or buttons 4 px in, led by a squircle saying what it is when leadIcon is set (News'
 * newspaper, Achievements' trophy). With nothing in it shown it's 0 wide, which a Row skips, and clear (not hidden:
 * what's in it would then count as hidden too, and it'd never come back)
 */
Rectangle {
    id: root
    default property alias content: row.data
    property string leadIcon: ""
    property alias spacing: row.spacing
    width: row.implicitWidth > 0 ? row.implicitWidth + 8 : 0
    height: 36
    opacity: width > 0 ? 1 : 0
    radius: Appearance.rounding.segment + 4 // Concentric with what's 4 px inside it
    color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.4) // As LauncherTopPanel.glassOverArt
    border { width: 1; color: ColorUtils.transparentize("white", 0.92) }

    Row {
        id: row
        x: 4; anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Rectangle {
            visible: root.leadIcon !== ""
            width: 28; height: 28
            radius: Appearance.rounding.segment
            color: ColorUtils.transparentize("white", 0.92)
            MaterialSymbol { anchors.centerIn: parent; text: root.leadIcon; iconSize: 18; color: Appearance.colors.colOnLayer0 }
        }
    }
}
