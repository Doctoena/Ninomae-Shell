import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
Scope {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property bool packageManagerRunning: false
    property bool downloadRunning: false
    // What logind says this machine can do, so the screen doesn't offer what would fail silently
    // (hibernating needs swap on disk, which zram isn't). Until it answers, both count as yes
    property bool canHibernate: true
    property bool canRebootToFirmware: true
    Process {
        running: true
        command: ["sh", "-c", `
            for m in CanHibernate CanRebootToFirmwareSetup; do
                busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$m" 2>/dev/null || echo 's "yes"'
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                // "challenge" means allowed after asking for a password, so it counts
                const answers = text.trim().split("\n").map(l => l.match(/"([^"]*)"/)?.[1] ?? "yes");
                root.canHibernate = ["yes", "challenge"].includes(answers[0] ?? "yes");
                root.canRebootToFirmware = ["yes", "challenge"].includes(answers[1] ?? "yes");
            }
        }
    }
    function detectRunningStuff() {
        packageManagerRunning = false;
        downloadRunning = false;
        detectPackageManagerProc.running = false;
        detectPackageManagerProc.running = true;
        detectDownloadProc.running = false;
        detectDownloadProc.running = true;
    }
    Process {
        id: detectPackageManagerProc
        command: ["pidof", "pacman", "yay", "paru", "dnf", "zypper", "apt", "apx", "xbps", "flatpak", "snap", "apk",
            "yum", "epsi", "pikman"]
        onExited: (exitCode, exitStatus) => {
            root.packageManagerRunning = (exitCode === 0);
        }
    }
    Process {
        id: detectDownloadProc
        // Not curl or wget: the shell itself runs them now and then (weather, the game launcher)
        command: ["bash", "-c", "pidof aria2c yt-dlp || ls ~/Downloads | grep -E '\.crdownload$|\.part$'"]
        onExited: (exitCode, exitStatus) => {
            root.downloadRunning = (exitCode === 0);
        }
    }
    // The window is kept from the moment the menu opens until the drawer has slid back under the bar.
    // (Setting a "closing" flag when it closes was too late: the window was already gone, so the
    // slide-back never played.)
    property bool keepWindow: false
    Connections {
        target: GlobalStates
        function onSessionOpenChanged() {
            if (GlobalStates.sessionOpen) root.keepWindow = true;
        }
    }
    Timer { // Safety net in case the slide never finishes (e.g. the window couldn't be shown)
        interval: 1500
        running: root.keepWindow && !GlobalStates.sessionOpen
        onTriggered: root.keepWindow = false
    }
    Loader {
        id: sessionLoader
        active: GlobalStates.sessionOpen || root.keepWindow
        onActiveChanged: {
            if (sessionLoader.active) root.detectRunningStuff();
        }
        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.sessionOpen = false;
                }
            }
        }
        sourceComponent: PanelWindow { // Session menu
            id: sessionRoot
            visible: sessionLoader.active
            function hide() {
                GlobalStates.sessionOpen = false; // Also cancels a countdown (the Connections below)
            }

            // Lock, sleep and the like run at once. The ones that end the session (and close every app) count
            // down first: the same one again goes now, Esc or closing the menu cancels
            readonly property int countdownFrom: 5
            property string pending: ""
            property int remaining: 0
            readonly property var actions: ({
                lock: { run: () => Session.lock() },
                sleep: { run: () => Session.suspend() },
                hibernate: { run: () => Session.hibernate() },
                tasks: { run: () => Session.launchTaskManager() },
                reboot: { confirm: true, doing: Translation.tr("Rebooting"), run: () => Session.reboot() },
                poweroff: { confirm: true, doing: Translation.tr("Shutting down"), run: () => Session.poweroff() },
                logout: { confirm: true, doing: Translation.tr("Logging out"), run: () => Session.logout() },
                firmware: { confirm: true, doing: Translation.tr("Rebooting to the firmware"), run: () => Session.rebootToFirmware() }
            })
            function trigger(name) {
                if (sessionRoot.actions[name].confirm && sessionRoot.pending !== name) {
                    sessionRoot.pending = name;
                    sessionRoot.remaining = sessionRoot.countdownFrom;
                    countdownTimer.restart();
                    return;
                }
                sessionRoot.runNow(name);
            }
            function runNow(name) {
                sessionRoot.actions[name].run();
                sessionRoot.hide();
            }
            function cancel() {
                countdownTimer.stop();
                sessionRoot.pending = "";
            }
            Timer {
                id: countdownTimer
                interval: 1000
                repeat: true
                onTriggered: {
                    sessionRoot.remaining -= 1;
                    if (sessionRoot.remaining <= 0) sessionRoot.runNow(sessionRoot.pending);
                }
            }
            // Each action's letter (no labels for them on the buttons)
            readonly property var keyActions: {
                const keys = { [Qt.Key_L]: "lock", [Qt.Key_S]: "sleep", [Qt.Key_R]: "reboot", [Qt.Key_P]: "poweroff",
                               [Qt.Key_O]: "logout", [Qt.Key_T]: "tasks" };
                if (root.canHibernate) keys[Qt.Key_H] = "hibernate";
                if (root.canRebootToFirmware) keys[Qt.Key_F] = "firmware";
                return keys;
            }
            // One of the actions: lit red and counting down if it ends the session; clicked, it takes focus so
            // Enter goes now
            component Action: SessionActionButton {
                required property string actionName
                destructive: sessionRoot.actions[actionName].confirm ?? false
                countdown: sessionRoot.pending === actionName ? sessionRoot.remaining : 0
                countdownFrom: sessionRoot.countdownFrom
                keyHint: sessionRoot.keyLetters[actionName] ?? ""
                pendingText: sessionRoot.actions[actionName].doing ?? ""
                dimmed: sessionRoot.pending !== "" && sessionRoot.pending !== actionName
                onClicked: { forceActiveFocus(); sessionRoot.trigger(actionName); }
            }
            // A note joined under the actions: a warning, or the countdown's (with the apps that close)
            component Note: Rectangle {
                id: note
                property string symbol
                property string text
                property var apps: []
                property bool warn: true
                readonly property bool isLast: notes.shown[notes.shown.length - 1] === this
                Layout.fillWidth: true
                implicitHeight: 44
                topLeftRadius: Appearance.rounding.joined
                topRightRadius: Appearance.rounding.joined
                bottomLeftRadius: isLast ? Appearance.rounding.normal : Appearance.rounding.joined
                bottomRightRadius: bottomLeftRadius
                color: Appearance.colors.colLayer3ErrorHover
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 6
                    MaterialSymbol {
                        visible: note.symbol !== ""
                        text: note.symbol
                        iconSize: 18
                        color: Appearance.colors.colError
                    }
                    Repeater {
                        model: note.apps
                        delegate: IconImage {
                            required property var modelData
                            implicitSize: 20
                            source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: note.apps.length > 0 || note.symbol !== "" ? 4 : 0
                        elide: Text.ElideRight
                        text: note.text
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: note.warn ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                    }
                }
            }
            readonly property var keyLetters: ({ lock: "L", sleep: "S", reboot: "R", poweroff: "P", logout: "O", tasks: "T",
                hibernate: "H", firmware: "F" })
            // The main four, as tiles: counting down one of them, the note takes the strip's place
            readonly property bool tileCounting: ["reboot", "poweroff"].includes(sessionRoot.pending)
            component ExtraAction: Action { // A piece of the strip under the tiles: square where pieces meet, a hairline between
                id: extraAction
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                compact: true
                readonly property bool firstShown: extraRow.shown[0] === this
                readonly property bool lastShown: extraRow.shown[extraRow.shown.length - 1] === this
                readonly property real bottomCorner: notes.anyShown ? Appearance.rounding.joined : Appearance.rounding.normal
                buttonRadiusTopLeft: firstShown ? Appearance.rounding.joined : 0
                buttonRadiusBottomLeft: firstShown ? bottomCorner : 0
                buttonRadiusTopRight: lastShown ? Appearance.rounding.joined : 0
                buttonRadiusBottomRight: lastShown ? bottomCorner : 0
                scale: 1 // The pieces stay put when pressed: they're one strip
                Rectangle {
                    visible: !extraAction.firstShown
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 1
                    height: 22
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.9)
                }
            }
            Connections { // Closed in any way (Esc, a click outside, the shortcut, the lock screen): nothing runs
                target: GlobalStates
                function onSessionOpenChanged() { if (!GlobalStates.sessionOpen) sessionRoot.cancel(); }
            }
            // Open apps, by class, for the countdown. Titles that mark unsaved work ("● file" as VS Code does,
            // or a * before or after the name) for the warning
            readonly property var openApps: [...new Set((HyprlandData.windowList ?? []).map(w => w.class).filter(c => c))]
            readonly property var unsavedApps: [...new Set((HyprlandData.windowList ?? [])
                .filter(w => /^\s*[●•*]|\*\s*$/.test(w.title ?? ""))
                .map(w => DesktopEntries.heuristicLookup(w.class)?.name ?? w.class))]
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"
            anchors {
                top: true
                left: true
                right: true
            }
            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0
            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                onClicked: {
                    sessionRoot.hide()
                }
            }
            // Drops out of the middle of the bar as a gooey drawer, like the other bar drawers
            // (onScreenDisplay/OnScreenDisplay.qml), or rises out of it when it's along the bottom.
            readonly property real padding: 14
            readonly property real bottomRadius: Appearance.rounding.verylarge
            readonly property real hiddenExtra: 60
            readonly property real barBottom: GlobalStates.drawerTopOn(screen) // Below the bar, or near the top without one
            readonly property real panelWidth: contentColumn.implicitWidth + padding * 2
            readonly property real fullHeight: contentColumn.implicitHeight + padding * 2
            readonly property bool ready: readiness.ready // Slide only once the window is on screen
            // 0 = out, 1 = tucked under the bar
            property real offsetScale: (GlobalStates.sessionOpen && ready) ? 0 : 1
            Behavior on offsetScale {
                NumberAnimation {
                    duration: GlobalStates.sessionOpen ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: GlobalStates.sessionOpen ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
                }
            }
            onOffsetScaleChanged: if (offsetScale >= 1 && !GlobalStates.sessionOpen) root.keepWindow = false

            readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
            readonly property real drawerY: Math.min(0, drawerTop)
            readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
            readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)
            // The strip the bar takes, left uncovered by the dim and the drawer: at the top, or along the bottom
            readonly property real barSideTop: GlobalStates.barAtBottom ? 0 : barBottom
            readonly property real barSideBottom: GlobalStates.barAtBottom ? barBottom : 0

            Rectangle { // Dim everything below the bar, in step with the drawer
                anchors { fill: parent; topMargin: sessionRoot.barSideTop; bottomMargin: sessionRoot.barSideBottom }
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                opacity: 1 - sessionRoot.offsetScale
            }

            Item {
                id: stage
                anchors { fill: parent; topMargin: sessionRoot.barSideTop; bottomMargin: sessionRoot.barSideBottom }
                transform: BarSideFlip { size: stage.height } // Bar along the bottom: rises from it
                clip: true
                DrawerReadiness { id: readiness } // The window is made for each opening: always active
                BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                    name: "session"
                    active: sessionRoot.visibleHeight > 0
                    joinX: ((sessionRoot.screen?.width ?? 0) - sessionRoot.panelWidth) / 2
                    joinWidth: sessionRoot.panelWidth
                }
                DrawerBackground { // Shared with the other drawers
                    followBar: true // A card while there's no bar (a fullscreen game)
                    id: background
                    anchors.fill: parent
                    drawerX: (stage.width - sessionRoot.panelWidth) / 2
                    drawerY: sessionRoot.drawerY
                    drawerWidth: sessionRoot.panelWidth
                    drawerHeight: sessionRoot.drawerHeight
                    drawerRadius: Math.min(sessionRoot.bottomRadius, sessionRoot.visibleHeight / 2)
                    fallbackRadius: sessionRoot.bottomRadius
                }

                Item { // Card contents, riding on the drawer
                    id: card
                    x: (stage.width - sessionRoot.panelWidth) / 2
                    y: sessionRoot.drawerY
                    width: sessionRoot.panelWidth
                    height: sessionRoot.fullHeight
                    opacity: 1 - sessionRoot.offsetScale
                    transform: [
                        BarSideFlip { size: card.height }, // Upright in a flipped stage
                        Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob
                    ]
                    MouseArea { // Clicks inside the card don't close it
                        anchors.fill: parent
                    }

                    ColumnLayout {
                        id: contentColumn
                        anchors.centerIn: parent
                        spacing: 12
                        // Grows into place with the drawer (same timing, so opening isn't any slower)
                        scale: 0.92 + 0.08 * (1 - sessionRoot.offsetScale)
                        transformOrigin: GlobalStates.barAtBottom ? Item.Bottom : Item.Top // From the bar's side
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                if (sessionRoot.pending !== "") sessionRoot.cancel();
                                else sessionRoot.hide();
                                event.accepted = true;
                                return;
                            }
                            const name = sessionRoot.keyActions[event.key];
                            if (name) {
                                sessionRoot.trigger(name);
                                event.accepted = true;
                            }
                        }

                        // One joined group: you (the sidebar's greeting card), the main four as tiles, the rest as a strip
                        // under them, or while one of the tiles counts down, a note of what closes
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Rectangle {
                                id: greeting
                                Layout.fillWidth: true
                                implicitHeight: 64
                                topLeftRadius: Appearance.rounding.normal
                                topRightRadius: Appearance.rounding.normal
                                bottomLeftRadius: Appearance.rounding.joined
                                bottomRightRadius: Appearance.rounding.joined
                                color: ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colPrimary, 0.92)
                                clip: true
                                readonly property bool showWeather: Weather.enabled && (Weather.data.temp ?? "") !== ""
                                readonly property int battery: Math.round(Battery.percentage * 100)
                                Halo { // Behind your picture
                                    colour: Appearance.colors.colPrimary
                                    strength: 0.32
                                    reach: 31
                                    centreX: greetingAvatar.x + greetingAvatar.width / 2
                                    centreY: greetingAvatar.y + greetingAvatar.height / 2
                                }
                                Avatar {
                                    id: greetingAvatar
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    editable: false
                                }
                                ColumnLayout {
                                    anchors { left: greetingAvatar.right; right: parent.right; leftMargin: 10; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: Translation.tr("Bye for now, %1").arg(SystemInfo.username)
                                        font.family: Appearance.font.family.title
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: Font.Black
                                        color: Appearance.colors.colOnLayer3
                                    }
                                    RowLayout { // The date, the weather, how long it's been up and the battery (worth a look before sleep or shut down)
                                        Layout.fillWidth: true
                                        spacing: 4
                                        StyledText {
                                            text: Qt.locale().toString(DateTime.clock.date, "dddd d MMMM")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                        }
                                        MaterialSymbol {
                                            visible: greeting.showWeather
                                            Layout.leftMargin: 2
                                            text: Weather.data.icon || "cloud"
                                            iconSize: 13
                                            fill: 1
                                            color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: [greeting.showWeather ? String(Weather.data.temp).replace(/[CF]$/, "") : "",
                                                Translation.tr("up %1").arg(DateTime.uptime),
                                                !Battery.available ? "" : Battery.isCharging ? Translation.tr("%1%, charging").arg(greeting.battery)
                                                    : Translation.tr("%1%").arg(greeting.battery)].filter(t => t).join(" · ")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Battery.available && !Battery.isPluggedIn && Battery.percentage < 0.2
                                                ? Appearance.colors.colError : Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Action {
                                    id: sessionLock
                                    actionName: "lock"
                                    focus: sessionRoot.visible
                                    buttonIcon: "lock"
                                    buttonText: Translation.tr("Lock")
                                    KeyNavigation.right: sessionSleep
                                    KeyNavigation.down: sessionLogout
                                }
                                Action {
                                    id: sessionSleep
                                    actionName: "sleep"
                                    buttonIcon: "dark_mode"
                                    buttonText: Translation.tr("Sleep")
                                    KeyNavigation.left: sessionLock
                                    KeyNavigation.right: sessionReboot
                                    KeyNavigation.down: root.canHibernate ? sessionHibernate : sessionTaskManager
                                }
                                Action {
                                    id: sessionReboot
                                    actionName: "reboot"
                                    buttonIcon: "restart_alt"
                                    buttonText: Translation.tr("Reboot")
                                    KeyNavigation.left: sessionSleep
                                    KeyNavigation.right: sessionShutdown
                                    KeyNavigation.down: sessionTaskManager
                                }
                                Action {
                                    id: sessionShutdown
                                    actionName: "poweroff"
                                    buttonIcon: "power_settings_new"
                                    buttonText: Translation.tr("Shut down")
                                    KeyNavigation.left: sessionReboot
                                    KeyNavigation.down: root.canRebootToFirmware ? sessionFirmwareReboot : sessionTaskManager
                                }
                            }

                            // Less common actions, as wide as the tiles above (the first and last shown round the group's corners)
                            RowLayout {
                                id: extraRow
                                Layout.fillWidth: true
                                visible: !sessionRoot.tileCounting // A tile counting down: the note takes its place
                                spacing: 0
                                readonly property var shown: [sessionLogout, sessionHibernate, sessionTaskManager, sessionFirmwareReboot].filter(b => b.visible)
                                ExtraAction {
                                    id: sessionLogout
                                    actionName: "logout"
                                    buttonIcon: "logout"
                                    buttonText: Translation.tr("Log out")
                                    KeyNavigation.up: sessionLock
                                    KeyNavigation.right: root.canHibernate ? sessionHibernate : sessionTaskManager
                                }
                                ExtraAction { // Only where the machine can (logind; needs swap on disk)
                                    id: sessionHibernate
                                    actionName: "hibernate"
                                    visible: root.canHibernate
                                    buttonIcon: "downloading"
                                    buttonText: Translation.tr("Hibernate")
                                    KeyNavigation.up: sessionSleep
                                    KeyNavigation.left: sessionLogout
                                    KeyNavigation.right: sessionTaskManager
                                }
                                ExtraAction {
                                    id: sessionTaskManager
                                    actionName: "tasks"
                                    buttonIcon: "browse_activity"
                                    buttonText: Translation.tr("Tasks")
                                    KeyNavigation.up: sessionReboot
                                    KeyNavigation.left: root.canHibernate ? sessionHibernate : sessionLogout
                                    KeyNavigation.right: root.canRebootToFirmware ? sessionFirmwareReboot : null
                                }
                                ExtraAction {
                                    id: sessionFirmwareReboot
                                    actionName: "firmware"
                                    visible: root.canRebootToFirmware
                                    buttonIcon: "settings_applications"
                                    buttonText: Translation.tr("Firmware")
                                    KeyNavigation.up: sessionShutdown
                                    KeyNavigation.left: sessionTaskManager
                                }
                            }
                            ColumnLayout { // Notes joined under the strip: warnings, then the countdown; the last rounds the group off
                                id: notes
                                Layout.fillWidth: true
                                spacing: 4
                                readonly property var shown: [unsavedNote, packageNote, downloadNote, countdownNote].filter(n => n.visible)
                                readonly property bool anyShown: shown.length > 0
                                Note {
                                    id: unsavedNote
                                    visible: sessionRoot.unsavedApps.length > 0 && sessionRoot.pending === "" // Counting down, that note says it
                                    symbol: "edit_note"
                                    text: sessionRoot.unsavedApps.length === 1 ? Translation.tr("%1 has unsaved changes").arg(sessionRoot.unsavedApps[0])
                                        : Translation.tr("Unsaved changes in %1").arg(sessionRoot.unsavedApps.join(", "))
                                }
                                Note {
                                    id: packageNote
                                    visible: root.packageManagerRunning
                                    symbol: "package_2"
                                    text: Translation.tr("Your package manager is running")
                                }
                                Note {
                                    id: downloadNote
                                    visible: root.downloadRunning
                                    symbol: "download"
                                    text: Translation.tr("There might be a download in progress")
                                }
                                Note { // Counting down: what closes, any unsaved work, how to go now or back out
                                    id: countdownNote
                                    visible: sessionRoot.pending !== ""
                                    symbol: ""
                                    apps: sessionRoot.openApps.slice(0, 6)
                                    warn: sessionRoot.unsavedApps.length > 0
                                    text: [sessionRoot.openApps.length === 0 ? "" : sessionRoot.openApps.length === 1 ? Translation.tr("1 app closes")
                                            : Translation.tr("%1 apps close").arg(sessionRoot.openApps.length),
                                        sessionRoot.unsavedApps.length === 0 ? "" : sessionRoot.unsavedApps.length === 1
                                            ? Translation.tr("%1 has unsaved work").arg(sessionRoot.unsavedApps[0])
                                            : Translation.tr("unsaved work in %1").arg(sessionRoot.unsavedApps.join(", ")),
                                        Translation.tr("Enter goes now, Esc cancels")].filter(t => t).join(" · ")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    IpcHandler {
        target: "session"
        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
        function close(): void {
            GlobalStates.sessionOpen = false
        }
        function open(): void {
            GlobalStates.sessionOpen = true
        }
    }
    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"
        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }
    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"
        onPressed: {
            GlobalStates.sessionOpen = true
        }
    }
    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"
        onPressed: {
            GlobalStates.sessionOpen = false
        }
    }
}
