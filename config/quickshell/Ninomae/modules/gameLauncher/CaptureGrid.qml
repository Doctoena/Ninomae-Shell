import qs.modules.common
import QtQuick

/**
 * The Captures grid, the same on the Screenshots and Clips pages: 16:9 cells four across, joined (a 3 px gap
 * after each tile, right and bottom, the block rounded only at its outer corners: corner()), and `pad` of room
 * all round. Each page gives the model and the delegate (a cell: width cellWidth, height cellHeight, its tile
 * inset by gap on the right and bottom, its corners from corner(index, which)).
 */
GridView {
    id: grid
    readonly property int pad: 4
    readonly property int gap: 3
    readonly property int columns: 4
    topMargin: pad
    bottomMargin: 16
    leftMargin: pad
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cellWidth: Math.floor((width - pad * 2) / columns)
    cellHeight: Math.round((cellWidth - gap) * 9 / 16) + gap

    // A tile's corner ("tl", "tr", "bl", "br"): rounded where it's a corner of the whole block, else joined. A
    // short last row leaves the row above it a bottom-right corner too
    function corner(index, which) {
        const n = count, cols = columns;
        const lastRow = Math.floor((n - 1) / cols) * cols;
        const outer = which === "tl" ? index === 0
            : which === "tr" ? index === Math.min(cols, n) - 1
            : which === "bl" ? index === lastRow
            : index === n - 1 || (n % cols !== 0 && index === lastRow - 1);
        return outer ? Appearance.rounding.small : Appearance.rounding.joined;
    }
}
