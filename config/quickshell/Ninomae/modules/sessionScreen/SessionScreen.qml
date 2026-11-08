import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
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
    // Warning pill shown under the actions (unsaved changes, package manager or downloads running)
    component WarningPill: Rectangle {
        id: warningPill
        property string text
        color: Appearance.colors.colErrorContainer
        radius: 12
        implicitHeight: 34
        implicitWidth: warningRow.implicitWidth + 28
        RowLayout {
            id: warningRow
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                text: "warning"
                iconSize: 18
                color: Appearance.colors.colOnErrorContainer
            }
            StyledText {
                text: warningPill.text
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnErrorContainer
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
                onClicked: { forceActiveFocus(); sessionRoot.trigger(actionName); }
            }
            component ExtraAction: Action { // A wide button in the row under the tiles
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                compact: true
                outerBottomLeft: extraRow.shown[0] === this
                outerBottomRight: extraRow.shown[extraRow.shown.length - 1] === this
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
            readonly property real padding: 28
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
                        spacing: 20
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

                        // Header: your wallpaper as a banner, your picture over its bottom edge, a goodbye, and the uptime
                        // (with the battery on a laptop: worth a look before choosing sleep over shutting down)
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 176
                            ClippingRectangle {
                                id: banner
                                width: parent.width
                                height: 130
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer3 // Shown until the picture loads, or for a video wallpaper
                                readonly property string wallpaper: Config.wallpaperPath
                                Image {
                                    anchors.fill: parent
                                    // A video wallpaper has a still of it (Config.thumbnailPath), an image its screen-sized copy.
                                    // (By id: a ClippingRectangle's children sit in an inner item, so `parent` isn't the banner)
                                    source: /\.(mp4|webm|mkv|mov|avi|gif)$/i.test(banner.wallpaper) ? Config.thumbnailPath
                                        : WallpaperVariants.forScreen(banner.wallpaper, 1100, 260)
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 1100
                                    asynchronous: true
                                }
                                Rectangle { // A shade, so the banner sits back behind what's on the card
                                    anchors.fill: parent
                                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.55)
                                }
                            }
                            Avatar {
                                x: 22
                                y: 82
                                editable: false
                                implicitWidth: 92
                                implicitHeight: 92
                            }
                            ColumnLayout {
                                x: 128
                                y: 134
                                width: parent.width - x
                                spacing: -2
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Translation.tr("Bye for now, %1").arg(SystemInfo.username)
                                    font.family: Appearance.font.family.title
                                    font.pixelSize: 22
                                    font.weight: Font.Black
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    readonly property int battery: Math.round(Battery.percentage * 100)
                                    text: [Translation.tr("Up %1").arg(DateTime.uptime),
                                        !Battery.available ? "" : Battery.isCharging ? Translation.tr("battery %1%, charging").arg(battery)
                                            : Translation.tr("battery %1%").arg(battery)].filter(t => t).join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Battery.available && !Battery.isPluggedIn && Battery.percentage < 0.2
                                        ? Appearance.colors.colError : Appearance.colors.colSubtext
                                }
                            }
                        }

                        // The actions: one joined group, the main four as tiles, the rest as wide buttons under them
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Action {
                                    id: sessionLock
                                    actionName: "lock"
                                    outerTopLeft: true
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
                                    outerTopRight: true
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
                                spacing: 4
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
                        }

                        // Counting down: what's about to happen, how to go now or back out, and what closes
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            visible: sessionRoot.pending !== ""
                            spacing: 6
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("%1 in %2 s").arg(sessionRoot.actions[sessionRoot.pending]?.doing ?? "").arg(sessionRoot.remaining)
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colError
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Click it again or press Enter to go now. Esc cancels.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            RowLayout { // The apps that get closed
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 4
                                visible: sessionRoot.openApps.length > 0
                                spacing: 6
                                Repeater {
                                    model: sessionRoot.openApps.slice(0, 8)
                                    delegate: IconImage {
                                        required property var modelData
                                        implicitSize: 22
                                        source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                                    }
                                }
                                StyledText {
                                    Layout.leftMargin: 4
                                    text: sessionRoot.openApps.length === 1 ? Translation.tr("1 app will close")
                                        : Translation.tr("%1 apps will close").arg(sessionRoot.openApps.length)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        // Warnings
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            visible: sessionRoot.unsavedApps.length > 0 || root.packageManagerRunning || root.downloadRunning
                            spacing: 6
                            WarningPill {
                                Layout.alignment: Qt.AlignHCenter
                                visible: sessionRoot.unsavedApps.length > 0
                                text: sessionRoot.unsavedApps.length === 1 ? Translation.tr("%1 has unsaved changes").arg(sessionRoot.unsavedApps[0])
                                    : Translation.tr("Unsaved changes in %1").arg(sessionRoot.unsavedApps.join(", "))
                            }
                            WarningPill {
                                Layout.alignment: Qt.AlignHCenter
                                visible: root.packageManagerRunning
                                text: Translation.tr("Your package manager is running")
                            }
                            WarningPill {
                                Layout.alignment: Qt.AlignHCenter
                                visible: root.downloadRunning
                                text: Translation.tr("There might be a download in progress")
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
