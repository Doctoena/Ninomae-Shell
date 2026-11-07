// Lock screen: the wallpaper as it is (blurred only when that's on in Settings), the time big in the bottom
// left over a soft shade, and the password in a see-through pill with the avatar in the bottom right.
// Keyboard layout, battery, weather and the power buttons are see-through chips in the top right.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
MouseArea {
    id: root
    required property LockContext context
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property color glass: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
    readonly property color glassHover: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.15)
    readonly property color edge: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
    property bool revealed: false

    function forceFieldFocus() {
        passwordInput.forceActiveFocus();
    }
    function greeting() {
        const h = DateTime.clock.date.getHours();
        if (h < 5) return Translation.tr("Up late");
        if (h < 12) return Translation.tr("Good morning");
        if (h < 18) return Translation.tr("Good afternoon");
        return Translation.tr("Good evening");
    }
    Connections {
        target: root.context
        function onShouldReFocus() {
            root.forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => root.forceFieldFocus()
    onPositionChanged: mouse => root.forceFieldFocus()
    Component.onCompleted: {
        forceFieldFocus();
        revealed = true;
    }
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Escape) // Esc to clear
            root.context.currentText = "";
        forceFieldFocus();
    }

    // ════════════════════════ Background ════════════════════════
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3background
    }
    // The wallpaper: drawn as it is, or through the blur only when that's on (no effect pass otherwise). Either
    // settles from a slight zoom as it locks
    readonly property bool blurred: Config.options.lock.blur.enable
    property real wallpaperScale: revealed ? 1 : Config.options.lock.blur.extraZoom
    Behavior on wallpaperScale {
        NumberAnimation {
            duration: 1200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standardDecel
        }
    }
    Image {
        id: wallpaper
        anchors.fill: parent
        // The wallpaper's size version for this screen's shape, as the desktop shows (WallpaperVariants)
        source: WallpaperVariants.forScreen(Config.wallpaperPath, root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: true
        visible: !root.blurred
        opacity: status === Image.Ready ? 1 : 0
        scale: root.wallpaperScale
    }
    Loader {
        anchors.fill: parent
        active: root.blurred
        sourceComponent: MultiEffect {
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: Math.min(1, Config.options.lock.blur.radius / 64)
            opacity: wallpaper.status === Image.Ready ? 1 : 0
            scale: root.wallpaperScale
        }
    }
    Rectangle { // A light shade at the top for the chips, a deeper one at the foot for the time and the password
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.8) }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.25) }
        }
    }

    // ════════════════════════ Top right: status and power ════════════════════════
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: root.revealed ? 16 : -50
        spacing: 6
        Behavior on y {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        GlassChip {
            icon: "keyboard_alt"
            text: HyprlandXkb.currentLayoutCode
            visible: text.length > 0
        }
        GlassChip {
            visible: Battery.available
            icon: Battery.icon // Follows the level, like the bar's
            text: Battery.percent + "%"
            warn: Battery.isLowAndUnplugged
        }
        GlassChip {
            visible: Weather.enabled && (Weather.data.temp ?? "") !== ""
            icon: Weather.data.icon ?? "cloud"
            text: Weather.data.temp ?? ""
        }
        Item { width: 6; height: 1 }
        GlassButton {
            iconName: "dark_mode"
            tip: Translation.tr("Sleep")
            onClicked: Session.suspend()
        }
        GuardedGlassButton {
            iconName: "restart_alt"
            tip: Translation.tr("Restart")
            targetAction: LockContext.ActionEnum.Reboot
        }
        GuardedGlassButton {
            iconName: "power_settings_new"
            tip: Translation.tr("Shut down")
            targetAction: LockContext.ActionEnum.Poweroff
        }
    }

    // ════════════════════════ Bottom left: the time ════════════════════════
    Column {
        anchors.left: parent.left
        anchors.leftMargin: Math.round(root.width * 0.03)
        y: root.height - height - Math.round(root.height * 0.045) + (root.revealed ? 0 : 30)
        opacity: root.revealed ? 1 : 0
        spacing: -Math.round(root.height * 0.006)
        Behavior on y {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        StyledText {
            text: DateTime.time
            color: Appearance.colors.colOnLayer0
            font.family: Appearance.font.family.expressive
            font.pixelSize: Math.round(root.height * 0.2)
            font.weight: Font.DemiBold
            font.letterSpacing: -6
        }
        StyledText {
            leftPadding: 6
            text: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM d")
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.15)
            font.pixelSize: Appearance.font.pixelSize.hugeass
            font.weight: Font.Medium
        }
    }

    // ════════════════════════ Bottom right: the password ════════════════════════
    Column {
        anchors.right: parent.right
        anchors.rightMargin: Math.round(root.width * 0.03)
        y: root.height - height - Math.round(root.height * 0.06) + (root.revealed ? 0 : 30)
        opacity: root.revealed ? 1 : 0
        spacing: 10
        Behavior on y {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Rectangle {
            id: field
            width: 400
            height: 66
            radius: 22
            color: root.glass
            readonly property bool failed: root.context.showFailure
            border.width: failed || passwordInput.activeFocus ? 2 : 1
            border.color: failed ? Appearance.colors.colError
                : passwordInput.activeFocus ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : root.edge
            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            // Shake on a wrong password
            transform: Translate { id: shakeTranslate }
            SequentialAnimation {
                id: wrongPasswordShakeAnim
                NumberAnimation { target: shakeTranslate; property: "x"; to: -18; duration: 50 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: 18; duration: 50 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: -9; duration: 40 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: 9; duration: 40 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 30 }
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // Avatar with an accent ring: ~/.face, or the first letter of the username
            Rectangle {
                id: avatar
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: width / 2
                color: Appearance.colors.colSecondaryContainer
                border.width: 2
                border.color: field.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    visible: avatarImage.status !== Image.Ready
                    text: SystemInfo.username.charAt(0).toUpperCase()
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
                FileView { // Only load ~/.face when there is one
                    id: faceFile
                    path: `${FileUtils.trimFileProtocol(Directories.home)}/.face`
                    printErrors: false
                }
                StyledImage {
                    id: avatarImage
                    anchors.centerIn: parent
                    width: 38
                    height: 38
                    source: faceFile.loaded ? `file://${faceFile.path}` : ""
                    cache: false // A new picture (Settings → your picture) under the same path
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(88, 88)
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.effect: RoundedMask { maskWidth: 38; maskHeight: 38; radius: 19 }
                }
            }

            // Above the typing: who (or what the password is for), and the field
            StyledText {
                id: fieldTitle
                anchors.left: avatar.right
                anchors.leftMargin: 12
                anchors.right: unlockButton.left
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.topMargin: 13
                elide: Text.ElideRight
                text: root.context.targetAction === LockContext.ActionEnum.Poweroff ? Translation.tr("Enter your password to shut down")
                    : root.context.targetAction === LockContext.ActionEnum.Reboot ? Translation.tr("Enter your password to restart")
                    : Translation.tr("%1, %2").arg(root.greeting()).arg(SystemInfo.username)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.context.targetAction !== LockContext.ActionEnum.Unlock ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledTextInput {
                id: passwordInput
                anchors.left: fieldTitle.left
                anchors.right: fieldTitle.right
                anchors.top: fieldTitle.bottom
                anchors.topMargin: 1
                height: 24
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                enabled: !root.context.unlockInProgress
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                font.pixelSize: Appearance.font.pixelSize.normal
                // Dots are drawn by PasswordChars when material shapes are on
                readonly property bool materialShapeChars: Config.options.lock.materialShapeChars
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, materialShapeChars ? 1 : 0)
                onTextChanged: root.context.currentText = text
                onAccepted: root.context.tryUnlock()
                Keys.onPressed: event => root.context.resetClearTimer()
                Connections {
                    target: root.context
                    function onCurrentTextChanged() {
                        passwordInput.text = root.context.currentText;
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: passwordInput.text.length === 0
                    text: field.failed ? Translation.tr("Incorrect password")
                        : root.context.unlockInProgress ? Translation.tr("Checking…")
                        : Translation.tr("Password")
                    color: field.failed ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
                Loader {
                    active: passwordInput.materialShapeChars
                    anchors.fill: parent
                    sourceComponent: PasswordChars {
                        length: root.context.currentText.length
                    }
                }
            }
            RippleButton {
                id: unlockButton
                anchors.right: parent.right
                anchors.rightMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: 15
                enabled: !root.context.unlockInProgress
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.context.tryUnlock()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    iconSize: 22
                    text: root.context.targetAction === LockContext.ActionEnum.Poweroff ? "power_settings_new"
                        : root.context.targetAction === LockContext.ActionEnum.Reboot ? "restart_alt"
                        : "arrow_forward"
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        // Under the pill: the fingerprint sensor works too
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 8
            visible: root.context.fingerprintsConfigured
            text: Translation.tr("Or touch the fingerprint sensor")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
        }
    }

    // ════════════════════════ Components ════════════════════════
    // See-through, with a hairline edge, as the launcher's chips on art
    component GlassChip: Rectangle {
        id: chip
        property string icon
        property string text
        property bool warn: false
        implicitHeight: 34
        implicitWidth: chipRow.implicitWidth + 22
        radius: 12
        color: root.glass
        border.width: 1
        border.color: root.edge
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: chip.icon
                fill: 1
                iconSize: 17
                color: chip.warn ? Appearance.colors.colError : Appearance.colors.colPrimary
            }
            StyledText {
                text: chip.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: chip.warn ? Appearance.colors.colError : Appearance.colors.colOnLayer0
            }
        }
    }
    component GlassButton: RippleButton {
        id: glassButton
        property string iconName
        property string tip
        property bool danger: false
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: 12
        colBackground: root.glass
        colBackgroundHover: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.75) : root.glassHover
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: glassButton.iconName
            iconSize: 18
            color: glassButton.toggled ? Appearance.colors.colOnPrimary
                : (glassButton.danger && glassButton.hovered) ? Appearance.colors.colError
                : Appearance.colors.colOnLayer0
        }
        Rectangle { // Hairline edge
            anchors.fill: parent
            radius: 12
            color: "transparent"
            visible: !glassButton.toggled
            border.width: 1
            border.color: root.edge
        }
        StyledToolTip { text: glassButton.tip }
    }
    // Shut down / restart: asks for the password first when the setting is on
    component GuardedGlassButton: GlassButton {
        id: guardedBtn
        required property var targetAction
        danger: targetAction === LockContext.ActionEnum.Poweroff
        toggled: root.context.targetAction === guardedBtn.targetAction
        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }
}
