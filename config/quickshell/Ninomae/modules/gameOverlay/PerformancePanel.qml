import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The in-game overlay's Performance: a slim row each for the frame rate (from MangoHud's log, when the game runs
// with it), the CPU and the GPU, with their graphs and this session's average and peak or low (kept by the overlay),
// and RAM and VRAM in the title row. The GPU is the one the game draws on (perf, from game_perf.py): on an
// integrated one, the game's share of it, and a warning when there's a faster one it isn't using
ColumnLayout {
    id: root
    property var cpuHistory: []
    property var gpuHistory: []
    property var fpsHistory: []
    property var cpuStats: null // { sum, count, peak } over the session
    property var gpuStats: null
    property var perf: ({}) // { gpu, integrated, busy, fps, fpsAvg, fpsLow }
    property bool onIntegrated: false // The game draws on an integrated GPU
    readonly property string integratedName: perf.gpu === "amd" ? Translation.tr("AMD graphics") : Translation.tr("Intel graphics")
    readonly property bool hasFps: (perf.fps ?? -1) > 0
    function statsText(stats) { // The session's average and peak, once there are two samples
        return (stats?.count ?? 0) > 1 ? Translation.tr("avg %1%\npeak %2%").arg(Math.round(stats.sum / stats.count * 100)).arg(Math.round(stats.peak * 100)) : "";
    }
    readonly property bool vramShown: !onIntegrated && ResourceUsage.vramTotal > 0 && !ResourceUsage.gpuAsleep
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        OverlayPanelTitle { Layout.fillWidth: true; icon: "monitoring"; text: Translation.tr("Performance") }
        StyledText {
            text: Translation.tr("RAM %1 / %2 GB").arg((ResourceUsage.memoryUsed / 1048576).toFixed(1)).arg((ResourceUsage.memoryTotal / 1048576).toFixed(0))
                + (root.vramShown ? "  ·  " + Translation.tr("VRAM %1 / %2 GB").arg(ResourceUsage.vramUsed.toFixed(1)).arg(ResourceUsage.vramTotal.toFixed(0)) : "")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colSubtext
        }
    }
    UsageGraph { // The frame rate, the highest near the top of its graph
        Layout.fillWidth: true
        visible: root.hasFps
        label: Translation.tr("FPS")
        valueText: Math.round(root.perf.fps ?? 0)
        history: root.fpsHistory
        ceiling: Math.max(60, ...root.fpsHistory) * 1.1
        sideText: Translation.tr("avg %1\n1% low %2").arg(Math.round(root.perf.fpsAvg ?? 0)).arg(Math.round(root.perf.fpsLow ?? 0))
    }
    UsageGraph {
        Layout.fillWidth: true
        label: Translation.tr("CPU")
        valueText: Math.round(ResourceUsage.cpuUsage * 100) + "%"
        temp: ResourceUsage.cpuTemp
        history: root.cpuHistory
        sideText: root.statsText(root.cpuStats)
        warning: ResourceUsage.cpuUsage >= 0.9
    }
    UsageGraph {
        readonly property real usage: root.onIntegrated ? Math.max(0, root.perf.busy) : ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuUsage
        Layout.fillWidth: true
        visible: root.onIntegrated || ResourceUsage.gpuDetected
        label: Translation.tr("GPU")
        valueText: ResourceUsage.gpuAsleep && !root.onIntegrated ? Translation.tr("Off") : Math.round(usage * 100) + "%"
        temp: root.onIntegrated || ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuTemp
        history: root.gpuHistory
        sideText: root.statsText(root.gpuStats)
        warning: usage >= 0.95
    }
    RowLayout { // On the integrated GPU when there's a faster one
        Layout.fillWidth: true
        visible: root.onIntegrated && ResourceUsage.gpuDetected
        spacing: 8
        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: "warning"
            iconSize: 18
            color: Appearance.colors.colError
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("The game is running on the %1, not the %2, so it's slower than it could be.")
                .arg(root.integratedName).arg(ResourceUsage.gpuName || Translation.tr("faster GPU"))
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }
    }
}
