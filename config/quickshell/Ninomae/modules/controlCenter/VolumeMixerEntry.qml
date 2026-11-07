import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
// One app's volume on the control centre's Sound page: its icon, name and what it's playing, a slider and the
// percentage. Its node goes null for a moment as the app stops playing (the row is on its way out): everything
// here reads it with ?.
RowLayout {
    id: root
    required property PwNode node
    spacing: 12
    PwObjectTracker {
        objects: [root.node]
    }
    Image {
        Layout.alignment: Qt.AlignVCenter
        visible: source != ""
        sourceSize: Qt.size(32, 32)
        source: {
            if (!root.node) return "";
            let icon;
            icon = AppSearch.guessIcon(root.node.properties["application.icon-name"]);
            if (AppSearch.iconExists(icon))
                return Quickshell.iconPath(icon, "image-missing");
            icon = AppSearch.guessIcon(root.node.properties["node.name"]);
            return Quickshell.iconPath(icon, "image-missing");
        }
    }
    ColumnLayout {
        Layout.preferredWidth: 170
        Layout.fillWidth: false
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: !root.node ? "" : root.node.properties["application.name"] ?? (root.node.description != "" ? root.node.description : root.node.name)
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer2
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.node?.properties["media.name"] ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }
    SlimSlider {
        Layout.fillWidth: true
        level: root.node?.audio?.volume ?? 0
        onMoved: if (root.node?.audio) root.node.audio.volume = value
    }
    StyledText {
        Layout.preferredWidth: 42
        horizontalAlignment: Text.AlignRight
        text: Math.round((root.node?.audio?.volume ?? 0) * 100) + "%"
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer2
    }
}
