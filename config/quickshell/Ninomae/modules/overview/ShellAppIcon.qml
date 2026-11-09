import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The icon for the shell's own entries in app search (Ninomae Settings, Volume control): a dark squircle with
 * a filled symbol in the accent. Used by the result row (32 px) and the preview (88 px), so they match.
 */
Rectangle {
    id: root
    property string symbol: "settings"
    property real size: 32
    implicitWidth: size
    implicitHeight: size
    radius: size * 0.28
    color: Appearance.colors.colLayer4
    border.width: Math.max(1, size / 48)
    border.color: Qt.rgba(1, 1, 1, 0.06)
    MaterialSymbol { // Fills the tile, centred both ways at a whole-pixel size (19.2 px sat 1 px high)
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.symbol
        iconSize: Math.round(root.size * 0.6)
        fill: 1
        color: Appearance.colors.colPrimary
    }
}
