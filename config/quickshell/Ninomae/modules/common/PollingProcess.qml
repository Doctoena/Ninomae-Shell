import QtQuick
import Quickshell.Io

/**
 * A command whose output is wanted again and again: run it with trigger(), get its stdout in
 * onResult. Handles what each service used to redo by hand:
 *  - `debounce` (ms): a burst of trigger() calls runs the command once, after the burst
 *  - a trigger() while it's still running isn't dropped (setting `running` on a running Process does
 *    nothing): it runs once more when the current run ends, so the result is never stale
 *  - `interval` (ms, 0 = off): also runs on a timer while `polling` is true
 *  - `retries`: a failed run (non-zero exit) is retried after `retryDelay` ms, that many times
 *
 *   PollingProcess {
 *       command: ["nmcli", "radio", "wifi"]
 *       debounce: 300
 *       onResult: (text, exitCode) => root.wifiEnabled = text.trim() === "enabled"
 *   }
 */
Process {
    id: root
    property int debounce: 0
    property int interval: 0
    property bool polling: true
    property int retries: 0
    property int retryDelay: 2000
    property bool runOnStart: false

    signal result(string text, int exitCode)

    function trigger() {
        if (root.debounce > 0) debounceTimer.restart();
        else root.runNow();
    }
    function runNow() {
        if (root.running) {
            root._rerun = true;
            return;
        }
        root._streamDone = false;
        root._exitCode = -1;
        root.running = true;
    }

    property bool _rerun: false
    property bool _streamDone: false
    property int _exitCode: -1
    property int _failures: 0

    // Output and exit can arrive in either order; report once both are in
    function _finish() {
        if (!root._streamDone || root._exitCode < 0) return;
        const code = root._exitCode;
        root._exitCode = -1;
        if (code !== 0 && root._failures < root.retries) {
            root._failures++;
            retryTimer.restart();
            return;
        }
        root._failures = 0;
        root.result(collector.text, code);
        if (root._rerun) {
            root._rerun = false;
            root.runNow();
        }
    }

    stdout: StdioCollector {
        id: collector
        onStreamFinished: {
            root._streamDone = true;
            root._finish();
        }
    }
    onExited: exitCode => {
        root._exitCode = exitCode;
        root._finish();
    }

    property Timer debounceTimer: Timer {
        interval: root.debounce
        onTriggered: root.runNow()
    }
    property Timer retryTimer: Timer {
        interval: root.retryDelay
        onTriggered: root.runNow()
    }
    property Timer pollTimer: Timer {
        interval: Math.max(1, root.interval)
        running: root.interval > 0 && root.polling
        repeat: true
        onTriggered: root.trigger()
    }
    Component.onCompleted: if (root.runOnStart) root.runNow()
}
