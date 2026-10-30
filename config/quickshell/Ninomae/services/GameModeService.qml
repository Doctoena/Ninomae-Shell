pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Game mode: turns off Hyprland's animations, blur, shadows, rounding and gaps.
 * The values it replaces are read first and put back when it's turned off, so anything else set at
 * runtime survives (it used to `hyprctl reload`). Only if the shell restarted in between, and the
 * saved values are gone, does turning it off fall back to a reload.
 */
Singleton {
    id: root
    property bool active: false
    property var saved: null // { option: value } from before game mode, null when unknown

    // Option → where it goes in hl.config, and the game mode value
    readonly property var options: [
        { name: "animations:enabled", path: ["animations", "enabled"], value: false },
        { name: "decoration:shadow:enabled", path: ["decoration", "shadow", "enabled"], value: false },
        { name: "decoration:blur:enabled", path: ["decoration", "blur", "enabled"], value: false },
        { name: "decoration:rounding", path: ["decoration", "rounding"], value: 0 },
        { name: "general:gaps_in", path: ["general", "gaps_in"], value: 0 },
        { name: "general:gaps_out", path: ["general", "gaps_out"], value: 0 },
        { name: "general:border_size", path: ["general", "border_size"], value: 1 },
        { name: "general:allow_tearing", path: ["general", "allow_tearing"], value: true },
    ]

    function toggle() {
        if (root.active) disable();
        else enable();
    }
    function enable() {
        root.active = true;
        snapshotProc.running = true; // Applies game mode once the current values are read
    }
    function disable() {
        root.active = false;
        if (!root.saved) {
            Quickshell.execDetached(["hyprctl", "reload"]);
            return;
        }
        apply(root.saved);
        root.saved = null;
    }

    // { "a:b": v } → hl.config({ a = { b = v } })
    function luaValue(v) {
        if (typeof v === "boolean" || typeof v === "number") return String(v);
        return JSON.stringify(String(v)); // A JSON string is a valid Lua string literal here
    }
    function apply(values) {
        const tree = {};
        for (const opt of root.options) {
            if (!(opt.name in values)) continue;
            let node = tree;
            for (const key of opt.path.slice(0, -1)) {
                if (!node[key]) node[key] = {};
                node = node[key];
            }
            node[opt.path[opt.path.length - 1]] = values[opt.name];
        }
        const toLua = node => typeof node === "object"
            ? `{ ${Object.entries(node).map(([k, v]) => `${k} = ${toLua(v)}`).join(", ")} }`
            : luaValue(node);
        Quickshell.execDetached(["hyprctl", "eval", `hl.config(${toLua(tree)})`]);
    }
    function gameModeValues() {
        const values = {};
        for (const opt of root.options) values[opt.name] = opt.value;
        return values;
    }

    Process {
        id: snapshotProc
        command: ["hyprctl", "-j", "--batch", root.options.map(o => `getoption ${o.name}`).join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const values = {};
                try {
                    for (const part of text.split("\n\n\n")) {
                        if (part.trim().length === 0) continue;
                        const o = JSON.parse(part);
                        if ("bool" in o) values[o.option] = o.bool;
                        else if ("int" in o) values[o.option] = o.int;
                        else if ("float" in o) values[o.option] = o.float;
                        else if ("css" in o) {
                            // "4 4 4 4": one number when all sides match, otherwise the full string
                            const sides = o.css.trim().split(/\s+/);
                            values[o.option] = sides.every(s => s === sides[0]) ? Number(sides[0]) : o.css.trim();
                        }
                    }
                } catch (e) {
                    console.warn("[GameMode] Couldn't read the current Hyprland options:", e);
                }
                root.saved = Object.keys(values).length === root.options.length ? values : null;
                if (root.active) root.apply(root.gameModeValues());
            }
        }
    }

    // On startup, game mode counts as on when animations are off (as the toggles always did)
    Process {
        running: true
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    root.active = !(o.bool ?? (o.int !== 0));
                } catch (e) {}
            }
        }
    }
}
