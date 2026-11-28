import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The password prompt's card, joined pieces like the app search: what's asking (a shield with a halo, the
 * action's own description, its message with the names in bold, Details), the password field (you, the dots,
 * Caps Lock, show/hide) and Cancel / Authenticate. Checking: the dots dim and a spinner turns. Wrong: it all
 * turns red (Polkit.qml shakes it).
 */
ColumnLayout {
    id: root
    spacing: 4
    readonly property var flow: PolkitService.flow
    readonly property bool wrong: PolkitService.failed
    readonly property bool checking: !PolkitService.interactionAvailable && !wrong
    readonly property bool secret: !(flow?.responseVisible ?? false)
    property bool showText: false // The eye: what's typed shows
    property bool detailsOpen: false
    property color tint: wrong ? Appearance.colors.colError : Appearance.colors.colPrimary
    Behavior on tint { ColorAnimation { duration: 250 } }

    // Kept from the request, so the card still reads right while it slides away after it ends
    property string message: ""
    property string actionId: ""
    property var actionInfo: ({}) // action id → { description, vendor }, from pkaction
    onFlowChanged: {
        if (!flow) return;
        message = flow.message;
        actionId = flow.actionId;
        detailsOpen = false;
        showText = false;
        inputField.text = "";
        if (actionInfo[actionId] === undefined) {
            infoProcess.forId = actionId;
            infoProcess.command = ["pkaction", "--action-id", actionId, "--verbose"];
            infoProcess.running = true;
        }
    }
    readonly property var info: actionInfo[actionId] ?? {}
    Process {
        id: infoProcess
        property string forId // Filed under the action it was asked about, even if another request came since
        stdout: StdioCollector {
            onStreamFinished: {
                const field = name => (text.match(new RegExp(`^\\s*${name}:\\s*(.*)$`, "m"))?.[1] ?? "").trim();
                root.actionInfo = Object.assign({}, root.actionInfo, {
                    [infoProcess.forId]: { description: field("description"), vendor: field("vendor") }
                });
            }
        }
    }
    // The message, with names in quotes in bold ('sshd.service', `/usr/bin/true', “Wi-Fi”)
    readonly property string messageHtml: StringUtils.escapeHtml(message)
        .replace(/(?:&#39;|`|‘|“|&quot;)([^`'’”"&]+?)(?:&#39;|’|”|&quot;)/g, "<b>$1</b>")

    function submit() {
        if (!PolkitService.interactionAvailable) return;
        PolkitService.submit(inputField.text);
    }
    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            if (!PolkitService.interactionAvailable) return;
            inputField.text = "";
            inputField.forceActiveFocus();
        }
    }

    // ── What's asking ──
    Rectangle {
        id: card
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 32
        topLeftRadius: Appearance.rounding.normal
        topRightRadius: Appearance.rounding.normal
        bottomLeftRadius: Appearance.rounding.joined
        bottomRightRadius: Appearance.rounding.joined
        color: ColorUtils.mix(Appearance.colors.colLayer3, root.tint, 0.88)
        border.width: 1.5
        border.color: ColorUtils.transparentize(root.tint, 0.6)
        clip: true
        Behavior on implicitHeight {
            NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
        }

        Halo { // A soft halo behind the shield
            colour: root.tint
            strength: 0.38
            reach: 42
            centreX: shieldTile.x + shieldTile.width / 2
            centreY: shieldTile.y + shieldTile.height / 2
        }
        Rectangle {
            id: shieldTile
            x: 16
            y: 16
            width: 56
            height: 56
            radius: width * 0.28
            color: Appearance.colors.colLayer4
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)
            MaterialSymbol {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                text: root.wrong ? "gpp_bad" : "shield_lock"
                iconSize: 32
                fill: 1
                color: root.tint
            }
        }
        ColumnLayout {
            id: cardColumn
            anchors { left: shieldTile.right; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 16 }
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.wrong ? Translation.tr("Wrong password") : Translation.tr("Authentication required")
                font.family: Appearance.font.family.title
                font.weight: Font.Black
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.wrong ? Appearance.colors.colError : Appearance.colors.colOnLayer3
            }
            StyledText { // The action's own description ("Manage system services or other units")
                Layout.fillWidth: true
                visible: text !== ""
                text: root.info.description ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: ColorUtils.mix(Appearance.colors.colSubtext, root.tint, 0.65)
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 8
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                text: root.messageHtml
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnLayer3
            }
            StyledText { // Anything the system adds ("Too many attempts", an account note)
                Layout.fillWidth: true
                visible: text !== ""
                wrapMode: Text.Wrap
                text: root.flow?.supplementaryMessage ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: (root.flow?.supplementaryIsError ?? false) ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
            RippleButton { // Details: what exactly is being allowed, and whose it is
                Layout.topMargin: 6
                Layout.leftMargin: -8
                implicitHeight: 26
                implicitWidth: detailsRow.implicitWidth + 16
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.8)
                onClicked: root.detailsOpen = !root.detailsOpen
                contentItem: Item {
                    RowLayout {
                        id: detailsRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                            rotation: root.detailsOpen ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 160 } }
                        }
                        StyledText {
                            text: Translation.tr("Details")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.detailsOpen
                columns: 2
                columnSpacing: 10
                rowSpacing: 2
                StyledText {
                    text: Translation.tr("Action")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.actionId
                    wrapMode: Text.WrapAnywhere
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    visible: (root.info.vendor ?? "") !== ""
                    text: Translation.tr("From")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (root.info.vendor ?? "") !== ""
                    text: root.info.vendor ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer3
                }
            }
        }
    }

    // ── The password ──
    Rectangle {
        id: field
        Layout.fillWidth: true
        implicitHeight: 48
        radius: Appearance.rounding.joined
        color: Appearance.colors.colLayer3
        border.width: 1.5
        border.color: root.wrong ? Appearance.colors.colError
            : ColorUtils.transparentize(Appearance.colors.colPrimary, root.checking ? 0.85 : 0.55)
        Behavior on border.color { ColorAnimation { duration: 200 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
            spacing: 10
            Avatar { // Whose password it wants
                implicitWidth: 28
                implicitHeight: 28
                editable: false
                border.width: 0
            }
            StyledText {
                text: root.flow?.selectedIdentity?.displayName || SystemInfo.username
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Rectangle {
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.colors.colLayer4
            }
            StyledTextInput {
                id: inputField
                Layout.fillWidth: true
                clip: true
                focus: true
                enabled: PolkitService.interactionAvailable
                opacity: root.checking ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: 150 } }
                echoMode: root.secret && !root.showText ? TextInput.Password : TextInput.Normal
                passwordCharacter: "●"
                inputMethodHints: root.secret ? Qt.ImhSensitiveData : Qt.ImhNone
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer3
                onTextChanged: if (text.length > 0) PolkitService.failed = false
                onAccepted: root.submit()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        PolkitService.cancel();
                        event.accepted = true;
                    }
                }
                StyledText { // Placeholder
                    anchors.verticalCenter: parent.verticalCenter
                    visible: inputField.text.length === 0 && !root.checking
                    text: {
                        if (root.wrong) return Translation.tr("Try again");
                        const prompt = (root.flow?.inputPrompt ?? "").trim().replace(/:$/, "");
                        return prompt || (root.secret ? Translation.tr("Password") : Translation.tr("Answer"));
                    }
                    color: root.wrong ? Appearance.colors.colError : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            Rectangle { // Caps Lock: the usual reason for a wrong password
                visible: CapsLock.capsLockActive && root.secret
                implicitWidth: capsRow.implicitWidth + 14
                implicitHeight: 24
                radius: 7
                color: ColorUtils.transparentize(Appearance.colors.colError, 0.84)
                RowLayout {
                    id: capsRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: "keyboard_capslock"
                        iconSize: 14
                        color: Appearance.colors.colError
                    }
                    StyledText {
                        text: Translation.tr("Caps Lock")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colError
                    }
                }
            }
            MaterialSymbol { // Checking
                visible: root.checking
                text: "progress_activity"
                iconSize: 18
                color: Appearance.colors.colPrimary
                RotationAnimation on rotation {
                    running: root.checking
                    from: 0; to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }
            RippleButton { // Show or hide what's typed
                visible: root.secret && !root.checking
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.8)
                focusPolicy: Qt.NoFocus
                onClicked: root.showText = !root.showText
                StyledToolTip { text: root.showText ? Translation.tr("Hide password") : Translation.tr("Show password") }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: root.showText ? "visibility_off" : "visibility"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Cancel / Authenticate ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        PromptButton {
            // Narrow after a wrong password: trying again is the big target
            Layout.preferredWidth: root.wrong ? 120 : (root.width - 4) / 2
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            buttonRadiusBottomLeft: Appearance.rounding.normal // The group's bottom-left corner
            label: Translation.tr("Cancel")
            keyHint: "Esc"
            onClicked: PolkitService.cancel()
        }
        PromptButton {
            Layout.fillWidth: true
            primary: true
            enabled: PolkitService.interactionAvailable
            buttonRadiusBottomRight: Appearance.rounding.normal // The group's bottom-right corner
            label: root.checking ? Translation.tr("Checking…") : Translation.tr("Authenticate")
            keyHint: root.checking ? "" : "↵"
            onClicked: root.submit()
        }
    }

    component PromptButton: RippleButton {
        id: promptButton
        property bool primary: false
        property string label
        property string keyHint
        implicitHeight: 44
        buttonRadius: Appearance.rounding.joined
        focusPolicy: Qt.NoFocus // Keys stay in the field
        colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
        buttonColor: hovered ? colBackgroundHover : colBackground // Keeps its fill while disabled (it dims instead)
        opacity: enabled ? 1 : 0.55
        contentItem: Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                StyledText {
                    text: promptButton.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: promptButton.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                }
                StyledText {
                    visible: promptButton.keyHint !== ""
                    text: promptButton.keyHint
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: promptButton.primary ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.35) : Appearance.colors.colSubtext
                }
            }
        }
    }
}
