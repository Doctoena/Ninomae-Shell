import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// One of the in-game overlay's quick actions, a cell of the strip under the game's art (hairlines between them,
// drawn by the strip): its icon and name, its key in the corner. On: an accent wash and the icon and name in the
// accent. Unavailable: dimmed and does nothing, but still shows its tooltip (which says why)
Item {
    id: root
    property string icon
    property string text
    property string tip
    property string key
    property bool active: false
    property bool available: true // Not `enabled`: that would stop the tooltip too
    signal triggered()
    function trigger() { if (root.available) root.triggered(); }
    Layout.fillWidth: true // The strip's cells share its width
    Layout.preferredWidth: 1
    implicitHeight: 74
    opacity: available ? 1 : 0.45

    Rectangle { // On: an accent wash. Hovered: a lighter one
        anchors { fill: parent; margins: 6 }
        radius: Appearance.rounding.small
        color: root.active ? ColorUtils.transparentize(Appearance.colors.colPrimary, mouse.containsMouse ? 0.76 : 0.84)
            : mouse.containsMouse && root.available ? Appearance.colors.colLayer3Hover : "transparent"
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    }
    Column {
        anchors.centerIn: parent
        width: parent.width - 8
        spacing: 5
        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            iconSize: 22
            fill: root.active ? 1 : 0
            color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
        }
    }
    OverlayKey {
        visible: root.key !== ""
        anchors { top: parent.top; right: parent.right; margins: 7 }
        text: root.key
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.trigger()
    }
    StyledToolTip {
        extraVisibleCondition: mouse.containsMouse && root.tip !== ""
        text: root.tip
    }
}
