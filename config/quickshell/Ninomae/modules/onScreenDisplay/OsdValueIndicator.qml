import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
// One row of the on-screen display (the drawer draws the background): the icon on a squircle, in the accent
// while on (active) and quiet while off, as the quick toggles; the name, the value at the end (valueText, a
// percentage by default, or a pill: Caps Lock's On/Off), and a bar under them (showBar). Past full (a volume
// boost, value > 1) the value and bar turn red
Item {
    id: root
    property real value: 0
    required property string icon
    required property string name
    property string valueText: Math.round(value * 100) + "%"
    property bool active: true
    property bool showBar: true
    property bool valuePill: false
    property bool rotateIcon: false
    property bool scaleIcon: false
    readonly property bool boosted: value > 1.005
    readonly property color accent: boosted ? Appearance.colors.colError : Appearance.colors.colPrimary
    implicitWidth: Appearance.sizes.osdWidth + 60
    implicitHeight: 44
    RowLayout {
        anchors.fill: parent
        spacing: 12
        Rectangle {
            implicitWidth: 44
            implicitHeight: 44
            radius: root.active ? 14 : 22 // Squircle when on, circle when off, as the quick toggles
            color: root.active ? root.accent : Appearance.colors.colLayer2
            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors {
                    centerIn: parent
                    alignWhenCentered: !root.rotateIcon
                }
                color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                renderType: Text.QtRendering
                text: root.icon
                fill: root.active ? 1 : 0
                iconSize: 20 + 4 * (root.scaleIcon ? Math.min(1, root.value) : 1)
                rotation: 180 * (root.rotateIcon ? Math.min(1, root.value) : 0)
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
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    text: root.name
                }
                StyledText {
                    visible: !root.valuePill
                    color: root.boosted ? root.accent : root.active ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.Medium
                    text: root.valueText
                }
                Rectangle { // The value as a pill: solid accent while on, quiet while off
                    visible: root.valuePill
                    implicitWidth: Math.max(44, pillText.implicitWidth + 22)
                    implicitHeight: 26
                    radius: Appearance.rounding.chip + 1
                    color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    StyledText {
                        id: pillText
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        text: root.valueText
                    }
                }
            }
            StyledProgressBar {
                Layout.fillWidth: true
                visible: root.showBar
                value: Math.min(1, root.value)
                highlightColor: root.active ? root.accent : Appearance.colors.colSubtext
            }
        }
    }
}
