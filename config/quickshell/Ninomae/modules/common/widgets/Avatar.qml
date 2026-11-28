import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * You, in a circle with an accent ring (Settings' page list, the sidebar): your picture (~/.face) or your initial.
 * Pointed at, a pencil: a click picks a new picture (scripts/set-avatar.sh), shown right away. `icon` shows that
 * symbol instead, and then it's just a badge. `editable: false` leaves the pencil out (the lock screen).
 * `tooltipBeside` puts the hint to its right (against a window's edge).
 */
Rectangle {
    id: root
    property string icon: ""
    property bool tooltipBeside: false
    property bool editable: true
    readonly property bool isYou: icon === ""
    implicitWidth: 44
    implicitHeight: 44
    radius: width / 2
    color: Appearance.colors.colSecondaryContainer
    border.width: 2
    border.color: Appearance.colors.colPrimary
    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.isYou
        text: root.icon
        iconSize: Math.round(root.width / 2)
        color: Appearance.colors.colOnSecondaryContainer
    }
    StyledText {
        anchors.centerIn: parent
        visible: root.isYou && face.status !== Image.Ready
        text: SystemInfo.username.charAt(0).toUpperCase()
        font.family: Appearance.font.family.expressive
        font.pixelSize: Math.round(root.width * 0.43)
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnSecondaryContainer
    }
    FileView { // ~/.face, only when there is one; a new picture shows right away
        path: root.isYou ? `${FileUtils.trimFileProtocol(Directories.home)}/.face` : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { face.source = ""; face.source = `file://${path}`; }
    }
    StyledImage {
        id: face
        anchors.centerIn: parent
        width: root.width - 6
        height: root.height - 6
        cache: false // The same path with a new picture in it
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(88, 88)
        visible: root.isYou && status === Image.Ready
        layer.enabled: visible
        layer.effect: RoundedMask { maskWidth: face.width; maskHeight: face.height; radius: face.width / 2 }
    }
    Rectangle { // Pointed at: a pencil, a click picks a new picture
        visible: root.isYou && root.editable
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: faceArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "edit"
            iconSize: 18
            color: "white"
        }
    }
    MouseArea {
        id: faceArea
        enabled: root.isYou && root.editable
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/set-avatar.sh")])
    }
    StyledToolTip {
        x: root.tooltipBeside ? parent.width + 8 : (parent.width - width) / 2
        y: root.tooltipBeside ? (parent.height - height) / 2 : -height - 6
        text: Translation.tr("Change your picture")
        visible: faceArea.containsMouse
    }
}
