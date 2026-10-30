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
    // Warning pill shown under the actions (package manager / downloads running)
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
    component KeyHint: RowLayout {
        property list<string> keys
        property string label
        spacing: 4
        Repeater {
            model: parent.keys
            delegate: KeyChip {
                required property string modelData
                key: modelData
            }
        }
        StyledText {
            Layout.leftMargin: 4
            text: parent.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
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
        command: ["bash", "-c", "pidof curl wget aria2c yt-dlp || ls ~/Downloads | grep -E '\.crdownload$|\.part$'"]
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
                GlobalStates.sessionOpen = false;
            }
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
            // (onScreenDisplay/OnScreenDisplay.qml). Assumes a bar at the top.
            readonly property real padding: 28
            readonly property real bottomRadius: Appearance.rounding.verylarge
            readonly property real hiddenExtra: 60
            readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
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

            Rectangle { // Dim everything below the bar, in step with the drawer
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: parent.top; topMargin: sessionRoot.barBottom }
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                opacity: 1 - sessionRoot.offsetScale
            }

            Item {
                id: stage
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: parent.top; topMargin: sessionRoot.barBottom }
                clip: true
                DrawerReadiness { id: readiness } // The window is made for each opening: always active
                BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                    name: "session"
                    active: sessionRoot.visibleHeight > 0
                    joinX: ((sessionRoot.screen?.width ?? 0) - sessionRoot.panelWidth) / 2
                    joinWidth: sessionRoot.panelWidth
                }
                DrawerBackground { // Shared with the other drawers
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
                transform: Matrix4x4 { // Wobble with the blob
                    matrix: background.deformMatrix
                }
                MouseArea { // Clicks inside the card don't close it
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: contentColumn
                    anchors.centerIn: parent
                    spacing: 20
                    // Grows into place with the drawer (same timing, so opening isn't any slower)
                    scale: 0.92 + 0.08 * (1 - sessionRoot.offsetScale)
                    transformOrigin: Item.Top
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            sessionRoot.hide();
                        }
                    }

                    // Header: badge, title, who + uptime
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: 14 // A solid accent squircle, like the quick toggles' icons
                            color: Appearance.colors.colPrimary
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "power_settings_new"
                                iconSize: 24
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Session")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("%1 · up %2").arg(SystemInfo.username).arg(DateTime.uptime)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    // Main actions
                    RowLayout {
                        spacing: 12
                        SessionActionButton {
                            id: sessionLock
                            focus: sessionRoot.visible
                            buttonIcon: "lock"
                            buttonText: Translation.tr("Lock")
                            onClicked: { Session.lock(); sessionRoot.hide() }
                            KeyNavigation.right: sessionSleep
                            KeyNavigation.down: sessionLogout
                        }
                        SessionActionButton {
                            id: sessionSleep
                            buttonIcon: "dark_mode"
                            buttonText: Translation.tr("Sleep")
                            onClicked: { Session.suspend(); sessionRoot.hide() }
                            KeyNavigation.left: sessionLock
                            KeyNavigation.right: sessionReboot
                            KeyNavigation.down: root.canHibernate ? sessionHibernate : sessionTaskManager
                        }
                        SessionActionButton {
                            id: sessionReboot
                            buttonIcon: "restart_alt"
                            buttonText: Translation.tr("Reboot")
                            destructive: true
                            onClicked: { Session.reboot(); sessionRoot.hide() }
                            KeyNavigation.left: sessionSleep
                            KeyNavigation.right: sessionShutdown
                            KeyNavigation.down: sessionTaskManager
                        }
                        SessionActionButton {
                            id: sessionShutdown
                            buttonIcon: "power_settings_new"
                            buttonText: Translation.tr("Shut down")
                            destructive: true
                            onClicked: { Session.poweroff(); sessionRoot.hide() }
                            KeyNavigation.left: sessionReboot
                            KeyNavigation.down: root.canRebootToFirmware ? sessionFirmwareReboot : sessionTaskManager
                        }
                    }

                    // Less common actions
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        SessionActionButton {
                            id: sessionLogout
                            compact: true
                            buttonIcon: "logout"
                            buttonText: Translation.tr("Log out")
                            onClicked: { Session.logout(); sessionRoot.hide() }
                            KeyNavigation.up: sessionLock
                            KeyNavigation.right: root.canHibernate ? sessionHibernate : sessionTaskManager
                        }
                        SessionActionButton { // Only where the machine can (logind; needs swap on disk)
                            id: sessionHibernate
                            visible: root.canHibernate
                            compact: true
                            buttonIcon: "downloading"
                            buttonText: Translation.tr("Hibernate")
                            onClicked: { Session.hibernate(); sessionRoot.hide() }
                            KeyNavigation.up: sessionSleep
                            KeyNavigation.left: sessionLogout
                            KeyNavigation.right: sessionTaskManager
                        }
                        SessionActionButton {
                            id: sessionTaskManager
                            compact: true
                            buttonIcon: "browse_activity"
                            buttonText: Translation.tr("Tasks")
                            onClicked: { Session.launchTaskManager(); sessionRoot.hide() }
                            KeyNavigation.up: sessionReboot
                            KeyNavigation.left: root.canHibernate ? sessionHibernate : sessionLogout
                            KeyNavigation.right: root.canRebootToFirmware ? sessionFirmwareReboot : null
                        }
                        SessionActionButton {
                            id: sessionFirmwareReboot
                            visible: root.canRebootToFirmware
                            compact: true
                            buttonIcon: "settings_applications"
                            buttonText: Translation.tr("Firmware")
                            onClicked: { Session.rebootToFirmware(); sessionRoot.hide() }
                            KeyNavigation.up: sessionShutdown
                            KeyNavigation.left: sessionTaskManager
                        }
                    }

                    // Warnings
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.packageManagerRunning || root.downloadRunning
                        spacing: 6
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

                    // Key hints
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 18
                        KeyHint { keys: ["←", "→", "↑", "↓"]; label: Translation.tr("Move") }
                        KeyHint { keys: ["Enter"]; label: Translation.tr("Select") }
                        KeyHint { keys: ["Esc"]; label: Translation.tr("Close") }
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
