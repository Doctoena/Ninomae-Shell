import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// One of the in-game overlay's quick actions: a squircle in the accent when on, its key at its corner, its name
// under it, a tooltip. Unavailable: dimmed and does nothing, but still shows its tooltip (which says why)
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
    implicitWidth: 92
    implicitHeight: 84
    opacity: available ? 1 : 0.45
    Rectangle {
        id: squircle
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
        width: 52; height: 52
        radius: mouse.containsPress ? height / 2 : Appearance.rounding.normal // Toward a pill while held, as the toggles
        Behavior on radius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        color: root.active ? (mouse.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
            : mouse.containsMouse && root.available ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 24
            fill: root.active ? 1 : 0
            color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
        Rectangle { // Its key
            anchors { right: parent.right; bottom: parent.bottom; margins: -4 }
            width: 18; height: 18; radius: Appearance.rounding.chip - 2
            color: Appearance.colors.colLayer3
            StyledText {
                anchors.centerIn: parent
                text: root.key
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
        }
    }
    StyledText {
        anchors { top: squircle.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
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
