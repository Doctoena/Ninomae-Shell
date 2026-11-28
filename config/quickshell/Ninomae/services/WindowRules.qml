pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Every window rule (Settings → Window rules). The shipped ones are always read from window-rules.default.json, so
 * an update brings new and fixed ones in. ~/.config/ninomae-shell/window-rules.json (git ignores it, like
 * config.json) only keeps what you changed, like keybinds.json:
 *   changed: { "<shipped rule's name>": the rule as you edited it }
 *   removed: [ "<shipped rule's name>", … ]
 *   added:   [ your own rules ]
 * `rules` is the list in effect: the shipped ones in order (yours where you edited them), then your own, which so
 * come last and win where they overlap. Hyprland reads them as Lua: this writes
 * ~/.local/state/quickshell/user/window_rules.lua (hypr/hyprland/Windowrules.lua loads it) and reloads Hyprland,
 * only when that file would change.
 * A rule: { name, note, enabled, match: { class, title, xwayland, float… }, effects: { float, opacity, size… } }.
 * match and effects are Hyprland's own fields (patterns are regular expressions), so anything Settings doesn't
 * show a control for is kept as it is.
 */
Singleton {
    id: root
    readonly property string jsonPath: `${Directories.shellConfig}/window-rules.json`
    readonly property string defaultsPath: `${Directories.shellConfig}/window-rules.default.json`
    readonly property string luaPath: FileUtils.trimFileProtocol(`${Directories.state}/user/window_rules.lua`)
    property var defaults: []
    property var changed: ({})
    property var removed: []
    property var added: []
    property bool defaultsLoaded: false
    property bool userLoaded: false
    property var pendingOld: null // An old-style list read before the shipped rules: migrated once they're in
    readonly property bool loaded: defaultsLoaded && userLoaded
    // The rules in effect, and where each came from: { shipped: name } or { added: index into `added` }
    readonly property var merged: {
        const rules = [], origins = [];
        for (const d of root.defaults) {
            if (root.removed.includes(d.name)) continue;
            rules.push(root.changed[d.name] ?? d);
            origins.push({ shipped: d.name });
        }
        root.added.forEach((r, i) => { rules.push(r); origins.push({ added: i }); });
        return { rules: rules, origins: origins };
    }
    readonly property var rules: merged.rules
    onMergedChanged: if (root.loaded) root.writeLua()
    function load() {} // Referenced from shell.qml, so the Lua file is made on a machine that only has the JSON

    // ── Changing them (by index into `rules`) ──
    function isEdited(index) { // A shipped rule you changed
        const name = root.merged.origins[index]?.shipped;
        return name !== undefined && root.changed[name] !== undefined;
    }
    function add(rule) { root.save(root.changed, root.removed, root.added.concat([rule])); }
    function replace(index, rule) {
        const origin = root.merged.origins[index];
        if (origin?.shipped !== undefined) {
            const c = Object.assign({}, root.changed);
            const shipped = root.defaults.find(d => d.name === origin.shipped);
            if (root.same(rule, shipped)) delete c[origin.shipped]; // Back as shipped: nothing to keep
            else c[origin.shipped] = rule;
            root.save(c, root.removed, root.added);
        } else if (origin?.added !== undefined) {
            const a = root.added.slice(); a[origin.added] = rule;
            root.save(root.changed, root.removed, a);
        }
    }
    function remove(index) {
        const origin = root.merged.origins[index];
        if (origin?.shipped !== undefined) {
            const c = Object.assign({}, root.changed); delete c[origin.shipped];
            root.save(c, root.removed.concat([origin.shipped]), root.added);
        } else if (origin?.added !== undefined) {
            const a = root.added.slice(); a.splice(origin.added, 1);
            root.save(root.changed, root.removed, a);
        }
    }
    function setEnabled(index, on) { root.replace(index, Object.assign({}, root.rules[index], { enabled: on })); }
    function restore(index) { // A shipped rule you edited, back as shipped
        const name = root.merged.origins[index]?.shipped;
        if (name === undefined) return;
        const c = Object.assign({}, root.changed); delete c[name];
        root.save(c, root.removed, root.added);
    }

    // Same rule, whatever the order of its fields
    function canonical(v) {
        if (Array.isArray(v)) return v.map(root.canonical);
        if (v && typeof v === "object") return Object.keys(v).sort().reduce((o, k) => { o[k] = root.canonical(v[k]); return o; }, {});
        return v;
    }
    function same(a, b) { return JSON.stringify(root.canonical(a)) === JSON.stringify(root.canonical(b)); }

    function save(changed, removed, added) {
        root.changed = changed;
        root.removed = removed;
        root.added = added;
        jsonFile.setText(JSON.stringify({ changed: changed, removed: removed, added: added }, null, 2) + "\n");
    }
    // The old window-rules.json was a full copy of the shipped rules, taken once, so later ones never reached it.
    // Kept: your own rules and your edits. Shipped rules it doesn't have come in (they're likely newer than the copy)
    function migrate(list) {
        const c = {}, a = [];
        for (const r of list) {
            const shipped = root.defaults.find(d => d.name === r.name);
            if (!shipped) a.push(r);
            else if (!root.same(r, shipped)) c[r.name] = r;
        }
        const brought = root.defaults.filter(d => !list.some(r => r.name === d.name)).map(d => d.name);
        if (brought.length > 0) console.info("[WindowRules] Shipped rules your copy didn't have, now in effect:", brought.join(", "));
        root.save(c, [], a);
    }

    FileView {
        id: defaultsFile
        path: root.defaultsPath
        watchChanges: true // An update (git pull) changes them
        onFileChanged: reload()
        onLoaded: {
            try { const list = JSON.parse(text()); root.defaults = Array.isArray(list) ? list : []; }
            catch (e) { console.warn("[WindowRules] window-rules.default.json unreadable:", e); }
            root.defaultsLoaded = true;
            if (root.pendingOld) { root.migrate(root.pendingOld); root.pendingOld = null; }
        }
        onLoadFailed: root.defaultsLoaded = true
    }
    FileView {
        id: jsonFile
        path: root.jsonPath
        watchChanges: true
        printErrors: false // No file yet: nothing changed
        onFileChanged: reload()
        onLoaded: {
            let data;
            try { data = JSON.parse(text()); }
            catch (e) { console.warn("[WindowRules] window-rules.json unreadable:", e); return; } // Leave Hyprland's rules alone
            if (Array.isArray(data)) {
                if (root.defaultsLoaded) root.migrate(data); else root.pendingOld = data;
            } else {
                root.changed = (data.changed && typeof data.changed === "object") ? data.changed : {};
                root.removed = Array.isArray(data.removed) ? data.removed : [];
                root.added = Array.isArray(data.added) ? data.added : [];
            }
            root.userLoaded = true;
        }
        onLoadFailed: root.userLoaded = true // No file: the shipped rules as they are
    }
    onLoadedChanged: if (root.loaded) root.writeLua()

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
    property bool luaPending: false // Changed again while the last write ran: write once more after it
    function writeLua() {
        if (luaWriter.running) { root.luaPending = true; return; }
        const lines = root.rules.map(root.ruleLua).filter(l => l !== "");
        // No trailing newline: the compare below reads the file back through $(…), which drops one
        const lua = lines.length === 0 ? "" : ["-- Written by the shell from window-rules.default.json and your changes in window-rules.json. Change them in Settings → Window rules"].concat(lines).join("\n");
        luaWriter.command = ["bash", "-c", '[ "$(cat -- "$1" 2>/dev/null)" = "$2" ] && exit 0; mkdir -p -- "$(dirname -- "$1")" && printf "%s" "$2" > "$1" && hyprctl reload >/dev/null',
            "window-rules", root.luaPath, lua];
        luaWriter.running = true;
    }
    Process {
        id: luaWriter
        onExited: if (root.luaPending) { root.luaPending = false; root.writeLua(); }
    }
}
