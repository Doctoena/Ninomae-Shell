import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
// Flat caps lock row; the OSD drawer draws the background
Item {
    id: root
    implicitWidth: Appearance.sizes.osdWidth + 60
    implicitHeight: 44
    RowLayout {
        anchors.fill: parent
        spacing: 12
        Rectangle {
            implicitWidth: 44
            implicitHeight: 44
            radius: 14 // Squircle, like the quick toggles' icons
            color: Appearance.colors.colPrimary
            MaterialSymbol {
                anchors.centerIn: parent
                color: Appearance.colors.colOnPrimary
                text: "keyboard_capslock"
                iconSize: 22
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            text: Translation.tr("Caps Lock")
        }
        Rectangle { // On/off pill
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: capsState.implicitWidth + 20
            implicitHeight: 26
            radius: 9
            color: CapsLock.capsLockActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
            StyledText {
                id: capsState
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: CapsLock.capsLockActive ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                text: CapsLock.capsLockActive ? Translation.tr("On") : Translation.tr("Off")
            }
        }
    }
}
