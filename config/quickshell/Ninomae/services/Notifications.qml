pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        // Command to run when the notification is clicked, sent by apps that want the click to keep
        // working after the shell restarts (the Steam notifications plugin sends ["steam", "steam://…"])
        property var execArgv: root.parseExecArgv(notification?.hints?.["omarchy-exec-argv"])
        property Timer timer
        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
        Component.onDestruction: timer?.destroy()
    }
    // The "omarchy-exec-argv" hint: a JSON list of strings (program first). Anything else is ignored
    function parseExecArgv(value) {
        if (!value) return null;
        let argv = value;
        if (typeof value === "string") {
            try { argv = JSON.parse(value); } catch (e) { return null; }
        }
        if (!Array.isArray(argv) || argv.length === 0 || !argv.every(a => typeof a === "string" && a.length > 0)) return null;
        return argv;
    }
    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
            "execArgv": notif.execArgv ?? null,
        }
    }
    // Owned by its Notif (destroyed with it), so hovering can stop and restart it any number of times
    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: root.timeoutNotification(notificationId)
    }
    // Saved history is capped; the oldest notifications that aren't showing as popups go first
    readonly property int maxHistory: 200
    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    // Debounce file writes to reduce I/O
    Timer {
        id: saveDebounceTimer
        interval: 500
        repeat: false
        onTriggered: notifFileView.setText(stringifyList(root.list));
    }
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }
    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }
    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // The group sorts by its newest notification
            groups[notif.appName].time = Math.max(groups[notif.appName].time, notif.time);
        });
        return groups;
    }
    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property var appNameList: appNameListForGroups(root.groupsByAppName)
    property var popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)
    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    property bool loaded: false // The saved history has been read (or there was none)
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);
	NotificationServer {
        id: notifServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true
        onNotification: (notification) => {
            notification.tracked = true
            // The same notification again (a repeated "Low battery", say) replaces the old one instead
            // of stacking a copy under it
            root.list.filter(n => n.appName === notification.appName && n.summary === notification.summary
                    && n.body === notification.body)
                .forEach(n => root.discardNotification(n.notificationId));
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });
			root.list = root.trimmed([...root.list, newNotifObject]);
            // Popup
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                if (notification.expireTimeout != 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
                root.unread++;
            }
            root.notify(newNotifObject);
            saveDebounceTimer.restart();
        }
    }
    // Short-lived news only matters in the moment: dropped from the history a few minutes later
    // (once it isn't showing as a popup). So far, Steam's friend activity ("is playing …", "is now online")
    readonly property int ephemeralLifetime: 5 * 60 * 1000
    function isEphemeral(notif) {
        return notif.appName === "Steam" && /^is (now )?(playing|online|in-game)\b/i.test(notif.body);
    }
    function sweepEphemeral() {
        const cutoff = Date.now() - root.ephemeralLifetime;
        root.list.filter(n => !n.popup && n.time < cutoff && root.isEphemeral(n))
            .forEach(n => root.discardNotification(n.notificationId));
    }
    Timer {
        interval: 60 * 1000
        running: root.list.length > 0
        repeat: true
        onTriggered: root.sweepEphemeral()
    }
    // Removed notifications are destroyed a moment later, once the list's remove animation is done with them
    property var _disposeQueue: []
    function disposeLater(objects) {
        root._disposeQueue = root._disposeQueue.concat(objects);
        disposeTimer.restart();
    }
    Timer {
        id: disposeTimer
        interval: 2000
        onTriggered: {
            const queue = root._disposeQueue;
            root._disposeQueue = [];
            queue.forEach(n => n.destroy());
        }
    }
    // Drops the oldest non-popup notifications past maxHistory (destroying them)
    function trimmed(list) {
        let excess = list.length - root.maxHistory;
        if (excess <= 0) return list;
        const dropped = new Set();
        for (let i = 0; i < list.length && excess > 0; i++) {
            if (list[i].popup) continue;
            dropped.add(list[i]);
            excess--;
        }
        root.disposeLater([...dropped]);
        return list.filter(n => !dropped.has(n));
    }
    function markAllRead() {
        root.unread = 0;
    }
    function discardNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            const [removed] = root.list.splice(index, 1);
            triggerListChange();
            saveDebounceTimer.restart();
            root.disposeLater([removed]);
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }
    function discardAllNotifications() {
        const old = root.list;
        root.list = []
        root.disposeLater(old);
        triggerListChange()
        saveDebounceTimer.restart();
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }
    // Pause a popup's countdown while it's hovered (notifications with no timeout have no timer)
    function cancelTimeout(id) {
        root.list.find((notif) => notif.notificationId === id)?.timer?.stop();
    }
    // Resume it when the pointer leaves, with the full timeout again
    function restartTimeout(id) {
        const notif = root.list.find((notif) => notif.notificationId === id);
        if (notif?.popup) notif.timer?.restart();
    }
    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }
    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }
    function attemptInvokeAction(id, notifIdentifier) {
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            action.invoke()
        }
        else {
            // The sender is gone (e.g. after a shell restart): fall back to the notification's own
            // click command, if it brought one
            const notif = root.list.find((n) => n.notificationId === id);
            if (notif?.execArgv) Quickshell.execDetached(notif.execArgv);
            else console.warn("[Notifications] Action target not found in server: " + id)
        }
        root.discardNotification(id);
    }
    function triggerListChange() {
        root.list = root.list.slice(0)
    }
    function refresh() {
        notifFileView.reload()
    }
    Component.onCompleted: {
        refresh()
    }
    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            // A damaged file (cut short by a crash, say) starts an empty history instead of breaking
            // notifications until the file is fixed by hand
            let saved = [];
            try {
                saved = JSON.parse(notifFileView.text());
                if (!Array.isArray(saved)) throw new Error("not a list");
            } catch (e) {
                console.warn("[Notifications] Saved history unreadable, starting empty:", e);
                saved = [];
            }
            root.list = root.trimmed(saved.filter(notif => notif && typeof notif === "object").map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    // Actions die with the sender, except "Open" on notifications that carry their own
                    // click command (attemptInvokeAction runs it)
                    "actions": root.parseExecArgv(notif.execArgv) ? [{ "identifier": "exec-argv", "text": Translation.tr("Open") }] : [],
                    "execArgv": root.parseExecArgv(notif.execArgv),
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": notif.image,
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            }));
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })
            root.idOffset = maxId
            root.sweepEphemeral() // Yesterday's "is playing" shouldn't greet you on login
            root.loaded = true
            root.initDone()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                root.list = []
                notifFileView.setText(stringifyList(root.list));
                root.loaded = true
            } else {
                console.warn("[Notifications] Error loading file: " + error)
            }
        }
    }
}
