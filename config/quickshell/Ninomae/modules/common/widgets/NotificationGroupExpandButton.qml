import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
RippleButton { // Expand button
    id: root
    required property int count
    required property bool expanded
    property real fontSize: Appearance.font.pixelSize.smaller
    property real iconSize: Appearance.font.pixelSize.normal
    implicitHeight: fontSize + 4 * 2
    implicitWidth: Math.max(contentItem.implicitWidth + 5 * 2, 28)
    Layout.alignment: Qt.AlignVCenter
    Layout.fillHeight: false
    buttonRadius: 9 // Rounded rectangle, like the rest of the shell
    colBackground: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.92)
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.85)
    colRipple: Appearance.colors.colLayer3Active
    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: contentRow.implicitWidth
        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 2
            StyledText {
                Layout.leftMargin: 4
                visible: root.count > 1
                text: root.count
                font.pixelSize: root.fontSize
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: root.iconSize
                color: Appearance.colors.colOnSurfaceVariant
                rotation: expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
