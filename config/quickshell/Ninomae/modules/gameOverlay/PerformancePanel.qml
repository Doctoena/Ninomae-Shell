import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The in-game overlay's Performance: live CPU and GPU graphs with this session's average and peak (kept by the
// overlay), RAM and VRAM
OverlayPanel {
    id: root
    property var cpuHistory: []
    property var gpuHistory: []
    property var cpuStats: null // { sum, count, peak } over the session
    property var gpuStats: null
    function gb(kb) { return (kb / 1048576).toFixed(1) + " GB"; }
    implicitHeight: column.implicitHeight + 28
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10
        OverlayPanelTitle { icon: "monitoring"; text: Translation.tr("Performance") }
        UsageGraph {
            label: Translation.tr("CPU")
            usage: ResourceUsage.cpuUsage
            temp: ResourceUsage.cpuTemp
            history: root.cpuHistory
            stats: root.cpuStats
            warning: ResourceUsage.cpuUsage >= 0.9
        }
        UsageGraph {
            visible: ResourceUsage.gpuDetected
            label: ResourceUsage.gpuAsleep ? Translation.tr("GPU · asleep") : Translation.tr("GPU")
            usage: ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuUsage
            temp: ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuTemp
            history: root.gpuHistory
            stats: root.gpuStats
            warning: !ResourceUsage.gpuAsleep && ResourceUsage.gpuUsage >= 0.95
        }
        StyledText {
            text: Translation.tr("RAM %1 of %2").arg(root.gb(ResourceUsage.memoryUsed)).arg(root.gb(ResourceUsage.memoryTotal))
                + (ResourceUsage.vramTotal > 0 && !ResourceUsage.gpuAsleep
                    ? "  ·  " + Translation.tr("VRAM %1 of %2 GB").arg(ResourceUsage.vramUsed.toFixed(1)).arg(ResourceUsage.vramTotal.toFixed(0)) : "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colSubtext
        }
    }
}
