pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
/**
 * A service that provides access to Hyprland keybinds.
 *
 * Hyprland 0.55+ (Lua config): keybinds are no longer read by parsing
 * keybinds.conf. Instead they come from `hyprctl binds -j`, using each bind's
 * `description` (set in keybinds.lua). Descriptions in the form
 * "Category: text" are grouped into a section named "Category".
 * Binds with no description, or one starting with "[hidden]", are skipped.
 *
 * Output shape (used by the Keybinds settings page):
 * { children: [ { children: [ { name, keybinds: [ { mods, key, comment } ] } ] } ] }
 */
Singleton {
    id: root
    property int columnCount: 2
    property var keybinds: ({ "children": [] })
    property var codes: ({}) // Description → keycode, for binds made with "code:NN"
    property var raw: [] // Every bind as hyprctl gives it, hidden ones too: Settings checks a new shortcut against these

    function modsFromMask(mask) {
        const mods = []
        if (mask & 64) mods.push("Super")
        if (mask & 4) mods.push("Ctrl")
        if (mask & 8) mods.push("Alt")
        if (mask & 1) mods.push("Shift")
        return mods
    }

    function keyName(bind) {
        if (bind.key && bind.key.length > 0) return bind.key
        if (bind.keycode >= 272) return `mouse:${bind.keycode}`
        // The workspace keys are bound by position (keybinds.lua "code:" loops), so they come with no key:
        // the description says which
        if ((bind.description ?? "").includes("1-10")) return "1–0"
        // Punctuation is bound by position away from US layouts (hypr/hyprland/keymap.lua): named as your layout
        // prints it. Hyprland's JSON gives these keycode 0, so the code comes from its plain-text list (codes)
        const code = bind.keycode || root.codes[bind.description ?? ""]
        return KeyboardLayout.labels[String(code)] ?? `code:${code}`
    }

    function buildTree(binds) {
        const sections = []
        const byName = {}
        for (const bind of binds) {
            const desc = bind.description ?? ""
            if (!bind.has_description || desc.length === 0 || desc.startsWith("[hidden]")) continue
            const sep = desc.indexOf(": ")
            const category = sep > 0 ? desc.substring(0, sep) : "General"
            const comment = sep > 0 ? desc.substring(sep + 2) : desc
            if (!byName[category]) {
                byName[category] = { "name": category, "keybinds": [] }
                sections.push(byName[category])
            }
            byName[category].keybinds.push({
                "mods": root.modsFromMask(bind.modmask),
                "key": root.keyName(bind),
                "comment": comment,
                "description": desc,
            })
        }
        // Spread sections over columns, balancing by number of keybinds
        const columns = []
        const sizes = []
        for (let i = 0; i < root.columnCount; i++) { columns.push({ "children": [] }); sizes.push(0) }
        for (const section of sections) {
            let target = 0
            for (let i = 1; i < sizes.length; i++) if (sizes[i] < sizes[target]) target = i
            columns[target].children.push(section)
            sizes[target] += section.keybinds.length + 2
        }
        return { "children": columns }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getKeybinds.running = true
            }
        }
    }
    Connections {
        target: KeyboardLayout
        function onLabelsChanged() { root.keybinds = root.buildTree(root.raw) }
    }
    Process {
        id: getKeybinds
        running: true
        // The JSON list, then the plain one (which keeps the "code:NN" of binds made by position)
        command: ["bash", "-c", 'hyprctl binds -j; printf "\\x1e"; hyprctl binds']
        stdout: StdioCollector {
            id: keybindCollector
            onStreamFinished: {
                try {
                    const [json, plain] = keybindCollector.text.split("\x1e")
                    const codes = {}
                    for (const block of (plain ?? "").split(/\n\s*\n/)) {
                        const code = block.match(/^\s*key: .*code:(\d+)\s*$/m)
                        const desc = block.match(/^\s*description: (.*)$/m)
                        if (code && desc && !(desc[1] in codes)) codes[desc[1]] = Number(code[1])
                    }
                    root.codes = codes
                    const binds = JSON.parse(json)
                    root.raw = binds
                    root.keybinds = root.buildTree(binds)
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}
