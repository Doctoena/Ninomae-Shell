import QtQuick
import QtQuick.Window

/**
 * Tells a drawer when its window is really on screen, so the slide-out can start.
 * A layer window is mapped a few frames after it's made visible, and an animation started before
 * then plays out unseen (the drawer just appears). `ready` turns true after 3 presented frames, or
 * after 150 ms at the latest, and back to false when `active` does (put it in the drawer's window,
 * with `active` bound to the window being shown).
 */
Item {
    id: root
    property bool active: true
    property bool ready: false
    property int presentedFrames: 0
    onActiveChanged: if (!active) { ready = false; presentedFrames = 0; }

    Connections {
        target: root.Window.window
        enabled: root.active && !root.ready
        function onFrameSwapped() {
            root.presentedFrames++;
            if (root.presentedFrames >= 3) root.ready = true;
        }
    }
    FrameAnimation { running: root.active && !root.ready } // Qt only renders on change: keep frames coming
    Timer { interval: 150; running: root.active && !root.ready; onTriggered: root.ready = true } // Safety net
}
