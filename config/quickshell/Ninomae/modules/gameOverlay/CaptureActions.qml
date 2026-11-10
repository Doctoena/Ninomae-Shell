import QtQuick
import Quickshell
import Quickshell.Io

// What can be done with a capture (a clip or a screenshot), for the overlay's Captures panel and its viewer:
// copy it (a clip as a file, a screenshot as a PNG picture), open it in its app, move it to the Trash.
// copiedPath is the one just copied, for a moment, so its button can show a tick
Item {
    id: root
    property string copiedPath: ""
    signal trashed(string path)
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedPath = "" }
    function copy(capture) {
        if (!capture) return;
        copier.running = false;
        copier.path = capture.path;
        copier.command = capture.kind === "clip"
            ? ["bash", "-c", 'printf "file://%s\\n" "$0" | wl-copy --type text/uri-list', capture.path]
            // As PNG: Chromium/Electron apps (Vesktop, browsers) only paste image/png, and Steam saves JPEGs
            : ["bash", "-o", "pipefail", "-c", 'case "${0,,}" in *.png) wl-copy --type image/png < "$0" ;; *) magick "$0" png:- | wl-copy --type image/png ;; esac', capture.path];
        copier.running = true;
    }
    Process {
        id: copier
        property string path
        onExited: exitCode => { if (exitCode === 0) { root.copiedPath = copier.path; copiedTimer.restart(); } }
    }
    function open(capture) {
        if (capture) Quickshell.execDetached(["xdg-open", capture.path]);
    }
    function trash(capture) { // To the Trash, so it can be got back
        if (!capture) return;
        Quickshell.execDetached(["gio", "trash", "--", capture.path]);
        root.trashed(capture.path);
    }
}
