import qs.modules.common
import QtQuick
Canvas { // Visualizer
    id: root
    property var points: [] // Plain JS arrays: a list<> property is converted on every write, ~60 times a second
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property bool live: true
    property color color: Appearance.colors.colPrimary
    readonly property string _fillRgba: `rgba(${Math.round(color.r * 255)},${Math.round(color.g * 255)},${Math.round(color.b * 255)},0.15)`
    onPointsChanged: if (root.live || !root._flat) root.requestPaint() // Paused: one flat frame, then nothing
    onLiveChanged: root.requestPaint()
    property bool _flat: false
    anchors.fill: parent
    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const points = root.points;
        const maxVal = root.maxVisualizerValue || 1;
        const h = height;
        const w = width;
        const n = points.length;
        root._flat = !root.live;
        if (n < 2 || !root.live) return; // Not playing: no wave
        // Smoothing: simple moving average (optional)
        const smoothWindow = root.smoothing; // adjust for more/less smoothing
        const smoothPoints = new Array(n);
        for (let i = 0; i < n; ++i) {
            let sum = 0, count = 0;
            for (let j = -smoothWindow; j <= smoothWindow; ++j) {
                const idx = Math.max(0, Math.min(n - 1, i + j));
                sum += points[idx];
                count++;
            }
            smoothPoints[i] = sum / count;
        }
        // A smooth curve through the points (each segment bends toward the midpoint of the next), so
        // the wave is soft without the blur layer it used to have: blurring the canvas every frame
        // while music played was GPU work in the same family as the drawer layer that hung the iGPU
        const px = i => i * w / (n - 1);
        const py = i => h - (smoothPoints[i] / maxVal) * h;
        ctx.beginPath();
        ctx.moveTo(0, h);
        ctx.lineTo(px(0), py(0));
        for (let i = 1; i < n - 1; ++i)
            ctx.quadraticCurveTo(px(i), py(i), (px(i) + px(i + 1)) / 2, (py(i) + py(i + 1)) / 2);
        ctx.lineTo(px(n - 1), py(n - 1));
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fillStyle = root._fillRgba;
        ctx.fill();
    }
}