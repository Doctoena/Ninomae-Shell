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
        // Follows the config. During a theme change (modules/themeTransition) it only does once the old wallpaper
        // has been captured, so the new one loads underneath that snapshot while the colours are generated
        property string wallpaperPath
        Binding on wallpaperPath {
            when: !GlobalStates.themeHold || bgRoot.oldCaptured || bgRoot.wallpaperIsVideo
            value: bgRoot.wallpaperIsVideo ? Config.thumbnailPath : Config.wallpaperPath
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
            bgRoot.sizeKnown = false;
            bgRoot.updateZoomScale();
        }
        property bool sizeKnown: true // The new wallpaper's size has been read (avoids a jump mid-reveal)
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
                    bgRoot.sizeKnown = true;
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
                property int lower: Math.floor(((bgRoot.monitor.activeWorkspace?.id ?? 1) - 1) / chunkSize) * chunkSize + 1
                property int range: Math.max(1, chunkSize - 1)
                property real valueX: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                    }
                    return result;
                }
                property real valueY: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
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
                    width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                    height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            }
        }

        // ── Theme transition: the old wallpaper fades off the new one, zooming in a touch from the cursor ──
        // A frozen copy of the old wallpaper sits on top; a growing hole in it shows the new one
        // underneath. Windows and video keep running (this is the background layer).
        property bool revealArmed: false   // Old wallpaper captured, waiting for the new one to load
        property bool revealRunning: false
        readonly property real revealCx: GlobalStates.themeRevealX - screen.x
        readonly property real revealCy: GlobalStates.themeRevealY - screen.y
        property real revealProgress: 0 // 0 → 1 while the old wallpaper fades off the new one
        // From the snapshot to the end of the fade, without a gap at the hand-off (a gap showed the new
        // wallpaper for a frame: a flash just before the fade). Only goes false once the fade is done
        property bool revealActive: false
        onRevealArmedChanged: if (revealArmed) revealActive = true
        onRevealRunningChanged: if (!revealRunning && !revealArmed) { revealActive = false; dropSnapshot(); }
        function dropSnapshot() { oldWallpaper.source = ""; grabbed = null; } // Frees the screen-sized picture
        // 1. A theme change starts (prepare): capture the wallpaper as it is, then let the new one load under it
        property bool oldCaptured: false
        property string capturedPath: ""
        Connections {
            target: GlobalStates
            function onThemeHoldChanged() {
                if (!GlobalStates.themeHold || bgRoot.wallpaperIsVideo || bgRoot.revealRunning) return;
                revealAnim.stop();
                bgRoot.revealProgress = 0;
                bgRoot.capturedPath = bgRoot.wallpaperPath;
                bgRoot.revealArmed = true;
                // A still picture of the wallpaper as it is. The new one may only load once this is on screen
                wallpaperLayer.grabToImage(result => {
                    if (!bgRoot.revealArmed) return;
                    bgRoot.grabbed = result; // Kept: the picture lives as long as this does
                    oldWallpaper.source = result.url;
                });
                captureFallback.restart();
                revealTimeout.restart();
            }
            // 2. The colours are ready (reveal): grow the new wallpaper in, as they fade. Same wallpaper (light/dark,
            // a new scheme): there's nothing to grow, the colours just fade
            function onThemeRevealSerialChanged() {
                if (!bgRoot.revealArmed) return;
                if (bgRoot.wallpaperPath === bgRoot.capturedPath) { bgRoot.endReveal(); return; }
                bgRoot.revealWanted = true;
                if (bgRoot.newWallpaperReady) startReveal.restart();
            }
        }
        property var grabbed: null
        Timer { // The picture never came: go on anyway rather than wait out the whole change
            id: captureFallback
            interval: 400
            onTriggered: if (bgRoot.revealArmed && !bgRoot.oldCaptured) bgRoot.oldCaptured = true
        }
        Timer { // The picture is loaded: one frame for it to reach the screen, then the new wallpaper may load
            id: captureDone
            interval: 20
            onTriggered: bgRoot.oldCaptured = true
        }
        property bool revealWanted: false
        function endReveal() {
            revealArmed = false;
            revealRunning = false;
            revealActive = false;
            dropSnapshot();
            revealWanted = false;
            oldCaptured = false;
        }
        readonly property bool newWallpaperReady: wallpaper.status === Image.Ready && sizeKnown
        onNewWallpaperReadyChanged: if (newWallpaperReady && revealArmed && revealWanted) startReveal.restart() // Wasn't loaded yet at reveal
        Timer { // One more frame so the new image is actually painted under the hole
            id: startReveal
            interval: 32
            onTriggered: {
                bgRoot.revealRunning = true; // First: the snapshot must never be hidden between the two
                bgRoot.revealArmed = false;
                bgRoot.revealWanted = false;
                bgRoot.oldCaptured = false;
                revealAnim.restart();
            }
        }
        Timer { // Never revealed (switchwall.sh failed) or the new wallpaper never loaded: don't keep the old one up
            id: revealTimeout
            interval: 16000 // Past ThemeTransition's own 15 s safety release
            onTriggered: bgRoot.endReveal()
        }
        NumberAnimation {
            id: revealAnim
            target: bgRoot
            property: "revealProgress"
            from: 0
            to: 1
            duration: 800 // As the colour fade (Appearance), on the same curve
            easing.type: Easing.InOutCubic
            onFinished: bgRoot.revealRunning = false
        }
        // During a theme change: a snapshot of the old wallpaper over the new one. At the reveal it fades away,
        // zooming in a touch from the cursor, as the colours fade. A plain crossfade: no masks or clipping (a
        // circle mask drew nothing here, a rounded clip broke up once larger than the screen). A still picture
        // (grabToImage), not a live texture: that dropped out for a frame as the new wallpaper loaded under it
        Image {
            id: oldWallpaper
            anchors.fill: parent
            visible: bgRoot.revealActive && status === Image.Ready
            cache: false
            smooth: true
            opacity: 1 - bgRoot.revealProgress
            onStatusChanged: if (status === Image.Ready && bgRoot.revealArmed && !bgRoot.oldCaptured) captureDone.restart()
            transform: Scale {
                origin.x: bgRoot.revealCx
                origin.y: bgRoot.revealCy
                xScale: 1 + 0.05 * bgRoot.revealProgress
                yScale: xScale
            }
        }
    }
}
