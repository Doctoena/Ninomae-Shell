import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// An app's volume in the in-game overlay's Sound: its icon and name, and a slider for all its streams (a browser
// often has several). Its icon mutes it (a crossed speaker on it while muted). The game's own sound shows as the
// game, in the accent, with its art (gameName, gameArt)
RowLayout {
    id: root
    required property var nodes
    readonly property var node: nodes[0]
    property bool game: false
    property string gameName: ""
    property string gameArt: ""
    readonly property bool muted: nodes.every(n => n.audio?.muted ?? false)
    function toggleMute() {
        const mute = !muted;
        nodes.forEach(n => { if (n.audio) n.audio.muted = mute; });
    }
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
        Rectangle { // Muted, or hovered: what a click does, over the icon
            anchors.fill: parent
            visible: root.muted || muteMouse.containsMouse
            color: root.muted ? Appearance.colors.colErrorContainer : Qt.rgba(0, 0, 0, 0.55)
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.muted ? "volume_off" : "volume_mute"
                iconSize: 18
                fill: 1
                color: root.muted ? Appearance.colors.colOnErrorContainer : "white"
            }
        }
        MouseArea {
            id: muteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMute()
        }
        StyledToolTip {
            extraVisibleCondition: muteMouse.containsMouse
            text: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
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
            opacity: root.muted ? 0.4 : 1
            value: root.node.audio?.volume ?? 0
            onMoved: root.nodes.forEach(n => { if (n.audio) n.audio.volume = value; })
            configuration: StyledSlider.Configuration.S
            stopIndicatorValues: []
        }
    }
}
