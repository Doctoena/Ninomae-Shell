pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Settings → Display and Settings → Input, applied to Hyprland with `hyprctl eval`. Like WindowLayout:
 * when the shell starts, when a setting changes, and after Hyprland reloads its config (which puts back
 * hypr/hyprland/monitors.lua and general.lua). Display settings are also applied to a monitor when it's
 * plugged in. Re-applying values Hyprland already has changes nothing on screen.
 */
Singleton {
    id: root

    // Lua literals: strings quoted (JSON's escaping is valid Lua for these), tables from objects
    function toLua(value) {
        if (typeof value === "string") return JSON.stringify(value);
        if (typeof value === "object") return `{ ${Object.entries(value).map(([k, v]) => `${k} = ${root.toLua(v)}`).join(", ")} }`;
        return String(value);
    }

    // ── Input ──
    readonly property string inputLua: {
        const i = Config.options.input;
        return `hl.config(${root.toLua({ input: {
            repeat_rate: i.keyboard.repeatRate,
            repeat_delay: i.keyboard.repeatDelay,
            numlock_by_default: i.keyboard.numlockByDefault,
            sensitivity: i.mouse.sensitivity,
            accel_profile: i.mouse.accelProfile,
            natural_scroll: i.mouse.naturalScroll,
            scroll_factor: i.mouse.scrollFactor,
            left_handed: i.mouse.leftHanded,
            touchpad: {
                tap_to_click: i.touchpad.tapToClick,
                natural_scroll: i.touchpad.naturalScroll,
                disable_while_typing: i.touchpad.disableWhileTyping,
                scroll_factor: i.touchpad.scrollFactor,
                clickfinger_behavior: i.touchpad.clickfinger,
                tap_and_drag: i.touchpad.tapAndDrag,
            },
        } })})`;
    }
    function applyInput() {
        if (Config.ready) Quickshell.execDetached(["hyprctl", "eval", root.inputLua]);
    }
    // A settings change arrives as a whole config file reload, so many values change at once: apply once
    onInputLuaChanged: inputDebounce.restart()
    Timer { id: inputDebounce; interval: 150; onTriggered: root.applyInput() }

    // ── Display ──
    // displays.json (Directories.displaysPath): { "<monitor description>": { mode, scale, transform, vrr,
    // position, disabled, mirror: "<other description>" } }, only the fields changed in Settings. The rest stays as
    // hypr/hyprland/monitors.lua sets it (one rule for every screen, so this works on any machine)
    property var savedMonitors: ({})
    FileView {
        id: displaysFile
        path: Qt.resolvedUrl(Directories.displaysPath)
        watchChanges: true
        onFileChanged: displaysFile.reload()
        onLoaded: {
            try { root.savedMonitors = JSON.parse(displaysFile.text()) ?? {}; } catch (e) { root.savedMonitors = {}; }
            displayDebounce.restart();
        }
        onLoadFailed: root.savedMonitors = {} // No file yet: nothing changed in Settings
    }
    Timer { id: displayDebounce; interval: 150; onTriggered: root.applyDisplay() }
    function applyDisplay() {
        if (Object.keys(root.savedMonitors).length > 0) monitorsProc.running = true;
    }
    // Every field is sent (hl.monitor resets the ones left out): saved ones, the rest as they are now.
    // "all" includes screens that are off, so one turned off in Settings can be turned back on
    Process {
        id: monitorsProc
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                let monitors;
                try { monitors = JSON.parse(text); } catch (e) { return; }
                const calls = monitors.filter(m => root.savedMonitors[m.description]).map(m => {
                    const saved = root.savedMonitors[m.description];
                    if (saved.disabled) return `hl.monitor(${root.toLua({ output: m.name, disabled: true })})`;
                    // A screen that's off has no mode or place of its own yet: monitors.lua's defaults
                    const off = m.disabled;
                    const spec = {
                        output: m.name,
                        mode: saved.mode ?? (off ? "highres" : `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}`),
                        position: saved.position ?? (off ? "auto" : `${m.x}x${m.y}`),
                        scale: saved.scale ?? (off ? 1 : m.scale),
                        transform: saved.transform ?? (off ? 0 : m.transform),
                        vrr: saved.vrr ?? (m.vrr ? 1 : 0),
                    };
                    // Mirror: saved by the other screen's description, as port names differ between machines
                    const source = saved.mirror ? monitors.find(o => o.description === saved.mirror) : undefined;
                    if (source) spec.mirror = source.name;
                    return `hl.monitor(${root.toLua(spec)})`;
                });
                if (calls.length === 0) return;
                Quickshell.execDetached(["hyprctl", "eval", calls.join("\n")]);
            }
        }
    }

    function load() {
        root.applyInput();
        root.applyDisplay();
    }
    Connections {
        target: Config
        function onReadyChanged() { root.load(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.load();
            else if (event.name === "monitoradded" || event.name === "monitoraddedv2") root.applyDisplay();
        }
    }
}
