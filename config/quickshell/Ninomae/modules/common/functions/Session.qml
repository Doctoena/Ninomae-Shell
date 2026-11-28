pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
Singleton {
    id: root

    // Ending the session: every window is asked to close, as its ✕ would, so apps can save (or ask to). The
    // action runs once they're all gone. One still open after the wait, a "Save changes?" dialog say, stops it
    // with a notification and that window in front. With `force` (the lock screen, an empty battery: nobody
    // there to answer a dialog) it goes ahead after the wait anyway
    readonly property int closeWait: 10000 // ms
    property string _command: ""
    property string _what: ""
    property bool _force: false
    property real _deadline: 0
    function closeAppsThen(command, what, force) {
        root._command = command;
        root._what = what;
        root._force = force;
        root._deadline = Date.now() + root.closeWait;
        for (const w of HyprlandData.windowList ?? [])
            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${w.address}" })`);
        waitForClose.restart();
    }
    Timer {
        id: waitForClose
        interval: 250
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const left = HyprlandData.windowList ?? [];
            const timedOut = Date.now() >= root._deadline;
            if (left.length === 0 || (timedOut && root._force)) {
                stop();
                Quickshell.execDetached(["bash", "-c", root._command]);
            } else if (timedOut) {
                stop();
                const names = [...new Set(left.map(w => DesktopEntries.heuristicLookup(w.class)?.name ?? w.class))];
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${left[0].address}" })`);
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-u", "critical",
                    Translation.tr("%1 cancelled").arg(root._what),
                    Translation.tr("%1 didn't close. Save your work there and try again.").arg(names.join(", "))]);
            }
        }
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }
    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }
    function hibernate() {
        Quickshell.execDetached(["bash", "-c", "systemctl hibernate || loginctl hibernate"]);
    }
    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.taskManager}`]);
    }
    function logout() { // Hyprland's own exit, not killing it
        closeAppsThen("hyprctl dispatch 'hl.dsp.exit()'", Translation.tr("Log out"), false);
    }
    function poweroff(force = false) {
        closeAppsThen("systemctl poweroff || loginctl poweroff", Translation.tr("Shut down"), force);
    }
    function reboot(force = false) {
        closeAppsThen("systemctl reboot || loginctl reboot", Translation.tr("Reboot"), force);
    }
    function rebootToFirmware() {
        closeAppsThen("systemctl reboot --firmware-setup || loginctl reboot --firmware-setup", Translation.tr("Reboot to firmware"), false);
    }
}
