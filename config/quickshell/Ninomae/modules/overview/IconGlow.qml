import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The most vivid colour in each result's icon, for its card's tint and halo (the accent for grey icons, no icon,
 * or the shell's own entries). Worked out once per icon and remembered: the rows ask as they're built, so a
 * card already has its colour when it grows. One icon at a time goes through the quantizer (a queue).
 * Icon files are found by a short shell lookup (ColorQuantizer can't read `image://icon/…`).
 */
Item {
    id: root
    property var colours: ({}) // icon name → its colour, or null for "use the accent"
    property var iconFiles: ({}) // icon name → its file, "" when none was found
    property var queue: []
    property string current: "" // The icon in the quantizer now

    function colourFor(name) {
        return (name !== "" && root.colours[name]) ? root.colours[name] : Appearance.colors.colPrimary;
    }
    function request(name) {
        if (name === "" || root.colours[name] !== undefined || root.queue.includes(name) || root.current === name) return;
        root.queue.push(name);
        pump();
    }
    function remember(name, colour) {
        root.colours = Object.assign({}, root.colours, { [name]: colour });
        root.current = "";
        pump();
    }
    function pump() {
        if (root.current !== "" || root.queue.length === 0) return;
        root.current = root.queue.shift();
        const name = root.current;
        if (name.startsWith("/")) quantize(name);
        else if (root.iconFiles[name] !== undefined) quantize(root.iconFiles[name]);
        else lookupComp.createObject(root, { name: name }).running = true;
    }
    function quantize(file) {
        if (file === "") { remember(root.current, null); return; }
        if (quantizer.source === "file://" + file) { pick(); return; } // Same file as the last one: no change signal
        quantizer.source = "file://" + file;
    }
    function pick() {
        let best = null, bestScore = 0.12; // Below this it's grey or black: the accent
        for (const c of (quantizer.colors ?? [])) {
            const score = c.hsvSaturation * c.hsvValue;
            if (score > bestScore) { bestScore = score; best = c; }
        }
        remember(root.current, best);
    }
    Component {
        id: lookupComp
        Process {
            id: lookup
            required property string name
            // The icon theme and the themes it inherits from first, then hicolor (system, Flatpak, your own) and
            // pixmaps; the name goes in as an argument, never into the script. In this template string a bash \(
            // has to be written \\( (the string would turn \( into a bare bracket, a syntax error for bash)
            command: ["bash", "-c", `n=$1
theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
themes=$theme
for t in "$HOME/.local/share/icons/$theme" "/usr/share/icons/$theme"; do # And the themes it inherits from
  [ -f "$t/index.theme" ] && themes="$themes $(sed -n 's/^Inherits=//p' "$t/index.theme" | tr ',' ' ')"
done
for th in $themes; do [ "$th" = hicolor ] && continue
  for t in "$HOME/.local/share/icons/$th" "/usr/share/icons/$th"; do
    [ -d "$t" ] && f=$(find -L "$t" -path "*apps*" \\( -name "$n.svg" -o -name "$n.png" \\) -print -quit 2>/dev/null) && [ -n "$f" ] && { echo "$f"; exit; }
  done
done
for d in "$HOME/.local/share/icons/hicolor" "$HOME/.local/share/flatpak/exports/share/icons/hicolor" /var/lib/flatpak/exports/share/icons/hicolor /usr/share/icons/hicolor; do
  for s in scalable 512x512 256x256 128x128 64x64 48x48; do for e in svg png; do [ -f "$d/$s/apps/$n.$e" ] && { echo "$d/$s/apps/$n.$e"; exit; }; done; done
done
for e in svg png; do [ -f "/usr/share/pixmaps/$n.$e" ] && { echo "/usr/share/pixmaps/$n.$e"; exit; }; done`, "icon-lookup", lookup.name]
            stdout: StdioCollector {
                onStreamFinished: {
                    const file = text.trim();
                    root.iconFiles = Object.assign({}, root.iconFiles, { [lookup.name]: file });
                    if (root.current === lookup.name) root.quantize(file);
                    lookup.destroy(); // Once its output is read: on exit it could still be on its way
                }
            }
        }
    }
    ColorQuantizer {
        id: quantizer
        depth: 2 // Four colours
        rescaleSize: 32
        onColorsChanged: if (root.current !== "") root.pick()
    }
}
