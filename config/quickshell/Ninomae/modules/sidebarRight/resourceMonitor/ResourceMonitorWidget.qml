import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
// Your machine in a well: RAM, CPU and GPU, each a small ring (how full, its icon inside) with the figure and name
// beside it and a detail under them (used of total, the temperature, Asleep). Clicking one selects it (the accent
// card) and grows the well to hold its panel: a usage graph of the last couple of minutes with the figure and model on
// it, a few stats and the temperature, and (CPU and RAM) the apps using the most of it, each with End. Clicking it
// again (or the panel) closes it
Item {
    id: root
    property string selected: "" // "", "ram", "cpu" or "gpu"
    readonly property bool open: selected !== ""
    implicitHeight: tileRow.implicitHeight + (open ? detail.implicitHeight : 0)
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

    // ── One well: the rings, and the open one's panel under them (the well grows to hold it) ──
    GlassWell {
        anchors.fill: parent
    }
    Item {
        id: tileRow
        anchors { left: parent.left; right: parent.right; top: parent.top }
        implicitHeight: 72
        RowLayout {
            anchors { fill: parent; margins: 6 }
            spacing: 2
            RingTile {
                key: "ram"; label: "RAM"; icon: "memory"
                usage: ResourceUsage.memoryUsedPercentage; warning: root.ramWarning
                detail: root.usedOfTotal(ResourceUsage.memoryUsed / 1048576, ResourceUsage.memoryTotal / 1048576)
            }
            RingTile {
                key: "cpu"; label: "CPU"; icon: "developer_board"
                usage: ResourceUsage.cpuUsage; warning: root.cpuWarning
                detail: root.temperature(ResourceUsage.cpuTemp)
            }
            RingTile {
                key: "gpu"; label: "GPU"; icon: "stadia_controller"
                usage: ResourceUsage.gpuUsage; warning: root.gpuWarning
                asleep: ResourceUsage.gpuAsleep
                detail: asleep ? Translation.tr("Asleep") : root.temperature(ResourceUsage.gpuTemp)
                visible: ResourceUsage.gpuDetected
            }
        }
    }
    function temperature(c) { return c > 0 ? Math.round(c) + " °C" : ""; }

    // ── The selected one's panel, in the same well under the rings: the graph in a box tinted its colour, the figure
    //    big on it with the model under; average, peak, load and the temperature as small pieces; the apps using the most ──
    Item {
        id: detail
        anchors { left: tileRow.left; right: tileRow.right; top: tileRow.bottom }
        implicitHeight: detailColumn.implicitHeight + 18
        clip: true // The switch slide stays inside
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
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4; leftMargin: 6; rightMargin: 6 }
            transform: Translate { id: slide }
            spacing: 10

            Rectangle { // The graph in a box tinted its colour, the figure on it
                Layout.fillWidth: true
                implicitHeight: 118
                radius: 12
                color: ColorUtils.transparentize(detail.accent, 0.94)
                LineGraph {
                    // Inset: clear of the figure and the box's round corners (no clipping layer: a box-sized one hung
                    // the Intel GPU in the drawers)
                    anchors { fill: parent; topMargin: 34; leftMargin: 10; rightMargin: 10; bottomMargin: 10 }
                    guides: false
                    // Whatever history there is spans the width, so it isn't a stub at the edge right after opening
                    points: {
                        const samples = root.shownHistory, last = Math.max(1, samples.length - 1);
                        return samples.map((v, i) => Qt.point(1 - (samples.length - 1 - i) / last, v));
                    }
                    color: detail.accent
                    hideLine: !!root.shown.asleep // The GPU is powered down
                    emptyText: root.shown.asleep ? Translation.tr("Powered down to save battery\nWakes up when an app needs it")
                        : Translation.tr("Collecting…")
                }
                Column {
                    anchors { left: parent.left; top: parent.top; leftMargin: 12; topMargin: 8 }
                    spacing: 0
                    StyledText {
                        visible: !root.shown.asleep
                        text: root.percent(root.shown.usage)
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({})
                        color: detail.accent
                    }
                    StyledText {
                        text: root.shown.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtextGlass
                    }
                }
            }

            // Average, peak, load (a fixed count: only their text changes per poll) and the temperature, as pieces
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: 3
                    StatPiece {
                        required property int index
                        readonly property var stat: root.shown.stats[index] ?? { label: "", value: "" }
                        value: stat.value
                        label: stat.label
                    }
                }
                StatPiece {
                    readonly property bool hot: root.shown.temp >= root.shown.hot
                    visible: root.shown.temp > 0
                    value: Math.round(root.shown.temp) + " °C"
                    label: Translation.tr("Temp")
                    valueColor: hot ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                }
            }

            // The apps using the most of it (CPU and RAM), heaviest first: rows straight on the well
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.shownApps.length > 0
                spacing: 2
                StyledText {
                    Layout.leftMargin: 8
                    Layout.bottomMargin: 2
                    text: Translation.tr("Using the most")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtextGlass
                }
                // A fixed count of rows, not the list itself: a new list every few seconds would rebuild them
                // (a hovered button flickering, a click landing mid-rebuild lost); this way only their text changes
                Repeater {
                    model: root.topAppRows
                    Rectangle {
                        id: appRow
                        required property int index
                        readonly property var modelData: root.shownApps[index] ?? { name: "", appId: "", pid: 0, cpu: 0, mem: 0 }
                        readonly property string key: modelData.appId || modelData.name
                        // Re-read with each update (every few seconds), so Force quit turns up on its own
                        readonly property bool forceable: { root.topApps; return root.canForce(modelData.pid); }
                        visible: index < root.shownApps.length
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 12
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, rowHover.hovered ? 0.93 : 1)
                        HoverHandler { id: rowHover }
                        Rectangle { // Its icon on a squircle
                            id: appIcon
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28; radius: 9
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 18
                                source: Quickshell.iconPath(AppSearch.guessIcon(appRow.key), "application-x-executable")
                            }
                        }
                        StyledText {
                            anchors { left: appIcon.right; leftMargin: 10; right: appUse.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: DesktopEntries.heuristicLookup(appRow.key)?.name ?? appRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            id: appUse
                            anchors { right: endButton.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: root.shownKey === "ram" ? root.formatBytes(appRow.modelData.mem)
                                : appRow.modelData.cpu < 0.01 ? "<1%" : root.percent(appRow.modelData.cpu)
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colSubtextGlass
                        }
                        // End: a quiet glass piece, red-tinted while its row is pointed at (solid red for Force quit)
                        DialogButton {
                            id: endButton
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            implicitHeight: 26
                            padding: 10
                            buttonRadius: 9
                            buttonText: appRow.forceable ? Translation.tr("Force quit") : Translation.tr("End")
                            colBackground: appRow.forceable ? Appearance.colors.colErrorContainer
                                : rowHover.hovered ? ColorUtils.transparentize(Appearance.colors.colError, 0.82)
                                : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
                            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.72)
                            colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.6)
                            colText: appRow.forceable ? Appearance.colors.colOnErrorContainer
                                : rowHover.hovered ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                            onClicked: root.endApp(appRow.modelData.pid)
                        }
                    }
                }
            }
        }
    }

    // A component in the well: a small ring (how full, red at a warning) with its icon inside, the figure and name
    // beside it, a detail under them. A button: a soft card when pointed at, the accent card while its panel is open
    component RingTile: Rectangle {
        id: tile
        required property string key
        required property string label
        required property string icon
        required property real usage
        required property bool warning
        property string detail: ""
        property bool asleep: false // Powered-down GPU: no reading
        readonly property bool selected: root.selected === key
        readonly property color accent: warning ? Appearance.colors.colError : Appearance.colors.colPrimary
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        radius: 12
        color: selected ? Appearance.colors.colLayer3Accent
            : tileMouse.containsMouse ? ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.93)
            : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected = tile.selected ? "" : tile.key
        }
        UsageRing {
            id: ring
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            fraction: tile.asleep ? 0 : tile.usage
            colour: tile.accent
            icon: tile.asleep ? "bedtime" : tile.icon
            iconColour: tile.asleep ? Appearance.colors.colSubtextGlass : tile.accent
        }
        Column {
            anchors { left: ring.right; leftMargin: 9; right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            spacing: 0
            Row {
                spacing: 4
                StyledText {
                    id: figure
                    text: tile.asleep ? "—" : root.percent(tile.usage)
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning
                    color: tile.warning ? tile.accent : tile.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
                StyledText {
                    anchors.baseline: figure.baseline
                    text: tile.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtextGlass
                }
            }
            StyledText {
                visible: text !== ""
                width: parent.width
                elide: Text.ElideRight
                text: tile.detail
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtextGlass
            }
        }
    }
}
