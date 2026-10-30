import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * The crosshair, drawn from Config.options.crosshair (or `opts`, any object with the same fields): inner
 * lines, optional outer lines further out, a centre dot and a ring, each with its own opacity, and an
 * optional dark outline around each part. Plain rectangles on whole pixels, so it stays sharp at 1:1.
 * Used by the overlay (modules/crosshair) and the Settings preview. Its centre is the item's centre.
 */
Item {
    id: root
    property var opts: Config.options.crosshair

    readonly property color base: opts.color === "accent" ? Appearance.colors.colPrimary : opts.color
    readonly property int o: opts.outline ? Math.max(1, opts.outlineThickness) : 0
    function fill(pct) { return ColorUtils.transparentize(root.base, 1 - pct / 100); }
    // An outline as see-through as its part: a faint line doesn't get a solid frame
    function edge(pct) { return ColorUtils.transparentize("black", 1 - (opts.outlineOpacity / 100) * (pct / 100)); }

    // Lines as rectangles, `t` across, centred on the centre pixel(s), starting `gap` clear of them.
    // Horizontal ones `len` long, vertical ones `vlen`
    function cross(t, gap, len, vlen, pct) {
        const lo = c - Math.floor(t / 2), hi = lo + t;
        const out = [
            { x: hi + gap, y: lo, w: len, h: t, pct: pct },          // Right
            { x: lo - gap - len, y: lo, w: len, h: t, pct: pct },    // Left
            { x: lo, y: hi + gap, w: t, h: vlen, pct: pct }          // Bottom
        ];
        if (opts.topLine) out.push({ x: lo, y: lo - gap - vlen, w: t, h: vlen, pct: pct });
        return out;
    }
    readonly property int vlen: opts.verticalLength > 0 ? opts.verticalLength : opts.length
    readonly property var lineRects: [
        ...(opts.lines && opts.length > 0 ? cross(Math.max(1, opts.thickness), opts.gap, opts.length, vlen, opts.lineOpacity) : []),
        ...(opts.outerLines && opts.outerLength > 0 ? cross(Math.max(1, opts.outerThickness), opts.outerGap, opts.outerLength, opts.outerLength, opts.outerOpacity) : [])
    ]

    readonly property int ringR: Math.max(2, opts.circleRadius)
    readonly property int ringT: Math.max(1, opts.circleThickness)
    // From the centre to the furthest drawn pixel
    readonly property int extent: Math.max(opts.lines ? opts.gap + Math.max(opts.length, vlen) + Math.ceil(opts.thickness / 2) : 0,
                                           opts.outerLines ? opts.outerGap + opts.outerLength + Math.ceil(opts.outerThickness / 2) : 0,
                                           opts.circle ? ringR + 1 : 0,
                                           opts.dot ? Math.ceil(opts.dotSize / 2) : 0, 1) + o + 1
    readonly property int c: extent // The centre pixel
    implicitWidth: extent * 2 + 1
    implicitHeight: implicitWidth

    // Outlines frame each line (borders only, nothing under the fill), all under every fill
    Repeater {
        model: root.o > 0 ? root.lineRects : []
        Rectangle {
            required property var modelData
            x: modelData.x - root.o; y: modelData.y - root.o
            width: modelData.w + root.o * 2; height: modelData.h + root.o * 2
            color: "transparent"; border.width: root.o; border.color: root.edge(modelData.pct)
        }
    }
    Repeater {
        model: root.lineRects
        Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            color: root.fill(modelData.pct)
        }
    }

    // Ring: its outline on both sides of the stroke
    Item {
        visible: root.opts.circle
        readonly property int size: root.ringR * 2 + 1
        x: root.c - root.ringR; y: x
        width: size; height: size
        Rectangle { // Outer edge
            visible: root.o > 0
            anchors.centerIn: parent
            width: parent.size + root.o * 2; height: width; radius: width / 2
            color: "transparent"; border.width: root.o; border.color: root.edge(root.opts.circleOpacity)
        }
        Rectangle { // Inner edge
            visible: root.o > 0 && parent.size - root.ringT * 2 > 2
            anchors.centerIn: parent
            width: parent.size - root.ringT * 2; height: width; radius: width / 2
            color: "transparent"; border.width: root.o; border.color: root.edge(root.opts.circleOpacity)
        }
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: "transparent"; border.width: root.ringT; border.color: root.fill(root.opts.circleOpacity)
        }
    }

    // Centre dot: square while small (crisper), round from 4 px
    Rectangle {
        visible: root.opts.dot
        readonly property int d: Math.max(1, root.opts.dotSize)
        x: root.c - Math.floor(d / 2) - root.o; y: x
        width: d + root.o * 2; height: width
        radius: d >= 4 ? width / 2 : 0
        color: "transparent"; border.width: root.o; border.color: root.edge(root.opts.dotOpacity)
        Rectangle {
            x: root.o; y: root.o; width: parent.d; height: parent.d
            radius: parent.d >= 4 ? width / 2 : 0
            color: root.fill(root.opts.dotOpacity)
        }
    }
}
