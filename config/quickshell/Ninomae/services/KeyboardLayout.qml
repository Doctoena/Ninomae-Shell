pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The keyboard layout, as hypr/hyprland/keyboard.lua sets it (Settings → Input changes it). Writing it reloads
 * Hyprland, which applies the layout and moves the shortcuts to match (keymap.lua). Also names the keys the
 * shortcuts bind by position on this layout (labels), and sets the login screen's layout with localectl.
 */
Singleton {
    id: root
    readonly property string path: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keyboard.lua`)
    property string layout: "us"
    property string variant: ""
    property var labels: ({}) // xkb keycode → the key as this layout prints it, for the punctuation binds
    property var layouts: [] // Every layout and its variants (loadLayouts())
    property string loginLayout: "" // The login screen's, as localectl gives it ("us" or "us:dvorak")
    readonly property string current: variant ? `${layout}:${variant}` : layout

    function field(text, name) {
        const m = text.match(new RegExp(`^\\s*${name}\\s*=\\s*"([^"]*)"`, "m"));
        return m ? m[1] : "";
    }
    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.layout = root.field(file.text(), "layout") || "us";
            root.variant = root.field(file.text(), "variant");
        }
        onLoadFailed: { root.layout = "us"; root.variant = ""; } // keyboard.default.lua's
    }

    function set(layout, variant) {
        if (layout === root.layout && variant === root.variant) return;
        if (!/^[\w-]+$/.test(layout) || !/^[\w-]*$/.test(variant)) return;
        const lua = `-- Keyboard layout, set in Settings → Input (keyboard.default.lua says what goes here)\n`
            + `return {\n    layout  = "${layout}",\n    variant = "${variant}",\n}\n`;
        // Written in place (">" keeps the file), then a reload applies the layout and rebinds the shortcuts
        writer.command = ["bash", "-c", 'printf "%s" "$2" > "$1" && hyprctl reload >/dev/null', "write", root.path, lua];
        writer.running = true;
    }
    Process { id: writer }

    // Plain US and Dvorak bind every key by name, so there's nothing to label (and no helper to start)
    onCurrentChanged: {
        labelsProc.running = false;
        if (root.layout === "us" && (root.variant === "" || root.variant === "dvorak")) { root.labels = {}; return; }
        labelsProc.command = ["python3", "-I", Quickshell.shellPath("scripts/keyboard/xkb_layouts.py"), "labels", root.layout, root.variant];
        labelsProc.running = true;
    }
    Process {
        id: labelsProc
        stdout: StdioCollector {
            onStreamFinished: { try { root.labels = JSON.parse(text); } catch (e) { root.labels = {}; } }
        }
    }

    function loadLayouts() {
        if (root.layouts.length === 0 && !listProc.running) listProc.running = true;
    }
    Process {
        id: listProc
        command: ["python3", "-I", Quickshell.shellPath("scripts/keyboard/xkb_layouts.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.layouts = JSON.parse(text); } catch (e) {} }
        }
    }

    // ── Login screen ──
    function refreshLogin() { loginProc.running = true; }
    Process {
        id: loginProc
        command: ["localectl", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const get = name => ((text.match(new RegExp(`X11 ${name}:\\s*(\\S+)`)) ?? [])[1] ?? "").split(",")[0];
                const layout = get("Layout"), variant = get("Variant");
                root.loginLayout = layout ? (variant ? `${layout}:${variant}` : layout) : "";
            }
        }
    }
    // localectl asks for your password (the shell's polkit prompt) and writes /etc/X11/xorg.conf.d/00-keyboard.conf,
    // which the login screen reads
    function setLoginScreen() {
        loginSetter.command = ["localectl", "set-x11-keymap", root.layout, "pc105", root.variant];
        loginSetter.running = true;
    }
    Process {
        id: loginSetter
        onExited: root.refreshLogin()
    }
}
