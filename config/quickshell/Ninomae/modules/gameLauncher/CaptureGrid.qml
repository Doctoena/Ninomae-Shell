import QtQuick

/**
 * The Captures grid, the same on the Screenshots and Clips pages: 16:9 cells four across, a gap after each
 * tile (right and bottom), and `pad` of room all round so the clip doesn't cut the edge tiles' hover ring.
 * Each page gives the model and the delegate (a cell: width cellWidth, height cellHeight, its tile inset
 * by gap on the right and bottom).
 */
GridView {
    readonly property int pad: 4
    readonly property int gap: 8
    readonly property int columns: 4
    topMargin: pad
    bottomMargin: 16
    leftMargin: pad
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cellWidth: Math.floor((width - pad * 2) / columns)
    cellHeight: Math.round((cellWidth - gap) * 9 / 16) + gap
}
