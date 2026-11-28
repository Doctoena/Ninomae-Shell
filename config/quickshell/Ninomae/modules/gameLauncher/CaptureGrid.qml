import qs.modules.common
import QtQuick

/**
 * The Captures grid, the same on the Screenshots and Clips pages: 16:9 cells four across, joined (a 3 px gap
 * after each tile, right and bottom, the block rounded only at its outer corners: corner()), and `pad` of room
 * all round. The last tile (how to take more) reaches across the rest of its row (spanOf). Each page gives the
 * model and the delegate (a cell: width cellWidth, height cellHeight, its tile tileWidth(index) wide and
 * cellHeight - gap high, its corners from corner(index, which)). Its edges fade while there's more to scroll to.
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
    // Faded to whatever's behind it (the well), not to a colour: only while it can scroll, no layer otherwise
    layer.enabled: !(atYBeginning && atYEnd)
    layer.effect: ScrollFadeMask { topActive: !grid.atYBeginning; bottomActive: !grid.atYEnd }

    // The last tile spans the rest of its row
    function spanOf(index) { return index === count - 1 ? columns - index % columns : 1; }
    function tileWidth(index) { return cellWidth * spanOf(index) - gap; }

    // A tile's corner ("tl", "tr", "bl", "br"): rounded where it's a corner of the whole block, else joined (the
    // last tile spanning its row, every row is full)
    function corner(index, which) {
        const n = count, cols = columns;
        const lastRow = Math.floor((n - 1) / cols) * cols;
        const outer = which === "tl" ? index === 0
            : which === "tr" ? index === Math.min(cols, n) - 1 || (index === n - 1 && index < cols)
            : which === "bl" ? index === lastRow
            : index === n - 1;
        return outer ? Appearance.rounding.small : Appearance.rounding.joined;
    }
}
