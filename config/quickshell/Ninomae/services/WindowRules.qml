pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Every window rule (Settings → Window rules), in ~/.config/ninomae-shell/window-rules.json, which git ignores like
 * config.json. The first time it's a copy of the shipped window-rules.default.json. Hyprland reads them as Lua: this
 * writes ~/.local/state/quickshell/user/window_rules.lua (hypr/hyprland/Windowrules.lua loads it) and reloads
 * Hyprland, only when that file would change.
 * A rule: { name, note, enabled, match: { class, title, xwayland, float… }, effects: { float, opacity, size… } }.
 * match and effects are Hyprland's own fields (patterns are regular expressions), so anything Settings doesn't
 * show a control for is kept as it is.
 */
Singleton {
    id: root
    readonly property string jsonPath: `${Directories.shellConfig}/window-rules.json`
    readonly property string defaultsPath: `${Directories.shellConfig}/window-rules.default.json`
    readonly property string luaPath: FileUtils.trimFileProtocol(`${Directories.state}/user/window_rules.lua`)
    property var rules: []
    property bool loaded: false
    function load() {} // Referenced from shell.qml, so the Lua file is made on a machine that only has the JSON

    function save(list) {
        root.rules = list;
        jsonFile.setText(JSON.stringify(list, null, 2) + "\n");
        root.writeLua();
    }
    function add(rule) { root.save(root.rules.concat([rule])); }
    function replace(index, rule) { const list = root.rules.slice(); list[index] = rule; root.save(list); }
    function remove(index) { const list = root.rules.slice(); list.splice(index, 1); root.save(list); }
    function setEnabled(index, on) { root.replace(index, Object.assign({}, root.rules[index], { enabled: on })); }

    FileView {
        id: jsonFile
        path: root.jsonPath
        watchChanges: true
        printErrors: false // No file yet: it's made from the defaults
        onFileChanged: reload()
        onLoaded: {
            try { const list = JSON.parse(text()); root.rules = Array.isArray(list) ? list : []; }
            catch (e) { console.warn("[WindowRules] window-rules.json unreadable:", e); return; } // Leave Hyprland's rules alone
            root.loaded = true;
            root.writeLua();
        }
        onLoadFailed: firstCopy.running = true
    }
    Process { // The first time: start from the shipped rules
        id: firstCopy
        command: ["cp", "-n", root.defaultsPath, root.jsonPath]
        onExited: (code, status) => {
            if (code === 0) jsonFile.reload();
            else { root.rules = []; root.loaded = true; root.writeLua(); }
        }
    }

    // ── Lua ──
    function luaString(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'; }
    function luaValue(v) { return typeof v === "boolean" ? String(v) : typeof v === "number" ? String(v) : root.luaString(v); }
    function luaFields(obj) {
        return Object.keys(obj ?? {}).filter(k => /^[a-z_]+$/.test(k) && obj[k] !== null && obj[k] !== undefined && obj[k] !== "")
            .map(k => `${k} = ${root.luaValue(obj[k])}`);
    }
    function ruleLua(rule, index) {
        const match = root.luaFields(rule.match);
        const effects = root.luaFields(rule.effects);
        if (rule.enabled === false || match.length === 0 || effects.length === 0) return "";
        const name = rule.name || `rule-${index + 1}`;
        // Each in its own pcall: a rule Hyprland rejects doesn't take the others with it
        return `pcall(hl.window_rule, { name = ${root.luaString(name)}, match = { ${match.join(", ")} }, ${effects.join(", ")} })`;
    }
    function writeLua() {
        const lines = root.rules.map(root.ruleLua).filter(l => l !== "");
        // No trailing newline: the compare below reads the file back through $(…), which drops one
        const lua = lines.length === 0 ? "" : ["-- Written by the shell from ~/.config/ninomae-shell/window-rules.json. Change them in Settings → Window rules"].concat(lines).join("\n");
        luaWriter.command = ["bash", "-c", '[ "$(cat -- "$1" 2>/dev/null)" = "$2" ] && exit 0; mkdir -p -- "$(dirname -- "$1")" && printf "%s" "$2" > "$1" && hyprctl reload >/dev/null',
            "window-rules", root.luaPath, lua];
        luaWriter.running = true;
    }
    Process { id: luaWriter }
}
