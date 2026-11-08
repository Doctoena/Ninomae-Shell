import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// One of the in-game overlay's quick actions, as the sidebar's toggles: a neutral tile, its icon on a quiet circle
// when off and on an accent squircle when on (the name in the accent then), a tooltip (with its key). Unavailable: dimmed and does nothing, but
// still shows its tooltip (which says why)
Rectangle {
    id: root
    property string icon
    property string text
    property string tip
    property string key
    property bool active: false
    property bool available: true // Not `enabled`: that would stop the tooltip too
    signal triggered()
    function trigger() { if (root.available) root.triggered(); }
    Layout.fillWidth: true // The row's tiles share its width
    implicitWidth: 72
    implicitHeight: 88
    radius: Appearance.rounding.normal
    opacity: available ? 1 : 0.45
    color: mouse.containsMouse && root.available ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    Rectangle {
        id: squircle
        anchors { top: parent.top; topMargin: 12; horizontalCenter: parent.horizontalCenter }
        width: 40; height: 40
        radius: root.active ? 11 : height / 2 // Squircle when on, circle when off
        Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
        color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer4
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 20
            fill: root.active ? 1 : 0
            color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
    }
    StyledText {
        anchors { top: squircle.bottom; topMargin: 6; left: parent.left; right: parent.right; margins: 4 }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
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
        text: root.key ? `${root.tip}  ·  ${root.key}` : root.tip
    }
}
