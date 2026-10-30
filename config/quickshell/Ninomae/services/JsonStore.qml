import Quickshell
import Quickshell.Io
import QtQuick
/**
 * Reusable JSON file persistence, read and written in-process with atomic writes
 * (a crash mid-save can't truncate the file).
 *
 * Usage:
 *   JsonStore {
 *       id: myStore
 *       filePath: "/path/to/data.json"
 *       defaultValue: ({})       // or [] for arrays
 *       ensureDir: true          // mkdir -p the parent dir on startup
 *   }
 *
 * Properties:
 *   value     — the live JS value (object or array); bind to this for reads
 *   revision  — bumped on every data change; subscribe for reactive updates
 *
 * Signals:
 *   loaded()  — after each load() finished (the file read, or the default when there's none)
 *
 * Methods:
 *   load()    — read from disk (auto-called on Component.onCompleted)
 *   save()    — write current `value` to disk
 */
Item {
    id: root
    visible: false
    width: 0; height: 0
    required property string filePath
    property var defaultValue: ({})
    property bool ensureDir: true
    property bool autoLoad: true
    property var value: typeof defaultValue === "object" && Array.isArray(defaultValue)
                       ? [] : ({})
    property int revision: 0
    signal loaded()
    Component.onCompleted: {
        if (ensureDir)
            Quickshell.execDetached(["mkdir", "-p", filePath.replace(/\/[^/]*$/, "")]);
        if (autoLoad) load();
    }
    function load() {
        _loadRequested = true;
        if (_fileView.path === filePath) _fileView.reload();
        else _fileView.path = filePath;
    }
    function save() {
        _fileView.path = filePath;
        _fileView.setText(Array.isArray(root.value) ? JSON.stringify(root.value) : JSON.stringify(root.value, null, 2));
    }
    // Convenience: update data, bump revision, and save in one call.
    function commit(newData) {
        root.value = newData;
        root.revision = Date.now();
        save();
    }
    // ── Internal ──────────────────────────────────────────────────
    // Only react to loads we asked for, so our own saves don't loop back as reloads
    property bool _loadRequested: false
    function _setDefault() {
        root.value = typeof root.defaultValue === "object"
            ? JSON.parse(JSON.stringify(root.defaultValue))
            : root.defaultValue;
    }
    FileView {
        id: _fileView
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (!root._loadRequested) return;
            root._loadRequested = false;
            try {
                root.value = JSON.parse(text());
            } catch (e) {
                console.warn("JsonStore: failed to parse", root.filePath, e);
                root._setDefault();
            }
            root.revision = Date.now();
            root.loaded();
        }
        onLoadFailed: error => {
            if (!root._loadRequested) return;
            root._loadRequested = false;
            if (error !== FileViewError.FileNotFound)
                console.warn("JsonStore: failed to load", root.filePath, FileViewError.toString(error));
            root._setDefault();
            root.revision = Date.now();
            root.loaded();
        }
    }
}
