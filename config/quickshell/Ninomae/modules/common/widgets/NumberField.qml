import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * A number you can type, in a small box (a slider row's value, top right). Shows `value`; Enter or clicking
 * away keeps what you typed, kept between `from` and `to` (either way round) with `decimals` places, and calls
 * accepted(newValue). Esc puts the old value back, Up and Down step it by `stepSize`. A click selects it all, so
 * typing replaces it.
 */
Rectangle {
    id: root
    // In a glass window (`glass: true`: Settings, the control centre): Appearance's colWindowGlass* shades
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    property real value: 0
    property real from: 0
    property real to: 100
    property int decimals: 0
    property real stepSize: 1
    // Plain (the control centre, Settings): the number big on the card with its `unit` after, a box only while
    // pointed at or typed in
    property bool plain: false
    property string unit: ""
    signal accepted(real newValue)
    readonly property string shown: value.toFixed(decimals)
    implicitWidth: plain ? Math.max(36, input.contentWidth + (unitLabel.visible ? unitLabel.implicitWidth + 3 : 0) + 16)
        : Math.max(52, input.contentWidth + 22)
    implicitHeight: 30
    radius: Appearance.rounding.chip
    color: input.activeFocus ? Appearance.m3colors.m3surfaceContainerHighest
        : plain ? (boxHover.hovered ? (glass ? Appearance.colors.colLayer4Hover : Appearance.m3colors.m3surfaceContainerHigh) : "transparent")
        : glass ? (boxHover.hovered ? Appearance.colors.colWellRowActive : Appearance.colors.colWellRowHover)
        : boxHover.hovered ? Appearance.m3colors.m3surfaceContainerHigh : ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerHigh, 0.4)
    border.width: input.activeFocus ? 2 : 0
    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    HoverHandler { id: boxHover; cursorShape: Qt.IBeamCursor }
    GlassFinish { // A box (not plain) on glass: lifted like the buttons
        visible: root.glass && !root.plain && !input.activeFocus
        radius: root.radius
        hovered: boxHover.hovered
    }

    // Between from and to, with `decimals` places
    function clamp(n) {
        const low = Math.min(root.from, root.to), high = Math.max(root.from, root.to);
        return Number(Math.max(low, Math.min(high, n)).toFixed(root.decimals));
    }
    function keep() {
        const typed = parseFloat(input.text.replace(",", "."));
        if (isNaN(typed)) { input.text = root.shown; return; }
        const kept = root.clamp(typed);
        input.text = kept.toFixed(root.decimals);
        if (kept !== root.value) root.accepted(kept);
    }
    function step(direction) {
        const typed = parseFloat(input.text.replace(",", "."));
        const kept = root.clamp((isNaN(typed) ? root.value : typed) + direction * root.stepSize);
        input.text = kept.toFixed(root.decimals);
        input.selectAll();
        if (kept !== root.value) root.accepted(kept);
    }

    StyledTextInput {
        id: input
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: unitLabel.visible ? -(unitLabel.implicitWidth + 3) / 2 : 0
        width: root.plain ? Math.max(8, contentWidth + 2) : parent.width - 16
        horizontalAlignment: TextInput.AlignHCenter
        text: root.shown
        // As StyledText shows plain numbers: Rubik, without Roboto Flex's axes or full hinting (those made it odd)
        font.family: Appearance.font.family.numbers
        font.variableAxes: ({})
        font.hintingPreference: Font.PreferDefaultHinting
        font.pixelSize: root.plain ? 20 : Appearance.font.pixelSize.small
        font.weight: Font.Medium
        selectByMouse: true
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        validator: RegularExpressionValidator { regularExpression: /^-?\d*[.,]?\d*$/ }
        onActiveFocusChanged: if (activeFocus) selectAll(); else root.keep()
        onAccepted: { root.keep(); focus = false; }
        Keys.onEscapePressed: event => { text = root.shown; focus = false; event.accepted = true; }
        Keys.onUpPressed: event => { root.step(1); event.accepted = true; }
        Keys.onDownPressed: event => { root.step(-1); event.accepted = true; }
        Connections { // A change from the slider (or the option) shows, unless you're typing
            target: root
            function onShownChanged() { if (!input.activeFocus) input.text = root.shown; }
        }
    }
    StyledText { // The unit, small after the number
        id: unitLabel
        visible: root.plain && root.unit !== ""
        anchors { left: input.right; leftMargin: 3; baseline: input.baseline }
        text: root.unit
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
    }
}
