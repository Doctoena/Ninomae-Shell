pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root
    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options.time.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    // Config.options.time.format; with showAmPm off, a 12-hour format ("h:mm AP") drops its AM/PM
    readonly property string timeFormat: Config.options?.time?.format ?? "hh:mm"
    readonly property bool is12Hour: /a/i.test(timeFormat)
    // The clock has no date for a moment at startup, and the config can be half there during a reload: ""
    // then, not undefined (which QML warns about)
    property string time: {
        if (!clock.date) return "";
        const formatted = Qt.locale().toString(clock.date, timeFormat) ?? "";
        return (Config.options?.time?.showAmPm ?? true) ? formatted : formatted.replace(/\s*[AaPp][Mm]\b/g, "");
    }
    property string amPm: is12Hour && clock.date ? Qt.locale().toString(clock.date, "AP") : ""
    property string date: clock.date ? (Qt.locale().toString(clock.date, Config.options?.time?.dateFormat ?? "dddd, dd/MM") ?? "") : ""
    property string uptime: "0h 0m"
    function updateUptime() {
        fileUptime.reload();
        const textUptime = fileUptime.text();
        const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);
        // Convert seconds to days, hours, and minutes
        const days = Math.floor(uptimeSeconds / 86400);
        const hours = Math.floor((uptimeSeconds % 86400) / 3600);
        const minutes = Math.floor((uptimeSeconds % 3600) / 60);
        // Build the formatted uptime string
        let formatted = "";
        if (days > 0)
            formatted += `${days}d`;
        if (hours > 0)
            formatted += `${formatted ? " " : ""}${hours}h`;
        if (minutes > 0 || !formatted)
            formatted += `${formatted ? " " : ""}${minutes}m`;
        uptime = formatted;
    }
    Component.onCompleted: updateUptime()
    // Uptime only shows minutes, so refresh it on the clock's own tick instead of a separate timer
    Connections {
        target: clock
        function onDateChanged() {
            root.updateUptime();
        }
    }
    FileView {
        id: fileUptime
        path: "/proc/uptime"
        blockAllReads: true
    }
}
