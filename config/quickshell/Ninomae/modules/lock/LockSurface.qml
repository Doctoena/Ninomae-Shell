// Lock screen, styled like the login screen: blurred wallpaper, a floating top bar,
// a big clock and a solid card with the avatar and password pill.
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
    readonly property color colPrimaryTint: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
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
    Image {
        id: wallpaper
        anchors.fill: parent
        source: Config.wallpaperPath
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: Config.options.lock.blur.enable
        blurMax: 64
        blur: Math.min(1, Config.options.lock.blur.radius / 64)
        saturation: 0.08
        opacity: wallpaper.status === Image.Ready ? 1 : 0
        scale: root.revealed ? 1 : Config.options.lock.blur.extraZoom
        Behavior on scale {
            NumberAnimation {
                duration: 1200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standardDecel
            }
        }
    }
    Rectangle { // Tint toward the background so text stays legible
        anchors.fill: parent
        color: Appearance.m3colors.m3background
        opacity: 0.42
    }
    Rectangle { // Soft vignette at the bottom, under the card
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.75) }
            GradientStop { position: 0.4; color: "transparent" }
            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.4) }
        }
    }

    // ════════════════════════ Top bar ════════════════════════
    Rectangle {
        id: topBar
        x: 8
        width: root.width - 16
        height: 40
        y: root.revealed ? 6 : -height - 10
        radius: 14
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.08)
        Behavior on y {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }

        // Left: distro badge + user
        RowLayout {
            anchors {
                left: parent.left
                leftMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 10
            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 9
                color: root.colPrimaryTint
                CustomIcon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colPrimary
                }
            }
            StyledText {
                text: SystemInfo.username
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
        }

        // Centre: date
        StyledText {
            anchors.centerIn: parent
            text: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM d")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }

        // Right: keyboard layout, battery, power actions
        RowLayout {
            anchors {
                right: parent.right
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 4
            BarChip {
                icon: "keyboard_alt"
                text: HyprlandXkb.currentLayoutCode
                visible: text.length > 0
            }
            BarChip {
                visible: Battery.available
                icon: Battery.icon // Follows the level, like the bar's
                text: Battery.percent + "%"
                warn: Battery.isLowAndUnplugged
            }
            Rectangle {
                implicitWidth: 1
                implicitHeight: 18
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Appearance.colors.colOutlineVariant
            }
            BarIconButton {
                iconName: "dark_mode"
                onClicked: Session.suspend()
            }
            GuardedBarIconButton {
                iconName: "restart_alt"
                targetAction: LockContext.ActionEnum.Reboot
            }
            GuardedBarIconButton {
                iconName: "power_settings_new"
                targetAction: LockContext.ActionEnum.Poweroff
            }
        }
    }

    // ════════════════════════ Clock ════════════════════════
    StyledText {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.13 + (root.revealed ? 0 : -24)
        opacity: root.revealed ? 1 : 0
        Behavior on y {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        text: DateTime.time
        color: Appearance.colors.colOnLayer0
        font.family: Appearance.font.family.expressive
        font.pixelSize: Math.round(root.height * 0.15)
        font.weight: Font.DemiBold
        font.letterSpacing: -4
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Appearance.m3colors.m3background
            shadowOpacity: 0.5
            shadowBlur: 1.0
            shadowVerticalOffset: 2
        }
    }

    // ════════════════════════ Card ════════════════════════
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.47 + (root.revealed ? 0 : 40)
        width: 380
        height: cardColumn.implicitHeight + 56
        radius: 32
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.06)
        opacity: root.revealed ? 1 : 0
        Behavior on y {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                top: parent.top
                topMargin: 28
                left: parent.left
                right: parent.right
                leftMargin: 24
                rightMargin: 24
            }
            spacing: 18

            // Avatar with a lavender ring: ~/.face, or the first letter of the username
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 96
                implicitHeight: 96
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: Appearance.colors.colPrimary
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 82
                    height: 82
                    radius: width / 2
                    color: Appearance.colors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        visible: avatarImage.status !== Image.Ready
                        text: SystemInfo.username.charAt(0).toUpperCase()
                        font.family: Appearance.font.family.expressive
                        font.pixelSize: 36
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
                        anchors.fill: parent
                        source: faceFile.loaded ? `file://${faceFile.path}` : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(164, 164)
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: RoundedMask { maskWidth: 82; maskHeight: 82; radius: 41 }
                    }
                }
            }

            // Greeting + name
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.greeting()
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: SystemInfo.username
                    font.pixelSize: Appearance.font.pixelSize.hugeass - 6
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
            }

            // Password pill with the unlock button inside
            Rectangle {
                id: field
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 16
                color: Appearance.m3colors.m3surfaceContainerHigh
                readonly property bool failed: root.context.showFailure
                border.width: (failed || passwordInput.activeFocus) ? 2 : 0
                border.color: failed ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
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

                MaterialSymbol {
                    id: lockIcon
                    anchors {
                        left: parent.left
                        leftMargin: 18
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.context.fingerprintsConfigured ? "fingerprint" : "lock"
                    fill: 1
                    iconSize: 20
                    color: field.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                }
                StyledTextInput {
                    id: passwordInput
                    anchors {
                        left: lockIcon.right
                        leftMargin: 12
                        right: unlockButton.left
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    clip: true
                    enabled: !root.context.unlockInProgress
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    // Dots are drawn by PasswordChars when material shapes are on
                    readonly property bool materialShapeChars: Config.options.lock.materialShapeChars
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
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
                        color: field.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
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
                    anchors {
                        right: parent.right
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: 13
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

            // Hint under the field: pending power action, or fingerprint
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: text.length > 0
                text: root.context.targetAction === LockContext.ActionEnum.Poweroff ? Translation.tr("Enter your password to shut down")
                    : root.context.targetAction === LockContext.ActionEnum.Reboot ? Translation.tr("Enter your password to reboot")
                    : root.context.fingerprintsConfigured ? Translation.tr("Or touch the fingerprint sensor")
                    : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ════════════════════════ Components ════════════════════════
    component BarChip: Rectangle {
        id: chip
        property string icon
        property string text
        property bool warn: false
        implicitHeight: 28
        implicitWidth: chipRow.implicitWidth + 20
        radius: 9
        color: Appearance.m3colors.m3surfaceContainerHigh
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
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: chip.warn ? Appearance.colors.colError : Appearance.colors.colOnLayer0
            }
        }
    }
    component BarIconButton: RippleButton {
        id: barButton
        property string iconName
        property bool danger: false
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: 10
        colBackground: "transparent"
        colBackgroundHover: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.8) : root.colPrimaryTint
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: barButton.iconName
            iconSize: 19
            color: barButton.toggled ? Appearance.colors.colOnPrimary
                : (barButton.danger && barButton.hovered) ? Appearance.colors.colError
                : Appearance.colors.colOnSurfaceVariant
        }
    }
    // Shut down / reboot: asks for the password first when the setting is on
    component GuardedBarIconButton: BarIconButton {
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
