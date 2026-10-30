// Ninomae SDDM greeter, the twin of the shell's lock screen (modules/lock/LockSurface.qml): a floating
// top bar (logo, date, keyboard, battery, session, power), a big centred clock, and a solid login card.
// Same design language as the shell: rounded rectangles (squircles), not pills; neutral surfaces, with
// the accent kept for what's active. Only the avatar (and its ring) stays round, as on the lock screen.
// Colors come from theme.conf, which matugen regenerates from the current wallpaper.
import QtQuick
import QtQuick.Effects

Item {
    id: root
    width: Screen.width
    height: Screen.height

    // ── Palette (matugen → theme.conf), with the current values as fallbacks ──
    readonly property color colBackground: config.background_color || "#14121c"
    readonly property color colContainerLow: config.surface_container_low || "#1c1a24"
    readonly property color colContainer: config.surface_container || "#211e28"
    readonly property color colContainerHigh: config.surface_container_high || "#2b2833"
    readonly property color colContainerHighest: config.surface_container_highest || "#36333e"
    readonly property color colOnSurface: config.on_surface || "#e6e0ee"
    readonly property color colOnSurfaceVariant: config.on_surface_variant || "#cac3d8"
    readonly property color colOutline: config.outline || "#948ea1"
    readonly property color colOutlineVariant: config.outline_variant || "#494455"
    readonly property color colPrimary: config.primary || "#ccbeff"
    readonly property color colOnPrimary: config.on_primary || "#350097"
    readonly property color colPrimaryFixed: config.primary_fixed || "#e7deff"
    readonly property color colSecondaryContainer: config.secondary_container || "#4d3d88"
    readonly property color colOnSecondaryContainer: config.on_secondary_container || "#e8dfff"
    readonly property color colTertiary: config.tertiary || "#ffabee"
    readonly property color colError: config.error || "#ffb4ab"
    readonly property color colErrorContainer: config.error_container || "#93000a"
    readonly property color colOnErrorContainer: config.on_error_container || "#ffdad6"
    // Tinted badge background, like the shell's icon badges
    readonly property color colPrimaryTint: Qt.alpha(colPrimary, 0.18)
    // Corner radii: the shell's tokens (Appearance.rounding.chip / segment / container) and the lock
    // screen's larger pieces
    readonly property int radiusChip: 9       // 28 px chips, badges
    readonly property int radiusSegment: 10   // 30 px buttons
    readonly property int radiusContainer: 12 // 36–44 px rows and notices
    readonly property int radiusBar: 14
    readonly property int radiusField: 16
    readonly property int radiusPopup: 20
    readonly property int radiusCard: 32

    // ── Fonts (bundled: the sddm user cannot read ~/.local/share/fonts) ──
    FontLoader { id: fontMain; source: "fonts/RobotoFlex.ttf" }
    FontLoader { id: fontNumbers; source: "fonts/Rubik.ttf" }
    FontLoader { id: fontExpressive; source: "fonts/SpaceGrotesk.ttf" }
    FontLoader { id: fontIcons; source: "fonts/MaterialSymbolsRounded.ttf" }
    // Same Roboto Flex tuning as quickshell's Appearance.font.variableAxes.main
    readonly property var mainAxes: ({ "YTUC": 716, "YTFI": 716, "YTAS": 716, "YTLC": 490, "XTRA": 488, "wdth": 105, "GRAD": 175, "wght": 350 })

    // ── Motion: the shell's drawer and expressive curves ──
    readonly property var curveDrawerOpen: [0.12, 0.9, 0.22, 1.08, 1, 1]
    readonly property var curveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
    readonly property var curveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
    readonly property var curveDecel: [0.05, 0.7, 0.1, 1, 1, 1]

    // ── State ──
    property date now: new Date()
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property string userName: userModel.lastUser
    property string userRealName: ""
    property string userIcon: ""
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string sessionName: ""
    readonly property bool manualUser: userModel.count === 0
    property bool busy: false
    property bool failed: false
    property string infoMessage: ""
    property string openPopup: ""   // "", "users", "sessions"
    property bool revealed: false
    property real shakeOffset: 0
    // Laptop battery, read from sysfs (needs QML_XHR_ALLOW_FILE_READ=1, set in 99-ninomae-theme.conf).
    // -1 = no battery (or not readable): the chip stays hidden
    property int batteryPercent: -1
    property bool batteryCharging: false

    function login() {
        const user = manualUser ? manualUserInput.text.trim() : userName
        if (user.length === 0) {
            manualUserInput.forceActiveFocus()
            return
        }
        busy = true
        failed = false
        infoMessage = ""
        sddm.login(user, passwordInput.text, sessionIndex)
    }

    function focusPassword() {
        if (manualUser && manualUserInput.text.length === 0)
            manualUserInput.forceActiveFocus()
        else
            passwordInput.forceActiveFocus()
    }

    function greeting() {
        const h = now.getHours()
        if (h < 5) return "Up late"
        if (h < 12) return "Good morning"
        if (h < 18) return "Good afternoon"
        return "Good evening"
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    function readSysfs(path, done) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => { if (xhr.readyState === XMLHttpRequest.DONE) done(xhr.responseText.trim()) }
        xhr.open("GET", "file://" + path)
        xhr.send()
    }
    function readBattery() {
        for (const name of ["BAT0", "BAT1", "BAT2"]) {
            const dir = "/sys/class/power_supply/" + name
            readSysfs(dir + "/capacity", text => {
                const value = parseInt(text)
                if (isNaN(value)) return
                root.batteryPercent = value
                readSysfs(dir + "/status", status => root.batteryCharging = status === "Charging" || status === "Full")
            })
        }
    }
    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.readBattery()
    }

    // ════════════════════════ Background ════════════════════════
    Rectangle { anchors.fill: parent; color: root.colBackground }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: Number(config.blur || 0.55)
        saturation: 0.08
        opacity: wallpaper.status === Image.Ready ? 1 : 0
        scale: root.revealed ? 1.0 : 1.08
        Behavior on scale { NumberAnimation { duration: 1600; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDecel } }
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }

    // Tint toward the palette's background so text stays legible on light wallpapers
    Rectangle {
        anchors.fill: parent
        color: root.colBackground
        opacity: Number(config.dim || 0.42)
    }
    Rectangle { // Soft vignette at the bottom, under the card
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(root.colBackground, 0.25) }
            GradientStop { position: 0.4; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.alpha(root.colBackground, 0.6) }
        }
    }

    // Clicking empty space closes popups and returns focus to the password field
    MouseArea {
        anchors.fill: parent
        onClicked: { root.openPopup = ""; root.focusPassword() }
    }

    // ════════════════════════ Top bar (like the desktop's floating bar) ════════════════════════
    Rectangle {
        id: topBar
        x: 8
        width: root.width - 16
        height: 40
        y: root.revealed ? 6 : -height - 10
        radius: root.radiusBar
        color: Qt.alpha(root.colBackground, 0.92)
        Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }

        // Left: distro logo badge + hostname
        Row {
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 10
            Rectangle {
                width: 28; height: 28; radius: root.radiusChip
                color: root.colPrimaryTint
                Image { id: distroLogo; anchors.centerIn: parent; width: 16; height: 16; source: "fedora-symbolic.svg"; sourceSize: Qt.size(32, 32); visible: false }
                MultiEffect { anchors.fill: distroLogo; source: distroLogo; brightness: 1; colorization: 1; colorizationColor: root.colPrimary }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: sddm.hostName
                color: root.colOnSurface
                font.pixelSize: 14
                font.weight: Font.Medium
            }
        }

        // Centre: date
        Label {
            anchors.centerIn: parent
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            color: root.colOnSurfaceVariant
            font.pixelSize: 14
        }

        // Right: keyboard layout, session, power
        Row {
            id: barRight
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 4

            ChipButton {
                width: kbRow.implicitWidth + 22
                enabled: keyboard.layouts.length > 1
                onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
                Row {
                    id: kbRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; text: "keyboard_alt"; filled: true; color: root.colPrimary; font.pixelSize: 18 }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const l = keyboard.layouts[keyboard.currentLayout]
                            return l ? (l.longName.toLowerCase().indexOf("dvorak") >= 0 ? "dvorak" : l.shortName) : "us"
                        }
                        color: root.colOnSurface
                        font.pixelSize: 13
                    }
                }
            }

            ChipButton { // Battery (laptops), like the lock screen's
                id: batteryChip
                visible: root.batteryPercent >= 0
                enabled: false
                readonly property bool low: root.batteryPercent <= 20 && !root.batteryCharging
                width: batRow.implicitWidth + 22
                Row {
                    id: batRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.batteryCharging ? "bolt" : "battery_android_full"
                        filled: true
                        color: batteryChip.low ? root.colError : root.colPrimary
                        font.pixelSize: 17
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.batteryPercent + "%"
                        color: batteryChip.low ? root.colError : root.colOnSurface
                        font.pixelSize: 13
                    }
                }
            }

            ChipButton {
                id: sessionChip
                width: sessionRow.implicitWidth + 22
                active: root.openPopup === "sessions"
                enabled: sessionModel.count > 1
                onClicked: root.openPopup = root.openPopup === "sessions" ? "" : "sessions"
                Row {
                    id: sessionRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; text: "desktop_windows"; filled: true; color: root.colPrimary; font.pixelSize: 17 }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sessionName
                        color: sessionChip.active ? root.colPrimary : root.colOnSurface
                        font.pixelSize: 13
                        width: Math.min(implicitWidth, 220)
                        elide: Text.ElideRight
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: sessionModel.count > 1
                        text: "expand_more"
                        color: sessionChip.active ? root.colPrimary : root.colOnSurfaceVariant
                        font.pixelSize: 18
                        rotation: sessionChip.active ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
                    }
                }
            }

            Rectangle {
                visible: sddm.canSuspend || sddm.canReboot || sddm.canPowerOff
                width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter
                color: root.colOutlineVariant
            }

            IconButton { icon: "dark_mode"; tip: "Sleep"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
            IconButton { icon: "restart_alt"; tip: "Restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
            IconButton { icon: "power_settings_new"; tip: "Shut down"; danger: true; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
        }
    }

    // ════════════════════════ Clock ════════════════════════
    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.13 + (root.revealed ? 0 : -24)
        opacity: root.revealed ? 1 : 0
        Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDecel } }
        Behavior on opacity { NumberAnimation { duration: 700 } }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.colBackground
            shadowOpacity: 0.5
            shadowBlur: 1.0
            shadowVerticalOffset: 2
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "h:mm")
            color: root.colOnSurface
            font.family: fontExpressive.name
            font.pixelSize: Math.round(root.height * 0.15)
            font.weight: Font.DemiBold
            font.letterSpacing: -4
        }
    }

    // ════════════════════════ Login card ════════════════════════
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.shakeOffset
        y: root.height * 0.47 + (root.revealed ? 0 : 40)
        width: 380
        height: cardColumn.implicitHeight + 56
        radius: root.radiusCard
        color: Qt.alpha(root.colBackground, 0.94)
        opacity: root.revealed ? 1 : 0
        Behavior on y { NumberAnimation { duration: 650; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
        Behavior on opacity { NumberAnimation { duration: 400 } }
        MouseArea { anchors.fill: parent; onClicked: root.focusPassword() } // Keep clicks inside the card

        Column {
            id: cardColumn
            anchors { top: parent.top; topMargin: 28; left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 }
            spacing: 18

            // Avatar with a lavender ring; click to switch users when there are several
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                visible: !root.manualUser
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: root.colPrimary
                }
                Avatar { anchors.centerIn: parent; size: 82; source: root.userIcon }
                Rectangle { // Switch-user hint
                    visible: userModel.count > 1
                    anchors { right: parent.right; bottom: parent.bottom }
                    width: 30; height: 30; radius: root.radiusSegment
                    color: root.colPrimary
                    border.width: 3
                    border.color: root.colBackground
                    Icon { anchors.centerIn: parent; text: "swap_horiz"; color: root.colOnPrimary; font.pixelSize: 16 }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: userModel.count > 1
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.openPopup = root.openPopup === "users" ? "" : "users"
                }
            }

            // Greeting + name
            Column {
                id: nameBlock
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                visible: !root.manualUser
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.greeting()
                    color: root.colOnSurfaceVariant
                    font.pixelSize: 14
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.userRealName || root.userName
                    color: root.colOnSurface
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }
            }

            // No user list (e.g. hidden users): type a username instead
            Rectangle {
                visible: root.manualUser
                width: parent.width; height: 52; radius: root.radiusField
                color: root.colContainerHigh
                border.width: manualUserInput.activeFocus ? 2 : 0
                border.color: Qt.alpha(root.colPrimary, 0.55)
                Icon {
                    id: manualIcon
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    text: "person"; filled: true; color: root.colPrimary; font.pixelSize: 20
                }
                TextInput {
                    id: manualUserInput
                    anchors { left: manualIcon.right; leftMargin: 10; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    color: root.colOnSurface
                    font.family: fontMain.name
                    font.variableAxes: root.mainAxes
                    font.pixelSize: 15
                    selectionColor: root.colSecondaryContainer
                    clip: true
                    onAccepted: passwordInput.forceActiveFocus()
                    Label {
                        visible: !parent.text && !parent.activeFocus
                        text: "Username"
                        color: root.colOnSurfaceVariant
                        font.pixelSize: 15
                    }
                }
            }

            // Password field with the sign-in button inside
            Rectangle {
                id: field
                width: parent.width
                height: 52
                radius: root.radiusField
                color: root.colContainerHigh
                border.width: root.failed ? 2 : passwordInput.activeFocus ? 2 : 0
                border.color: root.failed ? root.colError : Qt.alpha(root.colPrimary, 0.55)
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Icon {
                    id: lockIcon
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    text: "lock"
                    filled: true
                    color: root.failed ? root.colError : root.colPrimary
                    font.pixelSize: 19
                }

                TextInput {
                    id: passwordInput
                    anchors { left: lockIcon.right; leftMargin: 10; right: confirmButton.left; rightMargin: 10; top: parent.top; bottom: parent.bottom }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: "transparent"           // the shapes below are drawn by hand
                    selectionColor: "transparent"
                    selectedTextColor: "transparent"
                    cursorDelegate: Item {}
                    font.pixelSize: 15
                    enabled: !root.busy
                    focus: true
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    onTextChanged: if (text.length > 0) { root.failed = false; root.infoMessage = "" }
                    onAccepted: root.login()
                    Keys.onEscapePressed: text = ""
                }

                Label {
                    anchors { left: passwordInput.left; verticalCenter: parent.verticalCenter }
                    visible: passwordInput.text.length === 0
                    text: root.busy ? "Signing in…" : "Password"
                    color: root.colOnSurfaceVariant
                    font.pixelSize: 15
                }

                // Material-shape password characters, like quickshell's PasswordChars.qml
                Item {
                    anchors { left: passwordInput.left; right: passwordInput.right; top: parent.top; bottom: parent.bottom }
                    clip: true
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.min(0, parent.width - width - 4)
                        spacing: 6
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Repeater {
                            model: passwordInput.text.length
                            delegate: Icon {
                                id: dot
                                required property int index
                                readonly property var shapes: ["circle", "pentagon", "star", "hexagon", "square", "diamond", "favorite"]
                                text: shapes[index % shapes.length]
                                filled: true
                                font.pixelSize: 17
                                color: root.colPrimary
                                scale: 0.4
                                opacity: 0
                                Component.onCompleted: appear.start()
                                ParallelAnimation {
                                    id: appear
                                    NumberAnimation { target: dot; property: "opacity"; to: 1; duration: 60 }
                                    NumberAnimation { target: dot; property: "scale"; to: 1; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveFastSpatial }
                                    ColorAnimation { target: dot; property: "color"; to: root.colOnSurface; duration: 1000 }
                                }
                            }
                        }

                        Rectangle { // Caret
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2; height: 20; radius: 1
                            color: root.colPrimary
                            visible: passwordInput.activeFocus && !root.busy
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 1; duration: 500 }
                                NumberAnimation { to: 0; duration: 500 }
                            }
                        }
                    }
                }

                Rectangle {
                    id: confirmButton
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40
                    radius: 13 // The lock screen's unlock button
                    color: confirmMouse.pressed ? Qt.darker(root.colPrimary, 1.08)
                         : confirmMouse.containsMouse ? Qt.lighter(root.colPrimary, 1.06) : root.colPrimary
                    scale: confirmMouse.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveFastSpatial } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Icon {
                        anchors.centerIn: parent
                        text: root.busy ? "progress_activity" : "arrow_forward"
                        color: root.colOnPrimary
                        font.pixelSize: 22
                        RotationAnimator on rotation {
                            running: root.busy
                            from: 0; to: 360; duration: 900
                            loops: Animation.Infinite
                        }
                        onTextChanged: if (!root.busy) rotation = 0
                    }
                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.busy
                        onClicked: root.login()
                    }
                }
            }
        }
    }

    // ════════════════════════ Notice (caps lock / errors / PAM messages) ════════════════════════
    Rectangle {
        id: notice
        readonly property string message: root.infoMessage !== "" ? root.infoMessage
            : root.failed ? "Incorrect password"
            : keyboard.capsLock ? "Caps Lock is on" : ""
        readonly property bool isError: root.failed || root.infoMessage !== ""
        property string shownMessage: ""
        onMessageChanged: if (message !== "") shownMessage = message

        anchors.horizontalCenter: card.horizontalCenter
        y: card.y + card.height + (message !== "" ? 14 : 4)
        width: noticeRow.implicitWidth + 28
        height: 34
        radius: root.radiusContainer
        color: isError ? Qt.alpha(root.colError, 0.18) : root.colPrimaryTint
        opacity: message !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveEffects } }
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveFastSpatial } }
        Behavior on color { ColorAnimation { duration: 200 } }

        Row {
            id: noticeRow
            anchors.centerIn: parent
            spacing: 8
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: notice.isError ? "error" : "keyboard_capslock_badge"
                filled: true
                color: notice.isError ? root.colError : root.colPrimary
                font.pixelSize: 18
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: notice.shownMessage
                color: notice.isError ? root.colError : root.colPrimary
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    // ════════════════════════ Popups ════════════════════════
    PopupCard {
        shown: root.openPopup === "users"
        x: card.x + (card.width - width) / 2
        y: card.y + 132 + (shown ? 0 : -12)
        transformOrigin: Item.Top
        Repeater {
            model: userModel
            delegate: PopupItem {
                required property int index
                required property string name
                required property string realName
                required property string icon
                readonly property bool current: index === root.userIndex
                selected: current
                label: realName || name
                sublabel: realName ? name : ""
                avatar: icon
                onCurrentChanged: if (current) { root.userName = name; root.userRealName = realName; root.userIcon = icon }
                Component.onCompleted: {
                    if (name === userModel.lastUser) root.userIndex = index
                    if (current) { root.userName = name; root.userRealName = realName; root.userIcon = icon }
                }
                onClicked: { root.userIndex = index; root.openPopup = ""; passwordInput.text = ""; root.focusPassword() }
            }
        }
    }

    PopupCard { // Drops from the session chip in the top bar
        shown: root.openPopup === "sessions"
        x: Math.min(root.width - width - 8, sessionChip.mapToItem(root, 0, 0).x)
        y: topBar.y + topBar.height + 8 + (shown ? 0 : -12)
        transformOrigin: Item.Top
        Repeater {
            model: sessionModel
            delegate: PopupItem {
                required property int index
                required property string name
                readonly property bool current: index === root.sessionIndex
                selected: current
                label: name
                iconName: "desktop_windows"
                onCurrentChanged: if (current) root.sessionName = name
                Component.onCompleted: if (current) root.sessionName = name
                onClicked: { root.sessionIndex = index; root.openPopup = ""; root.focusPassword() }
            }
        }
    }

    // ════════════════════════ Wrong-password shake ════════════════════════
    SequentialAnimation {
        id: shake
        NumberAnimation { target: root; property: "shakeOffset"; to: -24; duration: 50 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 24; duration: 50 }
        NumberAnimation { target: root; property: "shakeOffset"; to: -12; duration: 40 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 12; duration: 40 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 30 }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failed = true
            passwordInput.text = ""
            shake.restart()
            root.focusPassword()
        }
        function onLoginSucceeded() {
            root.revealed = false
        }
        function onInformationMessage(message) {
            root.infoMessage = message
        }
    }

    Keys.onEscapePressed: root.openPopup = ""

    Component.onCompleted: {
        revealed = true
        focusPassword()
    }

    // ════════════════════════ Components ════════════════════════
    component Label: Text {
        font.family: fontMain.name
        font.variableAxes: root.mainAxes
        renderType: Text.NativeRendering
    }

    // Same approach as quickshell's MaterialSymbol: curve rendering avoids artifacts on filled glyphs
    component Icon: Text {
        property bool filled: false
        renderType: filled ? Text.CurveRendering : Text.NativeRendering
        font.family: fontIcons.name
        font.hintingPreference: Font.PreferFullHinting
        font.variableAxes: ({ "FILL": filled ? 1 : 0, "opsz": 24 })
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Chip in the top bar (the lock screen's BarChip); tinted while its popup is open
    component ChipButton: Rectangle {
        id: chip
        property bool active: false
        signal clicked()
        height: 28
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: root.radiusChip
        color: active ? root.colPrimaryTint
             : (chipMouse.containsMouse && enabled) ? root.colContainerHighest : root.colContainerHigh
        Behavior on color { ColorAnimation { duration: 150 } }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.enabled
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }
    }

    // Icon button in the top bar (power actions), the lock screen's BarIconButton
    component IconButton: Rectangle {
        id: btn
        property string icon
        property string tip
        property bool danger: false
        signal clicked()
        width: 30; height: 30
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: root.radiusSegment
        color: !btnMouse.containsMouse ? "transparent" : danger ? Qt.alpha(root.colError, 0.2) : root.colPrimaryTint
        scale: btnMouse.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveFastSpatial } }
        Icon {
            anchors.centerIn: parent
            text: btn.icon
            color: btnMouse.containsMouse && btn.danger ? root.colError : root.colOnSurfaceVariant
            font.pixelSize: 19
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component Avatar: Item {
        id: avatar
        property string source
        property real size: 28
        width: size; height: size
        // sddm's stock placeholder face looks out of place; use the M3 account icon instead
        readonly property bool hasImage: img.status === Image.Ready && source.indexOf("/.face.icon") < 0
        Image {
            id: img
            anchors.fill: parent
            source: avatar.source ? avatar.source : ""
            sourceSize: Qt.size(avatar.size * 2, avatar.size * 2)
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            visible: avatar.hasImage
            source: img
            maskEnabled: true
            maskSource: avatarMask
        }
        Rectangle {
            anchors.fill: parent
            visible: !avatar.hasImage
            radius: width / 2
            color: root.colPrimaryTint
            Icon { anchors.centerIn: parent; text: "person"; filled: true; color: root.colPrimary; font.pixelSize: avatar.size * 0.6 }
        }
    }

    // Solid popup card (users / sessions)
    component PopupCard: Rectangle {
        id: popupCard
        property bool shown: false
        default property alias items: list.data
        width: Math.max(240, list.implicitWidth + 16)
        height: list.implicitHeight + 16
        radius: root.radiusPopup
        color: root.colContainer
        opacity: shown ? 1 : 0
        visible: opacity > 0
        scale: shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveEffects } }
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
        Column {
            id: list
            anchors { fill: parent; margins: 8 }
            spacing: 2
        }
    }

    component PopupItem: Rectangle {
        id: item
        property bool selected: false
        property string label
        property string sublabel
        property string avatar
        property string iconName
        signal clicked()
        width: 290
        height: sublabel ? 54 : 44
        radius: root.radiusContainer
        // Neutral row; the chosen one shows as an accent squircle behind its icon and its name in accent
        // (the shell's Wi-Fi / Bluetooth menus)
        color: itemMouse.containsMouse ? root.colContainerHigh : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 12
            Avatar { visible: item.iconName === ""; anchors.verticalCenter: parent.verticalCenter; size: 36; source: item.avatar }
            Rectangle {
                visible: item.iconName !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: root.radiusSegment
                color: item.selected ? root.colPrimary : root.colContainerHigh
                Behavior on color { ColorAnimation { duration: 120 } }
                Icon { anchors.centerIn: parent; text: item.iconName; filled: item.selected; font.pixelSize: 17; color: item.selected ? root.colOnPrimary : root.colOnSurfaceVariant }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: item.width - x - 52   // leave room for the check mark
                Label { width: parent.width; elide: Text.ElideRight; text: item.label; font.pixelSize: 14; font.weight: item.selected ? Font.DemiBold : Font.Normal; color: item.selected ? root.colPrimary : root.colOnSurface }
                Label { visible: item.sublabel !== ""; text: item.sublabel; font.pixelSize: 12; color: root.colOnSurfaceVariant }
            }
        }
        Icon {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            visible: item.selected
            text: "check"
            font.pixelSize: 20
            color: root.colPrimary
        }
        MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.clicked()
        }
    }
}
