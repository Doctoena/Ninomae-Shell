import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// The in-game overlay's list of outputs, as the sidebar's Sound menu lists them (in its side drawer): each with
// its icon on a squircle, the one in use in the accent with a check. A click moves the sound there (picked)
ColumnLayout {
    id: root
    property var outputs: []
    property var iconFor: node => "speaker"
    signal picked()
    spacing: 8
    OverlayPanelTitle {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.topMargin: 2
        icon: "volume_up"
        text: Translation.tr("Play sound through")
    }
    QuickDialogGroup {
        Repeater {
            model: root.outputs
            DialogListItem {
                id: outputRow
                required property var modelData
                readonly property bool inUse: modelData === Pipewire.defaultAudioSink
                Layout.fillWidth: true
                active: inUse
                onClicked: {
                    Pipewire.preferredDefaultAudioSink = modelData;
                    root.picked();
                }
                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: outputRow.horizontalPadding; rightMargin: outputRow.horizontalPadding
                        topMargin: outputRow.verticalPadding; bottomMargin: outputRow.verticalPadding
                    }
                    spacing: 12
                    QuickDialogIcon {
                        icon: root.iconFor(outputRow.modelData)
                        active: outputRow.inUse
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: outputRow.modelData.description || outputRow.modelData.name
                        color: outputRow.inUse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: outputRow.inUse ? Font.DemiBold : Font.Medium
                        elide: Text.ElideRight
                    }
                    MaterialSymbol {
                        visible: outputRow.inUse
                        text: "check"
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
