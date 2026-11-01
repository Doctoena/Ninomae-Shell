import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// An app's volume in the in-game overlay's Sound: its icon and name, and a slider. The game's own sound shows
// as the game, in the accent, with its art (gameName, gameArt)
RowLayout {
    id: root
    required property var node
    property bool game: false
    property string gameName: ""
    property string gameArt: ""
    PwObjectTracker { objects: [root.node] }
    // The first of its names that has an icon. A Flatpak (Zen) names itself only "Zen"/"zen": its app id, which
    // its icon is installed under, is in the portal's property
    readonly property string iconName: [node.properties["application.icon-name"], node.properties["pipewire.access.portal.app_id"],
        node.properties["application.name"], node.properties["application.process.binary"], node.name]
        .filter(n => n).map(n => AppSearch.guessIcon(n)).find(i => AppSearch.iconExists(i)) ?? ""
    spacing: 10
    Rectangle {
        Layout.preferredWidth: 30; Layout.preferredHeight: 30
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.segment
        color: Appearance.colors.colLayer2
        clip: true
        Image { // The game's art
            id: gameArtImage
            anchors.fill: parent
            visible: root.game && root.gameArt !== ""
            source: visible ? "file://" + root.gameArt : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 60
            asynchronous: true
        }
        IconImage { // An app's icon, from the icon theme (as the dock's)
            anchors.centerIn: parent
            implicitSize: 24
            visible: !root.game && root.iconName !== ""
            source: visible ? Quickshell.iconPath(root.iconName, "application-x-executable") : ""
        }
        MaterialSymbol { // Nothing to show: the controller for the game, a sound wave for an app
            anchors.centerIn: parent
            visible: root.game ? gameArtImage.status !== Image.Ready : root.iconName === ""
            text: root.game ? "sports_esports" : "graphic_eq"
            iconSize: 18
            color: Appearance.colors.colSubtext
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: -4
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.game ? (root.gameName || Translation.tr("The game"))
                : root.node.properties["application.name"] || root.node.description || root.node.name
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: root.game ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        }
        StyledSlider {
            Layout.fillWidth: true
            value: root.node.audio?.volume ?? 0
            onMoved: if (root.node.audio) root.node.audio.volume = value
            configuration: StyledSlider.Configuration.S
            stopIndicatorValues: []
        }
    }
}
