import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
// Three tiles styled like the quick toggles, usage as a ring around each icon. Clicking one selects it
// and opens a panel underneath with just that component: name and temperature, a usage graph of the
// last couple of minutes, and a few stats. Clicking it again (or the panel) closes it
Item {
    id: root
    property string selected: "" // "", "ram", "cpu" or "gpu"
    readonly property bool open: selected !== ""
    implicitHeight: tileRow.implicitHeight + (open ? 6 + detail.implicitHeight : 0)
    clip: true
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // Keep ResourceUsage polling only while the sidebar is open
    readonly property bool _watching: GlobalStates.sidebarRightOpen
    on_WatchingChanged: {
        ResourceUsage.watchers += _watching ? 1 : -1;
        if (_watching) foldTimer.stop(); else foldTimer.restart();
    }
    Timer { // Fold the panel once the sidebar has closed (not while its drawer is still sliding away)
        id: foldTimer
        interval: 500
        onTriggered: root.selected = ""
    }
    Component.onCompleted: if (_watching) ResourceUsage.watchers++
    Component.onDestruction: if (_watching) ResourceUsage.watchers--

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }
    function usedOfTotal(used, total) { // "3.1 / 16 GB"
        return used.toFixed(1) + " / " + (total >= 10 ? total.toFixed(0) : total.toFixed(1)) + " GB";
    }
    function percent(fraction) {
        return Math.round(fraction * 100) + "%";
    }
    function average(list) {
        return list.length ? list.reduce((a, b) => a + b, 0) / list.length : 0;
    }
    function peak(list) {
        return list.length ? Math.max(...list) : 0;
    }

    // ── Usage history, sampled while the sidebar is open (the service only polls then anyway) ──
    readonly property int historyLength: 40 // 40 × 3 s = 2 min at the default interval
    readonly property int sampleInterval: Config.options?.resources?.updateInterval ?? 3000
    property var ramHistory: []
    property var cpuHistory: []
    property var gpuHistory: []
    function pushSample(list, value) {
        const next = list.concat([Math.min(1, Math.max(0, value))]);
        return next.length > historyLength ? next.slice(next.length - historyLength) : next;
    }
    Timer {
        running: root._watching
        repeat: true // Not on start: CPU usage is a delta between polls, so right after opening it's stale
        interval: root.sampleInterval
        onTriggered: {
            root.ramHistory = root.pushSample(root.ramHistory, ResourceUsage.memoryUsedPercentage);
            root.cpuHistory = root.pushSample(root.cpuHistory, ResourceUsage.cpuUsage);
            if (ResourceUsage.gpuDetected) root.gpuHistory = root.pushSample(root.gpuHistory, ResourceUsage.gpuUsage);
        }
    }

    // Warning thresholds, shared by the tiles and the panel
    readonly property bool ramWarning: ResourceUsage.memoryUsedPercentage * 100 >= Config.options.bar.resources.memoryWarningThreshold
    readonly property bool cpuWarning: ResourceUsage.cpuUsage * 100 >= Config.options.bar.resources.cpuWarningThreshold
    readonly property bool gpuWarning: ResourceUsage.gpuUsage >= 0.9

    // What the panel shows, built for the shown component only (so the others' polls don't rebuild it)
    readonly property var shown: {
        switch (shownKey) {
        case "ram": return {
            title: Translation.tr("Memory"),
            subtitle: formatKB(ResourceUsage.memoryTotal) + " " + Translation.tr("installed"),
            temp: ResourceUsage.ramTemp, hot: 70,
            usage: ResourceUsage.memoryUsedPercentage,
            warning: ramWarning,
            stats: [
                { label: Translation.tr("Used"), value: formatKB(ResourceUsage.memoryUsed) },
                { label: Translation.tr("Available"), value: formatKB(ResourceUsage.memoryFree) },
                { label: Translation.tr("Swap"), value: ResourceUsage.swapTotal > 0
                    ? usedOfTotal(ResourceUsage.swapUsed / 1048576, ResourceUsage.swapTotal / 1048576)
                    : Translation.tr("Off") }
            ]
        };
        case "gpu": return {
            title: Translation.tr("Graphics"),
            subtitle: ResourceUsage.gpuName || (ResourceUsage.gpuType === "amd" ? "AMD" : ResourceUsage.gpuType === "nvidia" ? "NVIDIA" : "GPU"),
            temp: ResourceUsage.gpuTemp, hot: 85,
            usage: ResourceUsage.gpuUsage,
            warning: gpuWarning,
            asleep: ResourceUsage.gpuAsleep,
            stats: [
                { label: Translation.tr("VRAM"), value: ResourceUsage.gpuAsleep ? Translation.tr("Off")
                    : ResourceUsage.vramTotal > 0
                    ? usedOfTotal(ResourceUsage.vramUsed, ResourceUsage.vramTotal) : "—" },
                { label: Translation.tr("Average"), value: percent(average(gpuHistory)) },
                { label: Translation.tr("Peak"), value: percent(peak(gpuHistory)) }
            ]
        };
        default: return {
            title: Translation.tr("Processor"),
            subtitle: ResourceUsage.cpuName || "CPU",
            temp: ResourceUsage.cpuTemp, hot: 85,
            usage: ResourceUsage.cpuUsage,
            warning: cpuWarning,
            stats: [
                { label: Translation.tr("Average"), value: percent(average(cpuHistory)) },
                { label: Translation.tr("Peak"), value: percent(peak(cpuHistory)) },
                { label: Translation.tr("Load"), value: ResourceUsage.cpuUsage > 0.8 ? Translation.tr("High")
                    : ResourceUsage.cpuUsage > 0.4 ? Translation.tr("Medium") : Translation.tr("Low") }
            ]
        };
        }
    }
    // Apart from the rest, so the graph only redraws when a sample lands
    readonly property var shownHistory: shownKey === "ram" ? ramHistory : shownKey === "gpu" ? gpuHistory : cpuHistory
    // Keeps showing the last selection while the panel folds away, instead of going blank mid-animation
    property string shownKey: selected || "cpu"
    // Switching tiles while open slides the old content out and the new in, from the clicked tile's side
    property int switchDirection: 1
    readonly property var tileOrder: ["ram", "cpu", "gpu"]
    onSelectedChanged: {
        if (selected === "") return;
        if (!detail.visible || shownKey === selected) { // Opening: the panel's own fade covers it
            switchAnim.stop();
            detailColumn.opacity = 1;
            slide.x = 0;
            shownKey = selected;
            return;
        }
        switchDirection = tileOrder.indexOf(selected) > tileOrder.indexOf(shownKey) ? 1 : -1;
        switchAnim.restart();
    }
    SequentialAnimation {
        id: switchAnim
        ParallelAnimation {
            NumberAnimation { target: detailColumn; property: "opacity"; to: 0; duration: 90; easing.type: Easing.InCubic }
            NumberAnimation { target: slide; property: "x"; to: -18 * root.switchDirection; duration: 90; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                root.shownKey = root.selected;
                slide.x = 18 * root.switchDirection;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: detailColumn; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: slide; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
    }

    // ── Tiles ──
    RowLayout {
        id: tileRow
        // Inset and gaps as in the quick toggle panel, so the tiles line up with the toggles
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6 }
        spacing: 6
        ResourceTile {
            key: "ram"; icon: "memory"; label: "RAM"
            usage: ResourceUsage.memoryUsedPercentage; warning: root.ramWarning
        }
        ResourceTile {
            key: "cpu"; icon: "planner_review"; label: "CPU"
            usage: ResourceUsage.cpuUsage; warning: root.cpuWarning
        }
        ResourceTile {
            key: "gpu"; icon: "stadia_controller"; label: "GPU"
            usage: ResourceUsage.gpuUsage; warning: root.gpuWarning
            asleep: ResourceUsage.gpuAsleep
            visible: ResourceUsage.gpuDetected
        }
    }

    // ── Detail panel for the selected tile ──
    Rectangle {
        id: detail
        anchors { left: tileRow.left; right: tileRow.right; top: tileRow.bottom; topMargin: 6 }
        implicitHeight: detailColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        clip: true // The switch slide stays inside the panel
        opacity: root.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        readonly property color accent: root.shown.warning ? Appearance.colors.colError : Appearance.colors.colPrimary
        MouseArea { // Clicking the panel folds it away too
            anchors.fill: parent
            onClicked: root.selected = ""
        }
        ColumnLayout {
            id: detailColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            transform: Translate { id: slide }
            spacing: 10

            // Name and model, with the temperature as a chip
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        width: parent.width
                        text: root.shown.title
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        width: parent.width
                        text: root.shown.subtitle
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                Rectangle {
                    id: tempChip
                    readonly property bool hot: root.shown.temp >= root.shown.hot
                    readonly property color tint: hot ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                    visible: root.shown.temp > 0
                    implicitWidth: tempRow.implicitWidth + 16
                    implicitHeight: 24
                    radius: 8
                    color: ColorUtils.transparentize(tint, hot ? 0.85 : 0.92)
                    Row {
                        id: tempRow
                        anchors.centerIn: parent
                        spacing: 3
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "device_thermostat"
                            iconSize: 15
                            color: tempChip.tint
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(root.shown.temp) + "°C"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            font.family: Appearance.font.family.numbers
                            color: tempChip.tint
                        }
                    }
                }
            }

            // Usage graph over the last couple of minutes: newest on the right, filled underneath
                LineGraph {
                    id: graph
                    Layout.fillWidth: true
                    // Whatever history there is spans the width, so it isn't a stub at the edge right after opening
                    points: {
                        const samples = root.shownHistory, last = Math.max(1, samples.length - 1);
                        return samples.map((v, i) => Qt.point(1 - (samples.length - 1 - i) / last, v));
                    }
                    color: detail.accent
                    hideLine: !!root.shown.asleep // The GPU is powered down
                    emptyText: root.shown.asleep ? Translation.tr("Powered down to save battery\nWakes up when an app needs it")
                        : Translation.tr("Collecting…")
                    StyledText { // Current value, top right over the graph
                        anchors { right: parent.right; top: parent.top }
                        visible: !root.shown.asleep
                        text: root.percent(root.shown.usage)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        color: detail.accent
                    }
                }

            // A few stats in equal columns. A fixed count, not the stats array: a new array on every poll
            // would rebuild the columns each time; this way only their text changes
            Row {
                id: statRow
                Layout.fillWidth: true
                Repeater {
                    model: 3
                    Column {
                        required property int index
                        readonly property var stat: root.shown.stats[index] ?? { label: "", value: "" }
                        width: statRow.width / 3
                        spacing: 1
                        StyledText {
                            width: parent.width - 6
                            text: parent.stat.value
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            width: parent.width - 6
                            text: parent.stat.label
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // A quick-toggle-sized tile: usage ring around the icon, then value and name. Selected shows in
    // the accent, like a toggle that's on
    component ResourceTile: Rectangle {
        id: tile
        required property string key
        required property string icon
        required property string label
        required property real usage
        required property bool warning
        property bool asleep: false // Powered-down GPU: "Asleep" and a moon instead of a 0 % reading
        readonly property bool selected: root.selected === key
        readonly property color accent: warning ? Appearance.colors.colError : Appearance.colors.colPrimary
        Layout.fillWidth: true
        implicitHeight: 56
        radius: tileMouse.containsPress ? height / 2 : Appearance.rounding.normal // Morphs toward a pill while held, like the toggles
        Behavior on radius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        color: tileMouse.containsPress ? Appearance.colors.colLayer2Active
            : tileMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected = tile.selected ? "" : tile.key
        }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 10
            Item { // Usage ring, where the toggles have their icon squircle
                id: ring
                implicitWidth: 34
                implicitHeight: 34
                property real shownFraction: Math.min(1, Math.max(0, tile.usage))
                Behavior on shownFraction { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Rectangle { // Filled behind the icon when selected, like an "on" toggle's squircle
                    anchors.centerIn: parent
                    width: 24; height: 24; radius: 12
                    color: tile.accent
                    opacity: tile.selected ? 1 : 0
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer // Smooth edges without multisampling or a layer
                    ShapePath { // Track
                        fillColor: "transparent"
                        strokeColor: Appearance.colors.colLayer3
                        strokeWidth: 3
                        PathAngleArc { centerX: 17; centerY: 17; radiusX: 15.5; radiusY: 15.5; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: tile.accent
                        strokeWidth: 3
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 17; centerY: 17; radiusX: 15.5; radiusY: 15.5
                            startAngle: -90
                            sweepAngle: 360 * ring.shownFraction
                        }
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: tile.asleep ? "bedtime" : tile.icon
                    iconSize: tile.selected ? 15 : 17
                    fill: tile.selected || tile.warning ? 1 : 0
                    color: tile.selected ? (tile.warning ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary)
                        : tile.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                }
            }
            Column {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    text: tile.asleep ? Translation.tr("Asleep") : root.percent(tile.usage)
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: tile.selected || tile.warning ? tile.accent : Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: tile.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
