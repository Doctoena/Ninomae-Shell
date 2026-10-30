pragma Singleton
import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import Quickshell.Io
import Qt.labs.folderlistmodel
Singleton {
    id: root
    readonly property bool available: UPower.displayDevice.isLaptopBattery
    readonly property var chargeState: UPower.displayDevice.state
    readonly property bool isCharging: chargeState == UPowerDeviceState.Charging
    readonly property bool isFullyCharged: chargeState == UPowerDeviceState.FullyCharged
    // On the charger whether or not it's charging (a charge limit holds it at PendingCharge)
    readonly property bool isPluggedIn: isCharging || isFullyCharged || chargeState == UPowerDeviceState.PendingCharge
    readonly property real percentage: UPower.displayDevice.percentage
    readonly property int percent: Math.round(percentage * 100) // For display: bar, popup, lock screen
    readonly property real energyRate: UPower.displayDevice.changeRate
    readonly property real timeToEmpty: UPower.displayDevice.timeToEmpty
    readonly property real timeToFull: UPower.displayDevice.timeToFull

    readonly property bool soundEnabled: Config.options.sounds.battery
    readonly property bool isLow: available && percentage <= Config.options.battery.low / 100
    readonly property bool isLowAndUnplugged: isLow && !isPluggedIn
    readonly property bool isCriticalAndUnplugged: available && !isPluggedIn && percentage <= Config.options.battery.critical / 100
    readonly property bool isFullAndCharging: available && isCharging && percentage >= Config.options.battery.full / 100
    // At the last level the laptop shuts down cleanly. It used to suspend, which kept draining until the battery
    // died in its sleep (a hard power-off, session lost); there's no disk swap to hibernate to. The config keys
    // keep their old names (automaticSuspend, suspend) so existing settings still apply
    readonly property bool allowAutomaticShutdown: Config.options.battery.automaticSuspend
    readonly property bool shouldShutDown: allowAutomaticShutdown && available && !isPluggedIn
        && percentage <= Config.options.battery.suspend / 100

    // The level as a glyph's fill (battery_1_bar … battery_full), for the bar and the lock screen.
    // Charging has its own steps (battery_charging_20 … _full), so the fill still tracks the level
    readonly property string icon: isCharging ? chargingIcon : isLow ? "battery_alert"
        : percentage >= 0.95 ? "battery_full" : `battery_${Math.max(0, Math.min(6, Math.round(percentage * 7)))}_bar`
    readonly property string chargingIcon: {
        if (percentage >= 0.95) return "battery_charging_full";
        const steps = [20, 30, 50, 60, 80, 90]; // The glyphs the font has; take the nearest
        return `battery_charging_${steps.find((s, i) => i === steps.length - 1 || percent < (s + steps[i + 1]) / 2)}`;
    }

    // Health from UPower's battery device (the display device is an aggregate without it); technology and
    // voltage, which UPower doesn't expose, from sysfs. No processes
    readonly property UPowerDevice batteryDevice: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property real healthPercent: (batteryDevice?.healthSupported ?? false) ? batteryDevice.healthPercentage : 100
    readonly property string sysfsPath: batteryDevice?.nativePath ? `/sys/class/power_supply/${batteryDevice.nativePath}` : ""
    property string technology: ""
    property real voltage: 0
    FileView {
        path: root.sysfsPath ? `${root.sysfsPath}/technology` : ""
        onLoaded: root.technology = text().trim()
        onLoadFailed: () => {}
    }
    FileView { id: voltageFile; path: root.sysfsPath ? `${root.sysfsPath}/voltage_now` : ""; blockAllReads: true; onLoadFailed: () => {} }
    function readVoltage() {
        if (!root.sysfsPath) return;
        voltageFile.reload();
        const microvolts = parseInt(voltageFile.text());
        root.voltage = isNaN(microvolts) ? 0 : microvolts / 1e6;
    }
    Timer {
        interval: 300000 // Voltage drifts slowly; the popup only shows one decimal
        running: root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readVoltage()
    }

    // Charge history from UPower's own log, /var/lib/upower/history-charge-<model>-<design Wh>.dat: one
    // "unix time<TAB>percent<TAB>state" line per change, written out every few minutes. No processes
    readonly property int historySpan: 12 * 3600 // Seconds the popup's graph covers
    property var history: [] // [{ t: unix seconds, v: 0..1 }], oldest first, from the last sample before the span
    property real _historySince: 0 // Last plug/unplug in the log, and whether the log ends plugged in
    property bool _historyPlugged: false
    property real _liveSince: 0 // Last plug/unplug seen while running (the log can lag by minutes)
    // When the charger was last plugged in or unplugged (unix seconds), 0 if unknown
    readonly property real pluggedSince: _historyPlugged === isPluggedIn ? _historySince : _liveSince
    FolderListModel {
        id: historyFolder
        folder: root.available ? "file:///var/lib/upower" : "" // No listing without a battery
        // The design capacity in the name isn't exposed, so match by model
        nameFilters: [`history-charge-${(root.batteryDevice?.model ?? "").replace(/ /g, "_")}-*.dat`]
        showDirs: false
    }
    FileView {
        path: root.available && historyFolder.count > 0 ? historyFolder.get(0, "filePath") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseHistory(text())
        onLoadFailed: () => {}
    }
    function parseHistory(text) {
        const from = Date.now() / 1000 - root.historySpan;
        const points = [];
        let since = 0, plugged = null;
        for (const line of text.split("\n")) {
            const [t, v, state] = line.split("\t");
            const time = Number(t);
            if (!time || !state || state === "unknown") continue;
            const nowPlugged = state !== "discharging";
            if (plugged !== null && nowPlugged !== plugged) since = time;
            plugged = nowPlugged;
            const point = { t: time, v: Number(v) / 100 };
            if (time < from) points.splice(0, points.length, point); // Only the latest one before the span
            else points.push(point);
        }
        root.history = points;
        root._historySince = since;
        root._historyPlugged = plugged ?? false;
    }

    // ── Warnings ──
    // Titles are shared by the notifications and the cleanup that matches them
    readonly property string lowTitle: Translation.tr("Low battery")
    readonly property string criticalTitle: Translation.tr("Critically low battery")
    readonly property string fullTitle: Translation.tr("Battery full")
    readonly property string shutdownTitle: Translation.tr("Battery empty, shutting down")
    function warn(title, body, critical, sound) {
        Quickshell.execDetached(["notify-send", "-a", "Battery", "-u", critical ? "critical" : "normal", title, body]);
        if (root.soundEnabled) Audio.playSystemSound(sound);
    }
    onIsLowAndUnpluggedChanged: if (isLowAndUnplugged) warn(lowTitle, Translation.tr("Consider plugging in your device"), true, "dialog-warning")
    onIsCriticalAndUnpluggedChanged: if (isCriticalAndUnplugged) warn(criticalTitle, allowAutomaticShutdown
        ? Translation.tr("Please charge!\nShuts down automatically at %1%").arg(Config.options.battery.suspend)
        : Translation.tr("Please charge!"), true, "suspend-error")
    onIsFullAndChargingChanged: if (isFullAndCharging) warn(fullTitle, Translation.tr("Please unplug the charger"), false, "complete")

    // A minute's warning before shutting down: plugging in or pressing Cancel keeps it on
    onShouldShutDownChanged: {
        if (shouldShutDown) {
            shutdownCountdown.restart();
            shutdownWarning.running = true;
            if (root.soundEnabled) Audio.playSystemSound("suspend-error");
        } else {
            shutdownCountdown.stop();
            shutdownWarning.running = false;
        }
    }
    Timer {
        id: shutdownCountdown
        interval: 60000
        onTriggered: if (root.shouldShutDown) Session.poweroff() // Asks windows to close first
    }
    Process {
        id: shutdownWarning
        // -A waits for the notification and prints the action's name if it's pressed
        command: ["notify-send", "-a", "Battery", "-u", "critical", "-A", `cancel=${Translation.tr("Cancel")}`,
            root.shutdownTitle, Translation.tr("Shutting down in 1 minute. Plug in or press Cancel to stay on.")]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "cancel") shutdownCountdown.stop()
        }
    }

    // Battery warnings go stale once the charger changes: low/critical/shutdown when it's plugged in, "full,
    // unplug" when it's unplugged. Also on startup, for ones saved from an earlier session
    function clearStaleWarnings() {
        const stale = root.isPluggedIn ? [root.lowTitle, root.criticalTitle, root.shutdownTitle] : [root.fullTitle];
        Notifications.list.filter(n => n.appName === "Shell" && stale.includes(n.summary))
            .forEach(n => Notifications.discardNotification(n.notificationId));
    }
    // At startup the battery, its charger state and the saved notifications each turn up in their own
    // time; tidy up once all three are there (after that, plugging in or out does it)
    readonly property bool readyToTidy: available && chargeState !== UPowerDeviceState.Unknown && Notifications.loaded
    onReadyToTidyChanged: if (readyToTidy) clearStaleWarnings()
    onIsPluggedInChanged: {
        if (!root.available) return;
        root._liveSince = Date.now() / 1000;
        root.clearStaleWarnings();
        root.readVoltage(); // Jumps on plug/unplug
        if (root.soundEnabled) Audio.playSystemSound(isPluggedIn ? "power-plug" : "power-unplug");
    }
}
