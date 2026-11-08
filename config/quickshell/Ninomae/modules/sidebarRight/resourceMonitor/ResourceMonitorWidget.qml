import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
// Three chips joined into one strip (as the quick toggles' block), usage as a ring around each icon. Clicking
// one selects it and opens a panel underneath, joined to the strip with just that component: name and temperature, a usage graph of the
// last couple of minutes, a few stats, and (CPU and RAM) the apps using the most of it, each with End.
// Clicking it again (or the panel) closes it
Item {
    id: root
    property string selected: "" // "", "ram", "cpu" or "gpu"
    readonly property bool open: selected !== ""
    implicitHeight: tileRow.implicitHeight + (open ? 4 + detail.implicitHeight : 0)
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

    // ── The apps using the most CPU or RAM: scripts/top_apps.py, while the sidebar is open (a scan takes
    // ~5 ms), so the list is already there when a tile is clicked ──
    readonly property int topAppRows: 4
    property var topApps: ({ cpu: [], mem: [] })
    readonly property var shownApps: shownKey === "ram" ? topApps.mem : shownKey === "cpu" ? topApps.cpu : []
    Process {
        running: root._watching
        command: ["python3", "-I", Quickshell.shellPath("scripts/top_apps.py"), String(root.sampleInterval / 1000), String(root.topAppRows)]
        stdout: SplitParser {
            onRead: line => {
                try { root.topApps = JSON.parse(line); } catch (e) { return; }
                // Forget End presses for apps that have gone
                const listed = new Set([...root.topApps.cpu, ...root.topApps.mem].map(a => a.pid));
                const gone = Object.keys(root._ending).filter(pid => !listed.has(Number(pid)));
                if (gone.length === 0) return;
                const ending = Object.assign({}, root._ending);
                for (const pid of gone) delete ending[pid];
                root._ending = ending;
            }
        }
        onRunningChanged: if (!running) root.topApps = { cpu: [], mem: [] }
    }
    // End asks the app to quit (SIGTERM, as closing it would). Still running 3 s later, the button offers
    // Force quit (SIGKILL)
    property var _ending: ({}) // pid → when End was pressed
    function canForce(pid) {
        return root._ending[pid] !== undefined && Date.now() - root._ending[pid] >= 3000;
    }
    function endApp(pid) {
        const force = root.canForce(pid);
        Quickshell.execDetached(["kill", force ? "-KILL" : "-TERM", String(pid)]);
        if (!force) root._ending = Object.assign({}, root._ending, { [pid]: Date.now() });
    }
    function formatBytes(bytes) {
        return bytes >= 1e9 ? (bytes / 1073741824).toFixed(1) + " GB" : Math.round(bytes / 1048576) + " MB";
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
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 4
        ResourceTile {
            first: true
            key: "ram"; icon: "memory"; label: "RAM"
            usage: ResourceUsage.memoryUsedPercentage; warning: root.ramWarning
        }
        ResourceTile {
            last: !ResourceUsage.gpuDetected
            key: "cpu"; icon: "planner_review"; label: "CPU"
            usage: ResourceUsage.cpuUsage; warning: root.cpuWarning
        }
        ResourceTile {
            last: true
            key: "gpu"; icon: "stadia_controller"; label: "GPU"
            usage: ResourceUsage.gpuUsage; warning: root.gpuWarning
            asleep: ResourceUsage.gpuAsleep
            visible: ResourceUsage.gpuDetected
        }
    }

    // ── Detail panel for the selected tile ──
    Rectangle {
        id: detail
        anchors { left: tileRow.left; right: tileRow.right; top: tileRow.bottom; topMargin: 4 }
        implicitHeight: detailColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        topLeftRadius: Appearance.rounding.joined // Joined to the strip above
        topRightRadius: Appearance.rounding.joined
        color: Appearance.colors.colLayer3
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
                        color: Appearance.colors.colOnLayer3
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
                    readonly property color tint: hot ? Appearance.colors.colError : Appearance.colors.colOnLayer3
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
                            color: Appearance.colors.colOnLayer3
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

            // The apps using the most of it (CPU and RAM), heaviest first
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.shownApps.length > 0
                spacing: 4
                StyledText {
                    text: Translation.tr("Using the most")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                // A fixed count of rows, not the list itself: a new list every few seconds would rebuild them
                // (a hovered button flickering, a click landing mid-rebuild lost); this way only their text changes
                Repeater {
                    model: root.topAppRows
                    RowLayout {
                        id: appRow
                        required property int index
                        readonly property var modelData: root.shownApps[index] ?? { name: "", appId: "", pid: 0, cpu: 0, mem: 0 }
                        readonly property string key: modelData.appId || modelData.name
                        // Re-read with each update (every few seconds), so Force quit turns up on its own
                        readonly property bool forceable: { root.topApps; return root.canForce(modelData.pid); }
                        visible: index < root.shownApps.length
                        Layout.fillWidth: true
                        spacing: 8
                        IconImage {
                            implicitSize: 18
                            source: Quickshell.iconPath(AppSearch.guessIcon(appRow.key), "application-x-executable")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: DesktopEntries.heuristicLookup(appRow.key)?.name ?? appRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            text: root.shownKey === "ram" ? root.formatBytes(appRow.modelData.mem)
                                : appRow.modelData.cpu < 0.01 ? "<1%" : root.percent(appRow.modelData.cpu)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colSubtext
                        }
                        DialogButton {
                            implicitHeight: 26
                            padding: 10
                            buttonText: appRow.forceable ? Translation.tr("Force quit") : Translation.tr("End")
                            colBackground: appRow.forceable ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer4
                            colBackgroundHover: Appearance.colors.colLayer4Hover
                            colRipple: Appearance.colors.colLayer4Active
                            colText: appRow.forceable ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer3
                            onClicked: root.endApp(appRow.modelData.pid)
                        }
                    }
                }
            }
        }
    }

    // A chip in the strip: usage ring around the icon, then the value and name in one line. Selected shows in the
    // accent, like a toggle that's on. Round at the strip's ends, slight between (and under, while the panel's open)
    component ResourceTile: Rectangle {
        id: tile
        required property string key
        required property string icon
        required property string label
        required property real usage
        required property bool warning
        property bool first: false
        property bool last: false
        property bool asleep: false // Powered-down GPU: "Asleep" and a moon instead of a 0 % reading
        readonly property bool selected: root.selected === key
        readonly property color accent: warning ? Appearance.colors.colError : Appearance.colors.colPrimary
        readonly property real outer: tileMouse.containsPress ? height / 2 : Appearance.rounding.normal
        readonly property real inner: tileMouse.containsPress ? height / 2 : Appearance.rounding.joined
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 40
        topLeftRadius: first ? outer : inner
        bottomLeftRadius: first && !root.open ? outer : inner
        topRightRadius: last ? outer : inner
        bottomRightRadius: last && !root.open ? outer : inner
        Behavior on topLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on topRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        color: tileMouse.containsPress ? Appearance.colors.colLayer3Active
            : tileMouse.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected = tile.selected ? "" : tile.key
        }
        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            Item { // Usage ring around the icon
                id: ring
                implicitWidth: 26
                implicitHeight: 26
                property real shownFraction: Math.min(1, Math.max(0, tile.usage))
                Behavior on shownFraction { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Rectangle { // Filled behind the icon when selected, like an "on" toggle's squircle
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: tile.accent
                    opacity: tile.selected ? 1 : 0
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer // Smooth edges without multisampling or a layer
                    ShapePath { // Track
                        fillColor: "transparent"
                        strokeColor: Appearance.colors.colLayer4
                        strokeWidth: 2.5
                        PathAngleArc { centerX: 13; centerY: 13; radiusX: 11.75; radiusY: 11.75; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: tile.accent
                        strokeWidth: 2.5
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 13; centerY: 13; radiusX: 11.75; radiusY: 11.75
                            startAngle: -90
                            sweepAngle: 360 * ring.shownFraction
                        }
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: tile.asleep ? "bedtime" : tile.icon
                    iconSize: tile.selected ? 12 : 14
                    fill: tile.selected || tile.warning ? 1 : 0
                    color: tile.selected ? (tile.warning ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary)
                        : tile.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                }
            }
            StyledText {
                text: tile.asleep ? Translation.tr("Asleep") : root.percent(tile.usage)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: tile.selected || tile.warning ? tile.accent : Appearance.colors.colOnLayer3
            }
            StyledText {
                text: tile.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
