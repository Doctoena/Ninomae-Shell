import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * A bar shape to pick (Settings → Bar & dock, the welcome window), drawn on a little screen the way it'd look in
 * the chosen position. `shape` is bar.cornerStyle: 0 Hug, 1 Float, 2 Square.
 */
PreviewTile {
    id: tile
    required property int shape
    readonly property var bar: Config.options.bar
    readonly property real barHeight: Math.max(12, Math.round(width * 0.055)) // Scales with the tile
    readonly property real curve: Math.round(barHeight * 1.7) // Hug's corner curves, a bit bigger than life so they read
    chosen: bar.cornerStyle === shape
    onClicked: Config.set("bar.cornerStyle", shape)
    Rectangle { // The bar
        id: miniBar
        readonly property real inset: tile.shape === 1 ? Math.round(tile.barHeight * 0.45) : 0
        width: parent.width - inset * 2
        height: tile.barHeight
        x: (parent.width - width) / 2
        y: tile.bar.bottom ? parent.height - height - inset : inset
        radius: tile.shape === 1 ? height / 2 : 0
        color: Appearance.colors.colLayer0
        Row { // Workspaces on the left, status dots on the right
            readonly property real dot: Math.round(tile.barHeight * 0.4)
            anchors { left: parent.left; leftMargin: tile.barHeight * 0.6; verticalCenter: parent.verticalCenter }
            spacing: dot * 0.6
            Rectangle { width: parent.dot * 3; height: parent.dot; radius: height / 2; color: Appearance.colors.colPrimary }
            Repeater { model: 3; Rectangle { width: parent.dot; height: parent.dot; radius: height / 2; color: Appearance.colors.colSubtext } }
        }
        Row {
            readonly property real dot: Math.round(tile.barHeight * 0.4)
            anchors { right: parent.right; rightMargin: tile.barHeight * 0.6; verticalCenter: parent.verticalCenter }
            spacing: dot * 0.6
            Repeater { model: 3; Rectangle { width: parent.dot; height: parent.dot; radius: height / 2; color: Appearance.colors.colOnLayer0; opacity: 0.6 } }
        }
    }
    // Hug: the bar's corners curve into the screen
    RoundCorner {
        visible: tile.shape === 0
        implicitSize: tile.curve
        color: Appearance.colors.colLayer0
        corner: tile.bar.bottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft
        x: miniBar.x
        y: tile.bar.bottom ? miniBar.y - implicitSize : miniBar.y + miniBar.height
    }
    RoundCorner {
        visible: tile.shape === 0
        implicitSize: tile.curve
        color: Appearance.colors.colLayer0
        corner: tile.bar.bottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight
        x: miniBar.x + miniBar.width - implicitSize
        y: tile.bar.bottom ? miniBar.y - implicitSize : miniBar.y + miniBar.height
    }
}
