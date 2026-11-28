import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The in-game overlay's performance: a card with a row each for the CPU and the GPU (UsageGraph: the value, its
// temperature and the session's average and peak, kept by the overlay, and a graph), then RAM and VRAM on a line
// of their own. The frame rate is on the game's art (GameBanner). The GPU is the one the game draws on (perf, from
// game_perf.py): on an integrated one, the game's share of it, and a warning when there's a faster one it isn't
// using. The top of the group the sound card closes
ColumnLayout {
    id: root
    property var cpuHistory: []
    property var gpuHistory: []
    property var cpuStats: null // { sum, count, peak } over the session
    property var gpuStats: null
    property var perf: ({}) // { gpu, integrated, busy, fps, fpsAvg, fpsLow }
    property bool onIntegrated: false // The game draws on an integrated GPU
    readonly property string integratedName: perf.gpu === "amd" ? Translation.tr("AMD graphics") : Translation.tr("Intel graphics")
    function detail(temp, stats) { // Its temperature, and the session's average and peak once there are two samples
        const parts = [];
        if (temp > 0) parts.push(Math.round(temp) + "°C");
        if ((stats?.count ?? 0) > 1)
            parts.push(Translation.tr("avg %1").arg(Math.round(stats.sum / stats.count * 100)), Translation.tr("peak %1").arg(Math.round(stats.peak * 100)));
        return parts.join("  ·  ");
    }
    readonly property bool vramShown: !onIntegrated && ResourceUsage.vramTotal > 0 && !ResourceUsage.gpuAsleep
    spacing: 4
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: rows.implicitHeight + 24
        topLeftRadius: Appearance.rounding.normal
        topRightRadius: Appearance.rounding.normal
        bottomLeftRadius: Appearance.rounding.joined
        bottomRightRadius: Appearance.rounding.joined
        color: Appearance.colors.colLayer3
        ColumnLayout {
            id: rows
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 12 }
            spacing: 8
            UsageGraph {
                Layout.fillWidth: true
                label: Translation.tr("CPU")
                valueText: Math.round(ResourceUsage.cpuUsage * 100) + "%"
                detail: root.detail(ResourceUsage.cpuTemp, root.cpuStats)
                history: root.cpuHistory
                warning: ResourceUsage.cpuUsage >= 0.9 || ResourceUsage.cpuTemp >= 90
            }
            UsageGraph {
                readonly property real usage: root.onIntegrated ? Math.max(0, root.perf.busy) : ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuUsage
                Layout.fillWidth: true
                visible: root.onIntegrated || ResourceUsage.gpuDetected
                label: Translation.tr("GPU")
                valueText: ResourceUsage.gpuAsleep && !root.onIntegrated ? Translation.tr("Off") : Math.round(usage * 100) + "%"
                detail: root.detail(root.onIntegrated || ResourceUsage.gpuAsleep ? 0 : ResourceUsage.gpuTemp, root.gpuStats)
                history: root.gpuHistory
                colour: Appearance.colors.colTertiary
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
    }
    Rectangle { // RAM and VRAM
        Layout.fillWidth: true
        implicitHeight: 32
        radius: Appearance.rounding.joined
        color: Appearance.colors.colLayer3
        StyledText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: Translation.tr("RAM %1 / %2 GB").arg((ResourceUsage.memoryUsed / 1048576).toFixed(1)).arg((ResourceUsage.memoryTotal / 1048576).toFixed(0))
                + (root.vramShown ? "   ·   " + Translation.tr("VRAM %1 / %2 GB").arg(ResourceUsage.vramUsed.toFixed(1)).arg(ResourceUsage.vramTotal.toFixed(0)) : "")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colSubtext
        }
    }
}
