pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "wtype -M ctrl v -m ctrl" // wtype: no daemon needed (ydotool needed ydotoold, which was never running)
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }
        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }
    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }
    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }
    // Entries reach the scripts as arguments ("$1"…), never as script text: printf '%s' keeps a '%' in
    // copied text from being read as a format, and quotes in it can't break out of the command
    // Shell snippet that decodes the entry in variable $e with the binary in $bin
    function decodeCommand(): string {
        return root.cliphistBinary.includes("cliphist")
            ? `printf '%s' "$e" | "$bin" decode` // Classic cliphist decodes the whole line
            : `"$bin" decode "\${e%%$'\\t'*}"`; // Stash decodes by entry number (before the tab)
    }
    function copy(entry) {
        Quickshell.execDetached(["bash", "-c", `bin="$0" e="$1"; ${root.decodeCommand()} | wl-copy`, root.cliphistBinary, entry]);
    }
    function paste(entry) {
        Quickshell.execDetached(["bash", "-c", `bin="$0" e="$1"; ${root.decodeCommand()} | wl-copy && sleep "$2" && ${root.pressPasteCommand}`,
            root.cliphistBinary, entry, String(root.pasteDelay)]);
    }
    function superpaste(count, isImage = false) {
        // Oldest first, so they end up pasted in their original order
        const targetEntries = entries.filter(entry => !isImage || entryIsImage(entry)).slice(0, count).reverse();
        const script = `bin="$0" delay="$1"; shift
            for e in "$@"; do ${root.decodeCommand()} | wl-copy && sleep "$delay" && ${root.pressPasteCommand} && sleep "$delay" || exit 1; done`;
        Quickshell.execDetached(["bash", "-c", script, root.cliphistBinary, String(root.pasteDelay), ...targetEntries]);
    }
    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `printf '%s\\n' "$1" | "$0" delete`, root.cliphistBinary, deleteProc.entry]
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.running = true;
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }
    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }
    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }
    function wipe() {
        wipeProc.running = true;
    }
    // History is only read when it's about to be shown (the launcher opening), not on every copy:
    // copying used to refresh twice (clipboard change + the IPC call from the wl-paste watcher)
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) root.refresh()
        }
    }
    Process {
        id: readProc
        property list<string> buffer: []
        command: [root.cliphistBinary, "list"]
        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }
    IpcHandler {
        target: "cliphistService"
        function update(): void {
            root.refresh()
        }
    }
}
