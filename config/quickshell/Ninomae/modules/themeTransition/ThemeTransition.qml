import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
// Smooth theme change, driven by switchwall.sh. Nothing is frozen or screenshotted:
//  1. `prepare`: the shell keeps its current colours while the new ones are generated (MaterialThemeLoader.hold
//     + GlobalStates.themeHold). The background snapshots its wallpaper and loads the new one under it meanwhile.
//  2. `reveal <x> <y>`: both are let go at once. The background fades its snapshot of the old wallpaper
//     off the new one, zooming in a touch from the cursor (modules/background), and every shell colour fades to its new value
//     (Appearance.colorFade). A light/dark switch has no new wallpaper, so it's just the colour fade.
Scope {
    id: root

    function prepare() {
        MaterialThemeLoader.hold = true;
        GlobalStates.themeHold = true;
        holdSafety.restart();
    }
    function reveal(x, y) {
        GlobalStates.themeRevealX = x;
        GlobalStates.themeRevealY = y;
        GlobalStates.themeRevealSerial++; // The background captures the old wallpaper now…
        releaseTimer.restart();           // …and the new look is let go a couple of frames later
    }
    function releaseHold() {
        holdSafety.stop();
        Appearance.colorFade = true;
        GlobalStates.themeHold = false;
        MaterialThemeLoader.release();
        fadeOff.restart();
    }

    Timer {
        id: releaseTimer
        interval: 40
        onTriggered: root.releaseHold()
    }
    Timer { // Colour changes outside a transition stay instant
        id: fadeOff
        interval: 1000 // Past the 800 ms fade
        onTriggered: Appearance.colorFade = false
    }
    Timer { // switchwall.sh never got to `reveal` (error, cancelled): don't keep the old look forever
        id: holdSafety
        interval: 15000
        onTriggered: root.releaseHold()
    }

    IpcHandler {
        target: "themeTransition"
        function prepare(): void { root.prepare(); }
        function reveal(x: real, y: real): void { root.reveal(x, y); }
        function cancel(): void { root.releaseHold(); }
    }
}
