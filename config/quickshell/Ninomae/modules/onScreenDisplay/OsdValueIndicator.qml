import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
// Flat value row (icon badge, name + value, progress bar); the OSD drawer draws the background
Item {
    id: root
    required property real value
    required property string icon
    required property string name
    property bool rotateIcon: false
    property bool scaleIcon: false
    implicitWidth: Appearance.sizes.osdWidth + 60
    implicitHeight: 44
    RowLayout {
        anchors.fill: parent
        spacing: 12
        Rectangle { // Icon: a solid accent squircle, like the quick toggles' icons
            implicitWidth: 44
            implicitHeight: 44
            radius: 14
            color: Appearance.colors.colPrimary
            MaterialSymbol {
                anchors {
                    centerIn: parent
                    alignWhenCentered: !root.rotateIcon
                }
                color: Appearance.colors.colOnPrimary
                renderType: Text.QtRendering
                text: root.icon
                iconSize: 20 + 4 * (root.scaleIcon ? root.value : 1)
                rotation: 180 * (root.rotateIcon ? root.value : 0)
                Behavior on iconSize {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 6
            RowLayout {
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    text: root.name
                }
                StyledText {
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    text: Math.round(root.value * 100) + "%"
                }
            }
            StyledProgressBar {
                Layout.fillWidth: true
                value: root.value
            }
        }
    }
}
