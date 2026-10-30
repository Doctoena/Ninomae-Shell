import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Settings search: an index of every option, read from the pages' own QML, so it never needs updating by hand.
 * Each `text:`, `title:` or `placeholderText:` given through Translation.tr() is an entry. Tooltips and choice
 * names are added to the entry before them as extra words to match. Keybinds come from Hyprland.
 *   results(query) → [{ page, label, where, keybind }] best first; `label` is what the page shows
 */
Item {
    id: root
    visible: false
    required property var pages // settings.qml's page list: { name, component }
    property var entries: [] // { page, label, section, words }

    Process {
        running: true
        command: ["bash", "-c", 'for f; do printf "\\x1e%s\\n" "$f"; cat -- "$f"; done', "settings-index",
            ...root.pages.map(p => Quickshell.shellPath(p.component))]
        stdout: StdioCollector {
            onStreamFinished: {
                const files = text.split("\x1e").slice(1);
                let all = [];
                files.forEach((file, i) => all = all.concat(root.parsePage(i, file)));
                root.entries = all;
            }
        }
    }

    function parsePage(page, source) {
        const found = [];
        let section = "";
        let sectionNext = false; // Just inside a ContentSection: its title is the section's name
        let tooltipNext = false; // Just inside a StyledToolTip: its text describes the entry before
        const tr = /(\w+)\s*:\s*Translation\.tr\(\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\)/g;
        for (const line of source.split("\n")) {
            if (/\bContentSection\s*\{/.test(line)) sectionNext = true;
            if (/\bStyledToolTip\s*\{/.test(line)) tooltipNext = true;
            tr.lastIndex = 0;
            let m;
            while ((m = tr.exec(line)) !== null) { // No String.matchAll in this JS engine
                const prop = m[1];
                const value = (m[2] ?? m[3]).replace(/\\n/g, " ").replace(/\\(.)/g, "$1");
                const last = found[found.length - 1];
                if (prop === "tooltip" || prop === "displayName" || (tooltipNext && prop === "text")) {
                    if (last) last.words += " " + value;
                    tooltipNext = false;
                    continue;
                }
                if (!["title", "text", "placeholderText", "mainText"].includes(prop)) continue;
                if (value.includes("%1") || value.length > 70) continue; // Filled in at run time, or a paragraph
                if (prop === "title" && sectionNext) {
                    section = value;
                    sectionNext = false;
                    found.push({ page, label: value, section: "", words: "" });
                } else {
                    found.push({ page, label: value, section, words: "" });
                }
            }
        }
        return found;
    }

    // Lower is better; -1 doesn't match
    function score(haystack, q) {
        const text = haystack.toLowerCase();
        if (text.startsWith(q)) return 0;
        if (text.includes(" " + q) || text.includes("(" + q)) return 1;
        if (text.includes(q)) return 2;
        return -1;
    }

    function results(query) {
        const q = query.trim().toLowerCase();
        if (q.length === 0) return [];
        const scored = [];
        for (const e of root.entries) {
            const label = Translation.tr(e.label);
            const section = e.section ? Translation.tr(e.section) : "";
            const pageName = root.pages[e.page].name;
            let s = root.score(label, q);
            if (s < 0) {
                const other = root.score([e.words ? Translation.tr(e.words) : "", section, pageName].join(" "), q);
                if (other >= 0) s = 3 + other;
            }
            if (s >= 0) scored.push({ s, page: e.page, label, where: section ? `${pageName} › ${section}` : pageName, keybind: false });
        }
        // Keybinds, by what they do
        const keybindsPage = root.pages.findIndex(p => p.component.endsWith("KeybindsConfig.qml"));
        for (const column of HyprlandKeybinds.keybinds.children ?? []) {
            for (const section of column.children ?? []) {
                for (const bind of section.keybinds ?? []) {
                    const s = root.score(bind.comment, q);
                    if (s >= 0) scored.push({ s: s + 0.5, page: keybindsPage, label: bind.comment,
                        where: `${root.pages[keybindsPage].name} › ${section.name}`, keybind: true });
                }
            }
        }
        scored.sort((a, b) => a.s - b.s);
        // The same label twice (a section and its switch, "Monochrome icons" on two pages): keep both only when they're in different places
        const seen = new Set();
        return scored.filter(r => {
            const key = r.label + "|" + r.where;
            if (seen.has(key)) return false;
            seen.add(key);
            return true;
        }).slice(0, 30);
    }
}
