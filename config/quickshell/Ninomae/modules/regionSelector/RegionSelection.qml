pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * One screen's region selector: its frozen frame, dimmed, with the windows, popups and pictures in them to
 * click (TargetRegion), or a rectangle to drag, or a shape to circle. Releasing does the action
 * (snip.sh): Screenshot saves and copies, Edit opens it in swappy (releasing with the right button too),
 * Search looks it up on the web, Text copies the text in it.
 * The action and shape belong to RegionSelector (shared by every screen): changes go up through
 * actionRequested and selectionModeRequested.
 */
PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    enum SnipAction { Copy, Edit, Search, CharRecognition }
    enum SelectionMode { RectCorners, Circle }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    signal actionRequested(var action)
    signal selectionModeRequested(var mode)
    signal dismiss()
    property string screenshotDir: Directories.screenshotTemp
    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property color overlayColor: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.35)
    property color selectionBorderColor: Appearance.colors.colPrimary
    property color windowBorderColor: Appearance.colors.colSubtext
    property color windowFillColor: ColorUtils.transparentize(Appearance.colors.colSubtext, 0.92)
    property color imageBorderColor: Appearance.colors.colTertiary
    property color imageFillColor: ColorUtils.transparentize(Appearance.colors.colTertiary, 0.92)
    // Floating windows first: they're on top, so a click picks them over a tiled one under them
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => (b.floating ? 1 : 0) - (a.floating ? 1 : 0))
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y
    property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
    readonly property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property bool dragging: false
    // Moved far enough to be a drag rather than a (slightly wobbly) click
    readonly property bool draggedAway: dragging && (Math.abs(draggingX - dragStartX) >= 4 || Math.abs(draggingY - dragStartY) >= 4)
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(
        root.windows.filter(w => w.workspace.id === root.activeWorkspaceId),
        root.layerRegions
    ).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title,
        }
    })
    // Top-level layers of this monitor (popups, the sidebar…), except the bar and dock
    readonly property list<var> layerRegions: (root.layers[root.hyprlandMonitor.name]?.levels["2"] ?? [])
        .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
        .map(layer => ({
            at: [layer.x - root.monitorOffsetX, layer.y - root.monitorOffsetY],
            size: [layer.w, layer.h],
            namespace: layer.namespace,
        }))
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property real contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity
    property var targetedRegion: null // The region under the cursor that a click would pick
    property real regionX: 0
    property real regionY: 0
    property real regionWidth: 0
    property real regionHeight: 0
    function isTargeted(region) {
        const t = root.targetedRegion;
        return !root.draggedAway && !!t && t.at[0] === region.at[0] && t.at[1] === region.at[1]
            && t.size[0] === region.size[0] && t.size[1] === region.size[1];
    }
    function updateTargetedRegion(x, y) {
        // Topmost first, and only regions that are drawn: a click shouldn't snap to something hidden
        const candidates = [
            ...(root.enableContentRegions ? root.imageRegions : []),
            ...(root.enableLayerRegions ? root.layerRegions : []),
            ...(root.enableWindowRegions ? root.windowRegions : []),
        ];
        root.targetedRegion = candidates.find(region => RegionFunctions.contains(region, x, y)) ?? null;
    }
    function setRegion(x, y, width, height) {
        root.regionX = x;
        root.regionY = y;
        root.regionWidth = width;
        root.regionHeight = height;
    }
    function resetDrag() {
        root.dragging = false;
        root.points = [];
        root.setRegion(0, 0, 0, 0);
    }
    function captureScreen() {
        root.mouseButton = Qt.LeftButton;
        root.setRegion(0, 0, root.screen.width, root.screen.height);
        root.snip(); // With whatever action is picked: a whole-screen search or OCR works too
    }
    // The frame for snip.sh to crop, uncompressed: it's a scratch file in the runtime dir, and grim writes it
    // ~8x faster that way, which is how long the selector takes to show
    Process {
        id: screenshotProc
        running: true
        command: ["sh", "-c", 'mkdir -p -- "$1" && grim -l 0 -o "$2" -- "$3"', "grab", root.screenshotDir, root.screen.name, root.screenshotPath]
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions) imageDetectionProcess.running = true;
            root.visible = true;
        }
    }
    // Pictures and panels in the frame (scripts/images/find_regions.py). It works in the frame's pixels: the
    // screen's, times its scale
    Process {
        id: imageDetectionProcess
        command: [`${Directories.scriptPath}/images/find-regions-venv.sh`, "--hyprctl",
            "--image", root.screenshotPath,
            "--max-width", `${Math.round(root.screen.width * root.monitorScale * root.falsePositivePreventionRatio)}`,
            "--max-height", `${Math.round(root.screen.height * root.monitorScale * root.falsePositivePreventionRatio)}`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = root.monitorScale;
                    const found = JSON.parse(text).map(r => ({ at: [r.at[0] / s, r.at[1] / s], size: [r.size[0] / s, r.size[1] / s] }));
                    // Only pictures inside a window or popup: on the bare wallpaper it finds shapes in the art
                    root.imageRegions = RegionFunctions.filterImageRegions(found, root.windowRegions, root.layerRegions);
                } catch (e) {
                    console.warn("[Region Selector] Content detection gave no usable output");
                }
            }
        }
    }
    // The frozen frame of this screen. snip.sh removes it after using it; otherwise (Esc, or this is
    // another monitor than the one snipped) it's removed when the selector closes
    property bool frameHandedOff: false
    Component.onDestruction: {
        if (!root.frameHandedOff) Quickshell.execDetached(["rm", "-f", root.screenshotPath]);
    }
    function snip() {
        // Nothing selected (a click on empty space): stay open. Carrying on would crop 0x0, which
        // ImageMagick reads as the whole screen
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            root.resetDrag();
            return;
        }
        // Clamp to the screen, then to physical pixels
        const x = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        const y = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        const w = Math.min(root.regionWidth, root.screen.width - x);
        const h = Math.min(root.regionHeight, root.screen.height - y);
        const scale = root.monitorScale;
        const geometry = `${Math.round(w * scale)}x${Math.round(h * scale)}+${Math.round(x * scale)}+${Math.round(y * scale)}`;
        let args;
        switch (root.action) {
            case RegionSelection.SnipAction.Copy:
            case RegionSelection.SnipAction.Edit: // Or a screenshot released with the right button
                args = [root.action === RegionSelection.SnipAction.Edit || root.mouseButton === Qt.RightButton ? "edit" : "copy",
                    Config.options.regionSelector.save ? Config.options.regionSelector.saveDir : ""];
                break;
            case RegionSelection.SnipAction.Search:
                args = ["search", root.imageSearchEngineBaseUrl];
                break;
            case RegionSelection.SnipAction.CharRecognition:
                args = ["ocr"];
                break;
        }
        root.frameHandedOff = true;
        Quickshell.execDetached([`${Directories.scriptPath}/screenshot/snip.sh`, args[0], root.screenshotPath, geometry, ...args.slice(1)]);
        root.dismiss();
    }
    ScreencopyView {
        anchors.fill: parent
        live: false
        captureSource: root.screen
        focus: root.visible
        Keys.onPressed: (event) => {
            switch (event.key) {
                case Qt.Key_Escape: root.dismiss(); break;
                case Qt.Key_Return: case Qt.Key_Enter: root.captureScreen(); break;
                case Qt.Key_S: root.actionRequested(RegionSelection.SnipAction.Copy); break;
                case Qt.Key_E: root.actionRequested(RegionSelection.SnipAction.Edit); break;
                case Qt.Key_F: root.actionRequested(RegionSelection.SnipAction.Search); break;
                case Qt.Key_T: root.actionRequested(RegionSelection.SnipAction.CharRecognition); break;
                case Qt.Key_Tab:
                    root.selectionModeRequested(root.isCircleSelection ? RegionSelection.SelectionMode.RectCorners
                        : RegionSelection.SelectionMode.Circle);
                    break;
                default: return;
            }
            event.accepted = true;
        }
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onPressed: (mouse) => {
                root.dragStartX = root.draggingX = mouse.x;
                root.dragStartY = root.draggingY = mouse.y;
                root.points = [];
                root.dragging = true;
                root.mouseButton = mouse.button;
            }
            onReleased: (mouse) => {
                if (!root.draggedAway) {
                    // A click: take the region under the cursor (snip() stays open if there's none)
                    const t = root.targetedRegion;
                    if (t) root.setRegion(t.at[0], t.at[1], t.size[0], t.size[1]);
                    else root.setRegion(0, 0, 0, 0);
                } else if (root.isCircleSelection && root.points.length > 0) {
                    // The scribble's bounding box, padded so the stroke itself isn't cut off
                    const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                    const xs = root.points.map(p => p.x);
                    const ys = root.points.map(p => p.y);
                    const minX = Math.min(...xs), minY = Math.min(...ys);
                    root.setRegion(minX - padding, minY - padding,
                        Math.max(...xs) - minX + padding * 2, Math.max(...ys) - minY + padding * 2);
                }
                root.snip();
            }
            onPositionChanged: (mouse) => {
                if (!root.dragging) {
                    root.updateTargetedRegion(mouse.x, mouse.y);
                    return;
                }
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                if (root.isCircleSelection) {
                    // Every point re-lays out the whole stroke: skip ones that barely moved
                    const last = root.points.length > 0 ? root.points[root.points.length - 1] : null;
                    if (!last || Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y) >= 3)
                        root.points.push(Qt.point(mouse.x, mouse.y));
                } else {
                    root.setRegion(Math.min(root.dragStartX, mouse.x), Math.min(root.dragStartY, mouse.y),
                        Math.abs(mouse.x - root.dragStartX), Math.abs(mouse.y - root.dragStartY));
                }
            }
            Loader {
                z: 2
                anchors.fill: parent
                active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
                sourceComponent: RectCornersSelectionDetails {
                    regionX: root.regionX
                    regionY: root.regionY
                    regionWidth: root.regionWidth
                    regionHeight: root.regionHeight
                    mouseX: mouseArea.mouseX
                    mouseY: mouseArea.mouseY
                    color: root.selectionBorderColor
                    overlayColor: root.overlayColor
                    pixelRatio: root.monitorScale
                }
            }
            Loader {
                z: 2
                anchors.fill: parent
                active: root.selectionMode === RegionSelection.SelectionMode.Circle
                sourceComponent: CircleSelectionDetails {
                    color: root.selectionBorderColor
                    overlayColor: root.overlayColor
                    points: root.points
                }
            }
            // Window regions
            Repeater {
                model: ScriptModel {
                    values: root.enableWindowRegions ? root.windowRegions : []
                }
                delegate: TargetRegion {
                    z: 2
                    required property var modelData
                    clientDimensions: modelData
                    showIcon: true
                    targeted: root.isTargeted(modelData)
                    opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.class}`
                    radius: Appearance.rounding.windowRounding
                }
            }
            // Layer regions
            Repeater {
                model: ScriptModel {
                    values: root.enableLayerRegions ? root.layerRegions : []
                }
                delegate: TargetRegion {
                    z: 3
                    required property var modelData
                    clientDimensions: modelData
                    targeted: root.isTargeted(modelData)
                    opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.namespace}`
                    radius: Appearance.rounding.windowRounding
                }
            }
            // Content regions
            Repeater {
                model: ScriptModel {
                    values: root.enableContentRegions ? root.imageRegions : []
                }
                delegate: TargetRegion {
                    z: 4
                    required property var modelData
                    clientDimensions: modelData
                    targeted: root.isTargeted(modelData)
                    opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                    borderColor: root.imageBorderColor
                    fillColor: targeted ? root.imageFillColor : "transparent"
                    text: Translation.tr("Content region")
                }
            }
            // Controls
            OptionsToolbar { // Slides up once the frame is up
                z: 9999
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                anchors.bottomMargin: root.visible ? 16 : -height
                opacity: root.visible ? 1 : 0
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on anchors.bottomMargin { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                action: root.action
                selectionMode: root.selectionMode
                onActionPicked: a => root.actionRequested(a)
                onSelectionModePicked: m => root.selectionModeRequested(m)
                onDismiss: root.dismiss()
                onCaptureScreen: root.captureScreen()
            }
        }
    }
}
