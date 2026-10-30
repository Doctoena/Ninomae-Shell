import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root
    property real baseHeight: 35
    property real radius: Appearance.rounding.small
    property real innerButtonRadius: Appearance.rounding.unsharpen
    editable: true
    opacity: root.enabled ? 1 : 0.4
    // The option buttons' surface (colLayer2 barely shows on a settings card); −/+ light up on hover
    readonly property color colSurface: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colButtonHover: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colButtonPressed: ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHighest, Appearance.colors.colOnLayer2, 0.85)
    background: Rectangle {
        color: root.colSurface
        radius: root.radius
    }
    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth, 40)
        StyledTextInput {
            id: labelText
            anchors.centerIn: parent
            text: root.value // displayText would make the numbers weird like 1,000 instead of 1000
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            validator: root.validator
            onTextChanged: {
                root.value = parseFloat(text);
                if (activeFocus) root.valueModified(); // Typed in: counts as a change, like the buttons
            }
        }
    }
    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.radius
        bottomLeftRadius: root.radius
        topRightRadius: root.innerButtonRadius
        bottomRightRadius: root.innerButtonRadius
        color: root.down.pressed ? root.colButtonPressed :
            root.down.hovered ? root.colButtonHover : ColorUtils.transparentize(root.colSurface)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.radius
        bottomRightRadius: root.radius
        topLeftRadius: root.innerButtonRadius
        bottomLeftRadius: root.innerButtonRadius
        color: root.up.pressed ? root.colButtonPressed :
            root.up.hovered ? root.colButtonHover : ColorUtils.transparentize(root.colSurface)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
}
