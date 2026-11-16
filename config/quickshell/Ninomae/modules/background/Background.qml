pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
Variants {
    id: root
    model: Quickshell.screens
    PanelWindow {
        id: bgRoot
        required property var modelData
        // Hide when fullscreen
        readonly property bool fullscreen: (monitor?.activeWorkspace?.toplevels?.values ?? []).some(w => w.wayland?.fullscreen)
        visible: !fullscreen || !Config?.options.background.hideWhenFullscreen
        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        // Wallpaper
        property bool wallpaperIsVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.wallpaperPath) // Any case (.MP4 too), like switchwall.sh
        // Follows the config, a size version made for this screen's shape if there is one (WallpaperVariants).
        // During a theme change only once the old one is held as a still picture (below), so it loads under that
        readonly property string configWallpaper: wallpaperIsVideo ? Config.thumbnailPath
            : WallpaperVariants.forScreen(Config.wallpaperPath, modelData.width, modelData.height)
        property string wallpaperPath
        Binding on wallpaperPath {
            when: !GlobalStates.themeHold || bgRoot.stillShown || bgRoot.wallpaperIsVideo
            value: bgRoot.configWallpaper
            restoreMode: Binding.RestoreNone
        }
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
        property real preferredWallpaperScale: Config.options.background.parallax.workspaceZoom
        property real effectiveWallpaperScale: 1 // Some reasonable init value, to be updated
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
        }
        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-ping", "-format", "%w %h", path] // -ping: read the size, don't decode the image
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;
                    if (width <= screenWidth || height <= screenHeight) {
                        // Undersized/perfectly sized: the image's width/height already stretch it to cover the
                        // screen (wallpaperToScreenRatio), so only the parallax zoom goes on top
                        bgRoot.effectiveWallpaperScale = bgRoot.preferredWallpaperScale;
                    } else {
                        // Oversized = can be zoomed for parallax, yay
                        bgRoot.effectiveWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                    }
                }
            }
        }
        // Wallpaper
        Item {
            id: wallpaperLayer
            anchors.fill: parent
            clip: true
            StyledImage {
                id: wallpaper
                visible: opacity > 0
                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                cache: false
                smooth: bgRoot.wallpaperToScreenRatio < 1 // Upscaled small images look blocky without it
                // Range = groups that workspaces span on
                property int chunkSize: Config?.options.bar.workspaces.shown ?? 10
                // Workspaces 1–10 are one group (0-based), so ws 10 is the far end, not the start of the next
                property int lower: Math.floor(((bgRoot.monitor?.activeWorkspace?.id ?? 1) - 1) / chunkSize) * chunkSize + 1
                property int range: Math.max(1, chunkSize - 1)
                property real valueX: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        result = (((bgRoot.monitor?.activeWorkspace?.id ?? lower) - lower) / range);
                    }
                    return result;
                }
                property real valueY: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        result = (((bgRoot.monitor?.activeWorkspace?.id ?? lower) - lower) / range);
                    }
                    return result;
                }
                property real effectiveValueX: Math.max(0, Math.min(1, valueX))
                property real effectiveValueY: Math.max(0, Math.min(1, valueY))
                x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                source: bgRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                sourceSize {
                    width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * (bgRoot.monitor?.scale ?? 1)
                    height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * (bgRoot.monitor?.scale ?? 1)
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            }
        }

        // ── Theme change (modules/themeTransition, GlobalStates.themeHold): a new wallpaper waits for the reveal.
        // The old one is taken as a still picture, only once there is a new one (not for light/dark), the new one
        // loads under it, and the picture goes at the reveal (under the screen cover) once the new one is in ──
        property bool stillShown: false // The picture is on screen: the new wallpaper may load under it
        property var grabbed: null      // Kept: the picture lives as long as this does
        onConfigWallpaperChanged: {
            if (!GlobalStates.themeHold || wallpaperIsVideo || grabbed || configWallpaper === wallpaperPath) return;
            wallpaperLayer.grabToImage(result => {
                if (!GlobalStates.themeHold) return;
                bgRoot.grabbed = result;
                still.source = result.url;
            });
            stillFallback.restart();
        }
        Connections {
            target: GlobalStates
            function onThemeHoldChanged() { bgRoot.dropStill(); }
        }
        Connections {
            target: wallpaper
            function onStatusChanged() { bgRoot.dropStill(); }
        }
        function dropStill() { // Once the new wallpaper is in (it may still be loading at the reveal)
            if (GlobalStates.themeHold || wallpaper.status === Image.Loading) return;
            stillFallback.stop();
            still.source = "";
            grabbed = null;
            stillShown = false;
        }
        Timer { // The picture never came: let the new wallpaper load anyway
            id: stillFallback
            interval: 400
            onTriggered: if (GlobalStates.themeHold) bgRoot.stillShown = true
        }
        Timer { // One frame for the picture to reach the screen before the wallpaper under it changes
            id: stillPainted
            interval: 20
            onTriggered: if (GlobalStates.themeHold) bgRoot.stillShown = true
        }
        Image {
            id: still
            anchors.fill: parent
            visible: source != "" && status === Image.Ready
            cache: false
            onStatusChanged: if (status === Image.Ready && GlobalStates.themeHold) stillPainted.restart()
        }
    }
}
