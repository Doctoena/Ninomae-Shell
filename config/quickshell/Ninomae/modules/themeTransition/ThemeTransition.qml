import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// Theme change (new wallpaper, light/dark, a new scheme), driven by switchwall.sh. The screen never freezes:
//  1. `prepare`: the shell's colours (MaterialThemeLoader.hold) and the wallpaper (modules/background) keep their
//     look while the new ones are worked out and loaded. Nothing else is applied yet, so all stays live.
//  2. `cover`: a still picture of every screen goes over everything; switchwall.sh waits for it (`ready`), then
//     applies the apps (GTK, Qt, kitty, VS Code, borders) and calls
//  3. `reveal <x> <y>`: the shell's colours change in one step (no per-colour fades, which stuttered), the new
//     wallpaper is let go, and the cover opens from the cursor in a soft circle at once. Apps repaint under it
//     in a fraction of a second, while the circle is still small.
// Without a picture (screen capture failed) the change is just instant.
Scope {
    id: root

    readonly property int duration: 750 // The circle's growth
    property bool covering: false       // The cover windows are up
    property int captured: 0            // Screens whose picture has arrived
    readonly property bool coverReady: covering && captured >= Quickshell.screens.length
    property real progress: 0           // The circle, 0 → 1

    function prepare() {
        MaterialThemeLoader.hold = true;
        GlobalStates.themeHold = true;
        holdSafety.restart();
    }
    function stage() { // The new colours, ahead of the rest (switchwall.sh): held till the reveal
        nextColors.reload();
        if (MaterialThemeLoader.hold) MaterialThemeLoader.pendingContent = nextColors.text();
    }
    function cover() {
        wipe.stop();
        progress = 0;
        captured = 0;
        covering = false; // A change mid-way through another: start again with a fresh picture
        covering = true;
        captureSafety.restart();
    }
    function reveal(x, y) {
        GlobalStates.themeRevealX = x;
        GlobalStates.themeRevealY = y;
        releaseHold();
    }
    function releaseHold() {
        holdSafety.stop();
        MaterialThemeLoader.release(); // The shell's new colours, in one step
        GlobalStates.themeHold = false; // And the new wallpaper
        if (coverReady) settle.restart(); // A moment for everything to repaint under the cover, then open
        else endCover();
    }
    function endCover() {
        wipe.stop();
        covering = false;
        captured = 0;
    }

    Timer { // The shell's colours have changed in one go: the next frames repaint it, then the circle opens
        id: settle
        interval: 90
        onTriggered: wipe.restart()
    }
    NumberAnimation {
        id: wipe
        target: root
        property: "progress"
        from: 0; to: 1
        duration: root.duration
        easing.type: Easing.InOutCubic
        onFinished: root.endCover()
    }
    Timer { // No picture came (no screen capture): drop the cover, the change will just be instant
        id: captureSafety
        interval: 500
        onTriggered: if (root.covering && !root.coverReady) root.endCover()
    }
    Timer { // switchwall.sh never got to `reveal` (error, cancelled): don't keep the old look forever
        id: holdSafety
        interval: 15000
        onTriggered: root.releaseHold()
    }

    FileView {
        id: nextColors
        path: Directories.generatedMaterialThemePath.replace(/colors\.json$/, "colors.next.json")
        blockLoading: true // stage() reads it straight after asking
        printErrors: false
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: cover
            required property var modelData
            screen: modelData
            visible: root.covering
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:themeTransition" // no_anim in Hyprland's layer rules
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {} // Clicks go through to what's under it
            // Where the circle grows from, on this screen, and how far it has to go to clear its farthest corner
            readonly property real cx: GlobalStates.themeRevealX - modelData.x
            readonly property real cy: GlobalStates.themeRevealY - modelData.y
            readonly property real reach: Math.max(Math.hypot(cx, cy), Math.hypot(width - cx, cy),
                Math.hypot(cx, height - cy), Math.hypot(width - cx, height - cy))

            Loader { // Made afresh for each change, so it takes a new picture
                id: shot
                anchors.fill: parent
                active: root.covering
                sourceComponent: ScreencopyView {
                    captureSource: cover.modelData
                    live: false
                    onHasContentChanged: if (hasContent) root.captured++
                }
            }
            ShaderEffect {
                anchors.fill: parent
                visible: shot.item?.hasContent ?? false
                readonly property real feather: 180
                // The picture, drawn only through the circle (hideSource). Live: it arrives after this is made
                property var source: ShaderEffectSource { sourceItem: shot.item; hideSource: true }
                property point center: Qt.point(cover.cx, cover.cy)
                property size size: Qt.size(width, height)
                property real radius: root.progress * (cover.reach + feather)
                fragmentShader: Qt.resolvedUrl("shaders/circleReveal.frag.qsb")
            }
        }
    }

    IpcHandler {
        target: "themeTransition"
        function prepare(): void { root.prepare(); }
        function stage(): void { root.stage(); }
        function cover(): void { root.cover(); }
        function ready(): bool { return root.coverReady || !root.covering; } // switchwall.sh waits on this
        function reveal(x: real, y: real): void { root.reveal(x, y); }
        function cancel(): void { root.releaseHold(); }
    }
}
