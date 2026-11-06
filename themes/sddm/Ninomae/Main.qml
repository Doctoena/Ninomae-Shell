// Ninomae SDDM greeter, the twin of the shell's lock screen (modules/lock/LockSurface.qml): the wallpaper as it
// is, the time big in the bottom left, the password in a see-through pill with the avatar in the bottom right,
// and see-through chips in the corners: the machine top left; keyboard, battery, session and power top right.
// Same design language as the shell: rounded rectangles (squircles), not pills; the accent for what's
// active. Only the avatar (and its ring) stays round. Colors come from theme.conf, which matugen
// regenerates from the current wallpaper.
import QtQuick
import QtQuick.Effects

Item {
    id: root
    width: Screen.width
    height: Screen.height

    // ── Palette (matugen → theme.conf), with the current values as fallbacks ──
    readonly property color colBackground: config.background_color || "#14121c"
    readonly property color colContainer: config.surface_container || "#211e28"
    readonly property color colContainerHigh: config.surface_container_high || "#2b2833"
    readonly property color colOnSurface: config.on_surface || "#e6e0ee"
    readonly property color colOnSurfaceVariant: config.on_surface_variant || "#cac3d8"
    readonly property color colPrimary: config.primary || "#ccbeff"
    readonly property color colOnPrimary: config.on_primary || "#350097"
    readonly property color colSecondaryContainer: config.secondary_container || "#4d3d88"
    readonly property color colError: config.error || "#ffb4ab"
    // See-through surfaces over the wallpaper, with a hairline edge (the lock screen's chips and pill)
    readonly property color colGlass: Qt.alpha(colBackground, 0.65)
    readonly property color colGlassHover: Qt.alpha(colBackground, 0.85)
    readonly property color colEdge: Qt.alpha(colOnSurface, 0.12)
    readonly property color colPrimaryTint: Qt.alpha(colPrimary, 0.18)
    // Corner radii: the lock screen's
    readonly property int radiusChip: 12      // 34 px chips and buttons
    readonly property int radiusRow: 12       // popup rows
    readonly property int radiusPopup: 20
    readonly property int radiusPill: 22

    // ── Fonts (bundled: the sddm user cannot read ~/.local/share/fonts) ──
    FontLoader { id: fontMain; source: "fonts/RobotoFlex.ttf" }
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
    // Blur and dim from theme.conf: off unless set there (the wallpaper shows as it is, as on the lock screen)
    readonly property real blurAmount: Number(config.blur || 0)
    readonly property real dimAmount: Number(config.dim || 0)
    // The clock as the shell shows it: 12-hour without AM/PM when theme.conf says so (sync-theme.sh), else 24-hour
    readonly property bool clock12: String(config.clock12) === "true"

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

    // The wallpaper: drawn as it is, or through the blur only when theme.conf sets one. Either settles from a
    // slight zoom
    property real wallpaperScale: revealed ? 1.0 : 1.08
    Behavior on wallpaperScale { NumberAnimation { duration: 1600; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDecel } }
    Image {
        id: wallpaper
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.blurAmount <= 0
        opacity: status === Image.Ready ? 1 : 0
        scale: root.wallpaperScale
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }
    Loader {
        anchors.fill: parent
        active: root.blurAmount > 0
        sourceComponent: MultiEffect {
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: root.blurAmount
            opacity: wallpaper.status === Image.Ready ? 1 : 0
            scale: root.wallpaperScale
            Behavior on opacity { NumberAnimation { duration: 600 } }
        }
    }
    Rectangle { // An even dim, only when theme.conf asks for one
        anchors.fill: parent
        visible: root.dimAmount > 0
        color: root.colBackground
        opacity: root.dimAmount
    }
    Rectangle { // A light shade at the top for the chips, a deeper one at the foot for the time and the password
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(root.colBackground, 0.2) }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.alpha(root.colBackground, 0.75) }
        }
    }

    // Clicking empty space closes popups and returns focus to the password field
    MouseArea {
        anchors.fill: parent
        onClicked: { root.openPopup = ""; root.focusPassword() }
    }

    // ════════════════════════ Top left: the machine ════════════════════════
    Rectangle {
        x: 16
        y: root.revealed ? 16 : -50
        Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
        width: hostRow.implicitWidth + 16
        height: 34
        radius: root.radiusChip
        color: root.colGlass
        border.width: 1
        border.color: root.colEdge
        Row {
            id: hostRow
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            spacing: 8
            Rectangle {
                width: 26; height: 26; radius: 9
                color: root.colPrimaryTint
                Image { id: distroLogo; anchors.centerIn: parent; width: 15; height: 15; source: "fedora-symbolic.svg"; sourceSize: Qt.size(30, 30); visible: false }
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
    }

    // ════════════════════════ Top right: keyboard, battery, session, power ════════════════════════
    Row {
        id: topRight
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: root.revealed ? 16 : -50
        Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
        spacing: 6

        GlassChip {
            icon: "keyboard_alt"
            text: {
                const l = keyboard.layouts[keyboard.currentLayout]
                return l ? (l.longName.toLowerCase().indexOf("dvorak") >= 0 ? "dvorak" : l.shortName) : "us"
            }
            enabled: keyboard.layouts.length > 1
            onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
        }
        GlassChip { // Battery (laptops)
            visible: root.batteryPercent >= 0
            enabled: false
            icon: root.batteryCharging ? "bolt" : "battery_android_full"
            text: root.batteryPercent + "%"
            warn: root.batteryPercent <= 20 && !root.batteryCharging
        }
        GlassChip {
            id: sessionChip
            icon: "desktop_windows"
            text: root.sessionName
            active: root.openPopup === "sessions"
            enabled: sessionModel.count > 1
            showArrow: sessionModel.count > 1
            onClicked: root.openPopup = root.openPopup === "sessions" ? "" : "sessions"
        }
        Item { width: 6; height: 1 }
        GlassButton { icon: "dark_mode"; tip: "Sleep"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
        GlassButton { icon: "restart_alt"; tip: "Restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        GlassButton { icon: "power_settings_new"; tip: "Shut down"; danger: true; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    // ════════════════════════ Bottom left: the time ════════════════════════
    Column {
        anchors.left: parent.left
        anchors.leftMargin: Math.round(root.width * 0.03)
        y: root.height - height - Math.round(root.height * 0.045) + (root.revealed ? 0 : 30)
        opacity: root.revealed ? 1 : 0
        spacing: -Math.round(root.height * 0.006)
        Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDecel } }
        Behavior on opacity { NumberAnimation { duration: 700 } }
        Text {
            text: root.clock12 ? Qt.formatTime(root.now, "h:mm AP").replace(/\s*[AaPp][Mm]$/, "") : Qt.formatTime(root.now, "h:mm")
            color: root.colOnSurface
            font.family: fontExpressive.name
            font.pixelSize: Math.round(root.height * 0.2)
            font.weight: Font.DemiBold
            font.letterSpacing: -6
        }
        Label {
            leftPadding: 6
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            color: Qt.alpha(root.colOnSurface, 0.85)
            font.pixelSize: 28
            font.weight: Font.Medium
        }
    }

    // ════════════════════════ Bottom right: who, and the password ════════════════════════
    Column {
        id: loginColumn
        anchors.right: parent.right
        anchors.rightMargin: Math.round(root.width * 0.03) - root.shakeOffset
        y: root.height - height - Math.round(root.height * 0.06) + (root.revealed ? 0 : 30)
        opacity: root.revealed ? 1 : 0
        spacing: 10
        Behavior on y { NumberAnimation { duration: 650; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
        Behavior on opacity { NumberAnimation { duration: 400 } }

        // Caps lock, a wrong password or what PAM says, over the pill
        Rectangle {
            id: notice
            readonly property string message: root.infoMessage !== "" ? root.infoMessage
                : root.failed ? "Incorrect password"
                : keyboard.capsLock ? "Caps Lock is on" : ""
            readonly property bool isError: root.failed || root.infoMessage !== ""
            property string shownMessage: ""
            onMessageChanged: if (message !== "") shownMessage = message
            anchors.right: parent.right
            width: noticeRow.implicitWidth + 28
            height: message !== "" ? 34 : 0
            radius: root.radiusChip
            color: isError ? Qt.alpha(root.colError, 0.22) : root.colGlass
            border.width: 1
            border.color: root.colEdge
            opacity: message !== "" ? 1 : 0
            clip: true
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveEffects } }
            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveEffects } }
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
                    color: notice.isError ? root.colError : root.colOnSurface
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }

        // No user list (hidden users): type a username first, in a pill of its own
        Rectangle {
            visible: root.manualUser
            width: 400; height: 56
            radius: root.radiusPill
            color: root.colGlass
            border.width: manualUserInput.activeFocus ? 2 : 1
            border.color: manualUserInput.activeFocus ? Qt.alpha(root.colPrimary, 0.55) : root.colEdge
            Icon {
                id: manualIcon
                anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                text: "person"; filled: true; color: root.colPrimary; font.pixelSize: 20
            }
            TextInput {
                id: manualUserInput
                anchors { left: manualIcon.right; leftMargin: 12; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                color: root.colOnSurface
                font.family: fontMain.name
                font.variableAxes: root.mainAxes
                font.pixelSize: 16
                selectionColor: root.colSecondaryContainer
                clip: true
                onAccepted: passwordInput.forceActiveFocus()
                Label {
                    visible: !parent.text && !parent.activeFocus
                    text: "Username"
                    color: Qt.alpha(root.colOnSurface, 0.6)
                    font.pixelSize: 16
                }
            }
        }

        // The pill: the avatar (switches users when there are several), who, the password, sign in
        Rectangle {
            id: field
            width: 400
            height: 66
            radius: root.radiusPill
            color: root.colGlass
            border.width: root.failed || passwordInput.activeFocus ? 2 : 1
            border.color: root.failed ? root.colError : passwordInput.activeFocus ? Qt.alpha(root.colPrimary, 0.55) : root.colEdge
            Behavior on border.color { ColorAnimation { duration: 150 } }
            MouseArea { anchors.fill: parent; onClicked: root.focusPassword() } // Keep clicks inside the pill

            Item {
                id: avatarBox
                anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                width: 44; height: 44
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: root.failed ? root.colError : root.colPrimary
                }
                Avatar { anchors.centerIn: parent; size: 38; source: root.manualUser ? "" : root.userIcon }
                Rectangle { // Switch-user hint
                    visible: userModel.count > 1
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: -4; bottomMargin: -4 }
                    width: 20; height: 20; radius: 7
                    color: root.colPrimary
                    Icon { anchors.centerIn: parent; text: "swap_horiz"; color: root.colOnPrimary; font.pixelSize: 13 }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: userModel.count > 1
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.openPopup = root.openPopup === "users" ? "" : "users"
                }
            }

            Label { // Above the typing: who
                id: fieldTitle
                anchors { left: avatarBox.right; leftMargin: 12; right: confirmButton.left; rightMargin: 10; top: parent.top; topMargin: 13 }
                elide: Text.ElideRight
                text: root.manualUser ? root.greeting() : root.greeting() + ", " + (root.userRealName || root.userName)
                color: root.colOnSurfaceVariant
                font.pixelSize: 13
            }

            TextInput {
                id: passwordInput
                anchors { left: fieldTitle.left; right: fieldTitle.right; top: fieldTitle.bottom; topMargin: 1 }
                height: 24
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: "transparent"           // the shapes below are drawn by hand
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                cursorDelegate: Item {}
                font.pixelSize: 16
                enabled: !root.busy
                focus: true
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                onTextChanged: if (text.length > 0) { root.failed = false; root.infoMessage = "" }
                onAccepted: root.login()
                Keys.onEscapePressed: text = ""
            }

            Label {
                anchors { left: passwordInput.left; verticalCenter: passwordInput.verticalCenter }
                visible: passwordInput.text.length === 0
                text: root.busy ? "Signing in…" : "Password"
                color: Qt.alpha(root.colOnSurface, 0.6)
                font.pixelSize: 16
            }

            // Material-shape password characters, like quickshell's PasswordChars.qml
            Item {
                anchors { left: passwordInput.left; right: passwordInput.right; top: passwordInput.top; bottom: passwordInput.bottom }
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
                        width: 2; height: 18; radius: 1
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
                anchors { right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter }
                width: 44; height: 44
                radius: 15 // The lock screen's unlock button
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

    // ════════════════════════ Popups ════════════════════════
    PopupCard { // Rises over the pill, from the avatar
        shown: root.openPopup === "users"
        x: loginColumn.x + loginColumn.width - width
        y: loginColumn.y + field.y - height - 10 + (shown ? 0 : 12)
        transformOrigin: Item.Bottom
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

    PopupCard { // Drops from the session chip
        shown: root.openPopup === "sessions"
        x: Math.min(root.width - width - 16, sessionChip.mapToItem(root, 0, 0).x)
        y: topRight.y + 34 + 8 + (shown ? 0 : -12)
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
        NumberAnimation { target: root; property: "shakeOffset"; to: -18; duration: 50 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 18; duration: 50 }
        NumberAnimation { target: root; property: "shakeOffset"; to: -9; duration: 40 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 9; duration: 40 }
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

    // A see-through chip: icon and text, clickable when enabled; tinted while its popup is open
    component GlassChip: Rectangle {
        id: chip
        property string icon
        property string text
        property bool active: false
        property bool warn: false
        property bool showArrow: false
        signal clicked()
        height: 34
        width: chipRow.implicitWidth + 22
        radius: root.radiusChip
        color: active ? Qt.alpha(root.colPrimary, 0.3) : (chipMouse.containsMouse && enabled) ? root.colGlassHover : root.colGlass
        border.width: 1
        border.color: root.colEdge
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; text: chip.icon; filled: true; color: chip.warn ? root.colError : root.colPrimary; font.pixelSize: 17 }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                color: chip.warn ? root.colError : chip.active ? root.colPrimary : root.colOnSurface
                font.pixelSize: 14
                width: Math.min(implicitWidth, 220)
                elide: Text.ElideRight
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.showArrow
                text: "expand_more"
                color: chip.active ? root.colPrimary : root.colOnSurfaceVariant
                font.pixelSize: 18
                rotation: chip.active ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveDrawerOpen } }
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.enabled
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }
    }

    // A see-through power button
    component GlassButton: Rectangle {
        id: btn
        property string icon
        property string tip
        property bool danger: false
        signal clicked()
        width: 34; height: 34
        radius: root.radiusChip
        color: !btnMouse.containsMouse ? root.colGlass : danger ? Qt.alpha(root.colError, 0.3) : root.colGlassHover
        border.width: 1
        border.color: root.colEdge
        scale: btnMouse.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveFastSpatial } }
        Icon {
            anchors.centerIn: parent
            text: btn.icon
            color: btnMouse.containsMouse && btn.danger ? root.colError : root.colOnSurface
            font.pixelSize: 18
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
            color: root.colSecondaryContainer
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
        border.width: 1
        border.color: root.colEdge
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
        radius: root.radiusRow
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
                width: 30; height: 30; radius: 10
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
