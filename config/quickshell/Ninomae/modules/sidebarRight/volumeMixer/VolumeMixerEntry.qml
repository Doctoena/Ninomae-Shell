import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
Item {
    id: root
    required property PwNode node
    PwObjectTracker {
        objects: [node]
    }
    implicitHeight: rowLayout.implicitHeight
    RowLayout {
        id: rowLayout
        anchors.fill: parent
        spacing: 8
        Image {
            property real size: 28
            Layout.alignment: Qt.AlignVCenter
            visible: source != ""
            sourceSize.width: size
            sourceSize.height: size
            source: {
                let icon;
                icon = AppSearch.guessIcon(root.node.properties["application.icon-name"]);
                if (AppSearch.iconExists(icon))
                    return Quickshell.iconPath(icon, "image-missing");
                icon = AppSearch.guessIcon(root.node.properties["node.name"]);
                return Quickshell.iconPath(icon, "image-missing");
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: -4
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                text: {
                    const app = root.node.properties["application.name"] ?? (root.node.description != "" ? root.node.description : root.node.name);
                    const media = root.node.properties["media.name"];
                    return media != undefined ? `${app} • ${media}` : app;
                }
            }
            StyledSlider {
                id: slider
                value: root.node.audio.volume
                onMoved: root.node.audio.volume = value
                configuration: StyledSlider.Configuration.S
                stopIndicatorValues: []
            }
        }
    }
}
