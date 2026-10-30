import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
// Polkit prompt, styled like the lock screen card: badge, message, password pill, two pill buttons
Item {
    id: root
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true
    Keys.onPressed: event => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            PolkitService.cancel();
        }
    }
    function submit() {
        PolkitService.submit(inputField.text);
    }
    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            if (!PolkitService.interactionAvailable) return;
            inputField.text = "";
            inputField.forceActiveFocus();
        }
        function onFailedChanged() {
            if (PolkitService.failed) shakeAnim.restart();
        }
    }
    Rectangle { // Scrim
        anchors.fill: parent
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
    StyledRectangularShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: shakeTranslate.x
        width: 400
        height: cardColumn.implicitHeight + 28 * 2
        radius: Appearance.rounding.verylarge
        color: Appearance.m3colors.m3surfaceContainer
        scale: 0.94
        opacity: 0
        Component.onCompleted: { scale = 1; opacity = 1; }
        Behavior on scale {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        QtObject {
            id: shakeTranslate
            property real x: 0
        }
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shakeTranslate; property: "x"; to: -14; duration: 50 }
            NumberAnimation { target: shakeTranslate; property: "x"; to: 14; duration: 50 }
            NumberAnimation { target: shakeTranslate; property: "x"; to: -7; duration: 40 }
            NumberAnimation { target: shakeTranslate; property: "x"; to: 7; duration: 40 }
            NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 30 }
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 28
            }
            spacing: 16

            Rectangle { // Badge
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 56
                implicitHeight: 56
                radius: 28
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "shield_lock"
                    fill: 1
                    iconSize: 28
                    color: Appearance.colors.colPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Authentication required")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: {
                        if (!PolkitService.flow) return "";
                        const message = PolkitService.flow.message;
                        return message.endsWith(".") ? message.slice(0, -1) : message;
                    }
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
            }

            // Password pill
            Rectangle {
                id: field
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 50
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: (PolkitService.failed || inputField.activeFocus) ? 2 : 0
                border.color: PolkitService.failed ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
                MaterialSymbol {
                    id: fieldIcon
                    anchors {
                        left: parent.left
                        leftMargin: 18
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.usePasswordChars ? "lock" : "edit"
                    fill: 1
                    iconSize: 20
                    color: PolkitService.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                }
                StyledTextInput {
                    id: inputField
                    anchors {
                        left: fieldIcon.right
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 18
                        verticalCenter: parent.verticalCenter
                    }
                    clip: true
                    focus: true
                    enabled: PolkitService.interactionAvailable
                    echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
                    inputMethodHints: root.usePasswordChars ? Qt.ImhSensitiveData : Qt.ImhNone
                    onTextChanged: if (text.length > 0) PolkitService.failed = false
                    onAccepted: root.submit()
                    Keys.onPressed: event => { // Esc to close
                        if (event.key === Qt.Key_Escape) {
                            PolkitService.cancel();
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: inputField.text.length === 0
                        text: {
                            if (PolkitService.failed) return Translation.tr("Wrong password, try again");
                            if (!PolkitService.interactionAvailable) return Translation.tr("Checking…");
                            const inputPrompt = PolkitService.flow?.inputPrompt.trim() ?? "";
                            const cleaned = inputPrompt.endsWith(":") ? inputPrompt.slice(0, -1) : inputPrompt;
                            return cleaned || (root.usePasswordChars ? Translation.tr("Password") : Translation.tr("Input"));
                        }
                        color: PolkitService.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PillButton {
                    Layout.fillWidth: true
                    buttonText: Translation.tr("Cancel")
                    onClicked: PolkitService.cancel()
                }
                PillButton {
                    Layout.fillWidth: true
                    primary: true
                    enabled: PolkitService.interactionAvailable
                    buttonText: Translation.tr("Authenticate")
                    onClicked: root.submit()
                }
            }
        }
    }

    component PillButton: RippleButton {
        id: pillButton
        property bool primary: false
        implicitHeight: 44
        buttonRadius: Appearance.rounding.container
        colBackground: primary ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.m3colors.m3surfaceContainerHighest
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
        buttonColor: hovered ? colBackgroundHover : colBackground // Keep the fill when disabled (it dims instead)
        contentItem: StyledText {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: pillButton.buttonText
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: pillButton.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
    }
}
