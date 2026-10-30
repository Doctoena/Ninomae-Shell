import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
RadioButton {
    id: root
    padding: 6
    implicitHeight: contentItem.implicitHeight + padding * 2
    property string description
    property color activeColor: Appearance?.colors.colPrimary ?? "#685496"
    property color inactiveColor: Appearance?.m3colors.m3onSurfaceVariant ?? "#45464F"
    PointingHandInteraction {}
    indicator: Item{}
    background: Rectangle {
        radius: Appearance.rounding.verysmall
        color: root.checked ?
            ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88) :
            (root.hovered ? ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.93) : "transparent")
        Behavior on color {
            animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
    contentItem: RowLayout {
        id: contentItem
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            id: radio
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            width: 18
            height: 18
            radius: Appearance?.rounding.full
            border.color: checked ? root.activeColor : root.inactiveColor
            border.width: 2
            color: "transparent"
            Behavior on border.color {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Rectangle {
                anchors.centerIn: parent
                width: checked ? 10 : 4
                height: checked ? 10 : 4
                radius: Appearance?.rounding.full
                color: Appearance?.colors.colPrimary
                opacity: checked ? 1 : 0
                Behavior on opacity {
                    animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance?.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance?.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }
        StyledText {
            text: root.description
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.weight: root.checked ? Font.DemiBold : Font.Normal
            color: root.checked ? Appearance?.colors.colOnSurface : Appearance?.colors.colOnSurfaceVariant
            Behavior on color {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}