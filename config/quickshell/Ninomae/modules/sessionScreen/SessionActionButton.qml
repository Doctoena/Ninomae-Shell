import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
// A power menu action: a big tile (icon badge + label, its key in the corner) or, with `compact`, a piece of the
// strip under the tiles; both pieces of one joined group (the menu sets each corner).
// Hover or keyboard focus, as the rest of the shell shows "active": the tile takes a light tint and a soft glow,
// its icon a solid accent squircle and its name the accent (error red for the ones that end the session).
// While `countdown` > 0 the action is about to run: a tile shows the seconds in its badge with a ring running out
// around it and says what's happening; the strip's piece shows the number and a bar. `dimmed`: another one is
// counting down
RippleButton {
    id: button
    property string buttonIcon
    property bool compact: false
    property bool keyboardDown: false
    property bool destructive: false // Ends the session: lit in the error colour instead of the accent
    property int countdown: 0
    property int countdownFrom: 5
    property string keyHint: "" // Its letter, in a tile's corner
    property string pendingText: "" // What a tile says while counting down ("Shutting down")
    property bool dimmed: false // Another action is counting down
    readonly property bool pending: countdown > 0
    // 1 → 0 over the countdown: the ring and the bar
    property real timeFraction: 1
    onPendingChanged: pending ? drain.restart() : drain.stop()
    NumberAnimation {
        id: drain
        target: button
        property: "timeFraction"
        from: 1
        to: 0
        duration: button.countdownFrom * 1000
    }
    opacity: dimmed ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: 180 } }
    readonly property color accent: destructive ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property color onAccent: destructive ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
    readonly property bool active: button.focus || button.hovered || button.down || button.keyboardDown || button.pending

    implicitWidth: compact ? compactRow.implicitWidth + 32 : 128
    implicitHeight: compact ? 44 : 120
    // Its corners: slight, as a piece inside the menu's joined group (the strip's pieces set their own). A press squeezes it
    buttonRadius: Appearance.rounding.normal // The ripple's clip
    buttonRadiusTopLeft: Appearance.rounding.joined
    buttonRadiusTopRight: Appearance.rounding.joined
    buttonRadiusBottomLeft: Appearance.rounding.joined
    buttonRadiusBottomRight: Appearance.rounding.joined
    scale: (button.down || button.keyboardDown) ? 0.97 : 1 // A small press: it sits in a joined group
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    colBackground: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
    colRipple: ColorUtils.transparentize(button.accent, 0.75)
    background.implicitWidth: implicitWidth
    background.implicitHeight: implicitHeight
    // Keyboard focus looks the same as hover, with a light tint of its colour; counting down, a stronger one
    buttonColor: pending ? ColorUtils.mix(button.accent, colBackgroundHover, 0.16)
        : active ? ColorUtils.mix(button.accent, colBackgroundHover, compact ? 0.04 : 0.08) : colBackground
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
        Rectangle { // A tile's key, in its corner
            visible: !button.compact && button.keyHint !== "" && !button.pending
            anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 2 }
            implicitWidth: keyText.implicitWidth + 12
            implicitHeight: 20
            radius: 6
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.92)
            opacity: button.active ? 1 : 0.6
            StyledText {
                id: keyText
                anchors.centerIn: parent
                text: button.keyHint
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
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
                Halo { // A soft glow behind it while it's the one you're on (z below: under the badge)
                    z: -1
                    visible: opacity > 0
                    opacity: button.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    colour: button.accent
                    strength: 0.4
                    reach: 40
                    centreX: parent.width / 2
                    centreY: parent.height / 2
                }
                Shape { // Counting down: a ring around the badge that runs out
                    visible: button.pending
                    anchors.centerIn: parent
                    width: 66
                    height: 66
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: button.accent
                        strokeWidth: 3
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 33; centerY: 33; radiusX: 31; radiusY: 31
                            startAngle: -90
                            sweepAngle: 360 * button.timeFraction
                        }
                    }
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
                text: button.pending && button.pendingText !== "" ? button.pendingText : button.buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: button.colContent
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
        // Wide button: icon (or the countdown) + label in a row
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
        // A strip piece's time left: a bar along the bottom that runs out (a tile has its ring)
        Rectangle {
            visible: button.pending && button.compact
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 10; bottomMargin: 4 }
            width: (parent.width - 20) * button.timeFraction
            height: 3
            radius: 2
            color: button.accent
        }
    }
}
