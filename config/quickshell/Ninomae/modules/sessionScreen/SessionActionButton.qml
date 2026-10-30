import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
// A power menu action: a big tile (icon badge + label) or, with `compact`, a pill.
// Hover or keyboard focus, as the rest of the shell shows "active": the tile stays neutral (a step lighter),
// its icon gets a solid accent squircle and its name turns accent (error red for the ones that end the session).
// While `countdown` > 0 the action is about to run: the number takes the icon's place and a bar runs out
RippleButton {
    id: button
    property string buttonIcon
    property bool compact: false
    property bool keyboardDown: false
    property bool destructive: false // Ends the session: lit in the error colour instead of the accent
    property int countdown: 0
    property int countdownFrom: 5
    readonly property bool pending: countdown > 0
    onPendingChanged: pending ? drain.restart() : drain.stop()
    readonly property color accent: destructive ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property color onAccent: destructive ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
    readonly property bool active: button.focus || button.hovered || button.down || button.keyboardDown || button.pending

    implicitWidth: compact ? compactRow.implicitWidth + 32 : 128
    implicitHeight: compact ? 44 : 128
    // Tiles round out a little when active (Material 3 shape morph); a press squeezes the button
    buttonRadius: compact ? 12 : (active ? Appearance.rounding.verylarge : Appearance.rounding.large)
    Behavior on buttonRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (button.down || button.keyboardDown) ? 0.94 : 1
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    colBackground: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
    colRipple: ColorUtils.transparentize(button.accent, 0.75)
    background.implicitWidth: implicitWidth
    background.implicitHeight: implicitHeight
    // Keyboard focus looks the same as hover. Counting down, the tile takes a tint of the action's colour
    buttonColor: pending ? ColorUtils.mix(button.accent, colBackgroundHover, 0.16) : active ? colBackgroundHover : colBackground
    Behavior on buttonColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    readonly property color colContent: active ? button.accent : Appearance.colors.colOnLayer1

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            keyboardDown = true;
            button.clicked();
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            keyboardDown = false;
            event.accepted = true;
        }
    }

    contentItem: Item {
        // Tile: a squircle badge with the icon (or the countdown), the label underneath
        ColumnLayout {
            visible: !button.compact
            anchors.centerIn: parent
            spacing: 12
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 52
                implicitHeight: 52
                radius: 17 // Squircle, like the quick toggles' icons
                scale: button.active ? 1.08 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                color: button.active ? button.accent : ColorUtils.transparentize(button.accent, 0.84)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                MaterialSymbol {
                    visible: !button.pending
                    anchors.centerIn: parent
                    text: button.buttonIcon
                    iconSize: 26
                    fill: button.active ? 1 : 0
                    color: button.active ? button.onAccent : button.accent
                    Behavior on fill { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                StyledText {
                    visible: button.pending
                    anchors.centerIn: parent
                    text: button.countdown
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.DemiBold
                    color: button.onAccent
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: button.buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: button.colContent
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
        // Pill: icon (or the countdown) + label in a row
        RowLayout {
            id: compactRow
            visible: button.compact
            anchors.centerIn: parent
            spacing: 8
            Item {
                implicitWidth: 20
                implicitHeight: 20
                MaterialSymbol {
                    visible: !button.pending
                    anchors.centerIn: parent
                    text: button.buttonIcon
                    iconSize: 20
                    color: button.accent
                }
                StyledText {
                    visible: button.pending
                    anchors.centerIn: parent
                    text: button.countdown
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.DemiBold
                    color: button.accent
                }
            }
            StyledText {
                text: button.buttonText
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Medium
                color: button.colContent
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
        // Time left: a bar along the bottom that runs out with the countdown
        Rectangle {
            id: timeLeft
            visible: button.pending
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: button.compact ? 10 : 16; bottomMargin: button.compact ? 4 : 10 }
            readonly property real full: parent.width - (button.compact ? 20 : 32)
            height: 3
            radius: 2
            color: button.accent
            NumberAnimation on width {
                id: drain
                running: false
                from: timeLeft.full
                to: 0
                duration: button.countdownFrom * 1000
            }
        }
    }
}
