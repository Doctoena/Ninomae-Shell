pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

/**
 * Your changes to the shortcuts (Settings → Keybinds), kept in ~/.config/ninomae-shell/keybinds.json, which git
 * ignores like config.json. keybinds.lua reads them as Lua: this writes ~/.local/state/quickshell/user/keybinds.lua
 * and reloads Hyprland, only when that file would change. Binds are never added or removed at runtime (through
 * hyprctl eval that crashed Hyprland): a reload builds them all afresh.
 *   changed: { "Category: What it does": "SUPER + K" (new keys) or false (turned off) }
 *   added:   [ { name, command, keys } ], your own shortcuts that run a command
 */
Singleton {
    id: root
    readonly property string jsonPath: `${Directories.shellConfig}/keybinds.json`
    readonly property string luaPath: FileUtils.trimFileProtocol(`${Directories.state}/user/keybinds.lua`)
    property var changed: ({})
    property var added: []
    property bool loaded: false
    function load() {} // Referenced from shell.qml, so the Lua file is made on a machine that only has the JSON

    function setKeys(description, keys) { const c = Object.assign({}, root.changed); c[description] = keys; root.save(c, root.added); }
    function turnOff(description) { root.setKeys(description, false); }
    function reset(description) { const c = Object.assign({}, root.changed); delete c[description]; root.save(c, root.added); }
    function addShortcut(name, command, keys) { root.save(root.changed, root.added.concat([{ name: name, command: command, keys: keys }])); }
    function setShortcutKeys(index, keys) { const a = root.added.slice(); a[index] = Object.assign({}, a[index], { keys: keys }); root.save(root.changed, a); }
    function removeShortcut(index) { const a = root.added.slice(); a.splice(index, 1); root.save(root.changed, a); }
    function save(changed, added) {
        root.changed = changed;
        root.added = added;
        jsonFile.setText(JSON.stringify({ changed: changed, added: added }, null, 2) + "\n");
        root.writeLua();
    }

    // Recording a shortcut: an empty submap, so keys that already have a bind reach Settings instead of running
    // (keybinds.lua defines it, with Escape to leave)
    function startCapture() { Hyprland.dispatch('hl.dsp.submap("ninomae_capture")'); }
    function stopCapture() { Hyprland.dispatch('hl.dsp.submap("global")'); }

    FileView {
        id: jsonFile
        path: root.jsonPath
        watchChanges: true
        printErrors: false // No file yet is normal: nothing changed
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.changed = (data.changed && typeof data.changed === "object") ? data.changed : {};
                root.added = Array.isArray(data.added) ? data.added : [];
            } catch (e) { console.warn("[KeybindOverrides] keybinds.json unreadable:", e); }
            root.loaded = true;
            root.writeLua();
        }
        onLoadFailed: { root.changed = {}; root.added = []; root.loaded = true; root.writeLua(); } // No file: nothing changed
    }

    function luaString(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'; }
    property bool luaPending: false // Changed again while the last write ran: write once more after it
    function writeLua() {
        if (luaWriter.running) { root.luaPending = true; return; }
        const changedLines = Object.keys(root.changed).map(d => `        [${luaString(d)}] = ${root.changed[d] === false ? "false" : luaString(root.changed[d])},`);
        const addedLines = root.added.filter(b => b.keys && b.command)
            .map(b => `        { keys = ${luaString(b.keys)}, command = ${luaString(b.command)}, name = ${luaString(b.name || b.command)} },`);
        const empty = changedLines.length === 0 && addedLines.length === 0;
        // No trailing newline: the compare below reads the file back through $(…), which drops one
        const lua = empty ? "" : ["-- Written by the shell from ~/.config/ninomae-shell/keybinds.json. Change them in Settings → Keybinds",
            "return {", "    changed = {", ...changedLines, "    },", "    added = {", ...addedLines, "    },", "}"].join("\n");
        luaWriter.command = ["bash", "-c", '[ "$(cat -- "$1" 2>/dev/null)" = "$2" ] && exit 0; mkdir -p -- "$(dirname -- "$1")" && printf "%s" "$2" > "$1" && hyprctl reload >/dev/null',
            "keybinds", root.luaPath, lua];
        luaWriter.running = true;
    }
    Process {
        id: luaWriter
        onExited: if (root.luaPending) { root.luaPending = false; root.writeLua(); }
    }
}
