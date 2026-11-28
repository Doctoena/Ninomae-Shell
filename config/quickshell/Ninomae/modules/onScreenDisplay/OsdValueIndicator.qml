import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
// One row of the on-screen display (the drawer draws the background), in a well (V2 with V3's ring): the level as a
// ring round the icon, as the battery drop-down's and the sidebar's (in the accent while on, quiet while off); the
// name and which device it is (detail), the value at the end (valueText, a percentage by default), and a slim filled
// bar under them (showBar): readable at a glance, and not a slider (the pop-up can't be dragged). Past full (a volume
// boost, value > 1) the ring, the value and the bar turn red. Without a bar (Caps Lock) it's compact (C3): a smaller
// ring, the name, and the shell's switch for on or off, only as wide as that
Item {
    id: root
    property real value: 0
    required property string icon
    required property string name
    property string detail: "" // The device ("VIRTUOSO MAX", "Built-in display"), or "Muted"
    property string valueText: Math.round(value * 100) + "%"
    property bool active: true
    property bool showBar: true
    property bool rotateIcon: false
    property bool scaleIcon: false
    readonly property bool boosted: value > 1.005
    readonly property color accent: boosted ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property color levelColour: active ? accent : Appearance.colors.colSubtextGlass
    readonly property bool compact: !showBar
    implicitWidth: compact ? row.implicitWidth + 24 : Appearance.sizes.osdWidth + 120 // Room for the device beside the name
    implicitHeight: compact ? 50 : 66

    GlassWell {
        anchors.fill: parent
    }
    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: root.compact ? 8 : 10; rightMargin: root.compact ? 12 : 14 }
        spacing: 12
        Item {
            implicitWidth: root.compact ? 34 : 46
            implicitHeight: implicitWidth
            UsageRing { // The level round the icon (no bar: full while on, as Caps Lock)
                anchors.fill: parent
                size: parent.implicitWidth
                stroke: root.compact ? 3 : 4
                fraction: root.showBar ? root.value : (root.active ? 1 : 0)
                colour: root.levelColour
                icon: ""
            }
            MaterialSymbol { // Drawn here, not by the ring: brightness turns and grows it with the level
                anchors {
                    centerIn: parent
                    alignWhenCentered: !root.rotateIcon
                }
                color: root.levelColour
                renderType: Text.QtRendering
                text: root.icon
                fill: root.active ? 1 : 0
                iconSize: 18 + 3 * (root.scaleIcon ? Math.min(1, root.value) : 1)
                rotation: 180 * (root.rotateIcon ? Math.min(1, root.value) : 0)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
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
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    text: root.name
                }
                StyledText { // The device (it also keeps the value at the row's end when there's none)
                    visible: !root.compact
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtextGlass
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.detail !== "" ? "· " + root.detail : ""
                }
                StyledText {
                    visible: !root.compact
                    color: root.boosted ? root.accent : root.active ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtextGlass
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.Medium
                    text: root.valueText
                }
                StyledSwitch { // Compact: on or off, as the shell's switch (shown, not clicked: the key sets it)
                    visible: root.compact
                    Layout.leftMargin: 6
                    enabled: false
                    sizeScale: 0.7
                    checked: root.active
                }
            }
            Rectangle { // The level as a slim filled bar, on a darker track
                Layout.fillWidth: true
                visible: root.showBar
                implicitHeight: 8
                radius: height / 2
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45)
                Rectangle {
                    width: Math.max(parent.height, parent.width * Math.min(1, Math.max(0, root.value)))
                    height: parent.height
                    radius: height / 2
                    color: root.levelColour
                    Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }
        }
    }
}
