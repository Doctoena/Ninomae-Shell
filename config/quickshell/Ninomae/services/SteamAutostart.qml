pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

/**
 * Starts Steam hidden (in the tray, no window) once per login, when Settings → Games → "Start Steam at login"
 * is on: games then start without waiting for Steam, and updates download before you play. Once per login
 * means a shell restart doesn't start it again, so quitting Steam keeps it closed until the next login
 */
Singleton {
    id: root
    function load() {} // Referenced from shell.qml so the singleton starts with the shell

    readonly property bool wanted: Config.ready && (Config.options.gameLauncher.steamAtLogin ?? false)
    onWantedChanged: if (wanted) _start()
    Component.onCompleted: if (wanted) _start()

    property bool _done: false
    function _start() {
        if (_done) return;
        _done = true;
        // The marker lives in XDG_RUNTIME_DIR, which is emptied when the session ends. Detached, so Steam
        // outlives a shell restart
        Quickshell.execDetached(["sh", "-c",
            'm="$XDG_RUNTIME_DIR/ninomae-steam-started"; [ -e "$m" ] && exit 0; : > "$m"; '
            + 'command -v steam >/dev/null && ! pgrep -x steam >/dev/null && exec steam -silent "$@"', "sh",
            ...((Config.options.gameLauncher.steamRemoteControl ?? false) ? ["-cef-enable-debugging"] : [])]);
    }
}
