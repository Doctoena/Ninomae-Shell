pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// The control centre's sections: a slim column of icons on squircles (accent for the open one), names under
ColumnLayout {
    id: rail
    required property var content // ControlCenterContent: sections, currentIndex, close()
    spacing: 6

    Repeater {
        model: rail.content.sections
        delegate: RailItem {
            required property var modelData
            required property int index
            symbol: modelData.icon
            label: modelData.name
            current: rail.content.currentIndex === index
            onClicked: GlobalStates.controlCenterSection = modelData.id
        }
    }
    Item { Layout.fillHeight: true }
    RailItem {
        symbol: "settings"
        label: Translation.tr("Settings")
        onClicked: {
            Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh")]);
            rail.content.close();
        }
    }

    component RailItem: MouseArea {
        id: item
        property string symbol
        property string label
        property bool current: false
        Layout.fillWidth: true
        implicitHeight: 72
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 52
                implicitHeight: 36
                radius: Appearance.rounding.container
                color: item.current ? Appearance.colors.colPrimary
                    : item.containsMouse ? Appearance.m3colors.m3surfaceContainerHigh : "transparent"
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: item.symbol
                    iconSize: 22
                    fill: item.current ? 1 : 0
                    color: item.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: item.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: item.current ? Font.DemiBold : Font.Normal
                color: item.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
        }
    }
}
