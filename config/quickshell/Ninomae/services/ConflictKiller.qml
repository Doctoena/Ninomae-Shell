pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * At start, finds programs that take the tray (kded6) or notifications (mako, dunst) from the shell. Stops them
 * when Settings → Advanced says to, otherwise asks in killDialog.qml (NINOMAE_CONFLICTS names what it found).
 */
Singleton {
    id: root
    readonly property string dialogPath: FileUtils.trimFileProtocol(Quickshell.shellPath("killDialog.qml"))
    readonly property var programs: ({ trays: ["kded6"], notifications: ["mako", "dunst"] })
    readonly property var options: ({ trays: "autoKillTrays", notifications: "autoKillNotificationDaemons" })
    function load() {
        // dummy to force init
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) check.running = true
        }
    }
    Process {
        id: check
        // One line per kind, "kind pids"
        command: ["bash", "-c", Object.keys(root.programs).map(k => `echo "${k} $(pidof ${root.programs[k].join(" ")})"`).join(";")]
        stdout: StdioCollector {
            onStreamFinished: {
                const running = this.text.split("\n").map(l => l.trim().split(" ")).filter(w => w.length > 1).map(w => w[0]);
                const ask = [];
                for (const kind of running) {
                    if (Config.options.conflictKiller[root.options[kind]]) Quickshell.execDetached(["killall", ...root.programs[kind]]);
                    else ask.push(kind);
                }
                if (ask.length > 0) Quickshell.execDetached(["env", `NINOMAE_CONFLICTS=${ask.join(",")}`, "qs", "-p", root.dialogPath]);
            }
        }
    }
}
