import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The in-game overlay's clips and screenshots from this session: how many of each, the newest three (the third
// says how many more), buttons to their folders. A tile opens the overlay's viewer (openCapture)
OverlayPanel {
    id: root
    property var captures: [] // [{ kind: "clip" | "shot", path, thumb (clips), duration (clips), … }], newest first
    property string clipsFolder: ""
    property string shotsFolder: ""
    property bool recording: false
    signal openCapture(int index)
    signal openFolder(string folder)
    readonly property int clipCount: captures.filter(c => c.kind === "clip").length
    readonly property int shotCount: captures.length - clipCount
    implicitHeight: column.implicitHeight + 28
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            OverlayPanelTitle { Layout.fillWidth: true; icon: "photo_library"; text: Translation.tr("This session") }
            OverlayChip {
                visible: root.clipsFolder !== ""
                icon: "movie"
                text: Translation.tr("Clips")
                onClicked: root.openFolder(root.clipsFolder)
            }
            OverlayChip {
                visible: root.shotsFolder !== ""
                icon: "photo"
                text: Translation.tr("Screenshots")
                onClicked: root.openFolder(root.shotsFolder)
            }
        }
        StyledText { // How many of each
            visible: root.captures.length > 0
            text: [root.clipCount === 1 ? Translation.tr("1 clip") : root.clipCount > 1 ? Translation.tr("%1 clips").arg(root.clipCount) : "",
                   root.shotCount === 1 ? Translation.tr("1 screenshot") : root.shotCount > 1 ? Translation.tr("%1 screenshots").arg(root.shotCount) : ""]
                .filter(t => t).join("  ·  ")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        RowLayout { // None yet: how to save one in the game
            visible: root.captures.length === 0
            spacing: 6
            StyledText {
                text: root.recording ? Translation.tr("None yet. In the game, save a clip with") : Translation.tr("None yet")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Rectangle { // The clip key, as a key
                visible: root.recording
                implicitWidth: Math.max(20, keyText.implicitWidth + 10); implicitHeight: 20
                radius: Appearance.rounding.chip - 2
                color: Appearance.colors.colLayer3
                StyledText {
                    id: keyText
                    anchors.centerIn: parent
                    text: GameClips.keyLabel
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        RowLayout { // The newest three, sharing the width
            Layout.fillWidth: true
            visible: root.captures.length > 0
            spacing: 8
            Repeater {
                model: root.captures.slice(0, 3)
                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    Layout.preferredWidth: (column.width - 16) / 3
                    Layout.preferredHeight: Math.round(Layout.preferredWidth * 9 / 16)
                    radius: Appearance.rounding.container
                    color: Appearance.colors.colLayer2
                    clip: true
                    Image { // A clip's thumbnail, or the screenshot itself
                        anchors.fill: parent
                        source: tile.modelData.kind === "shot" ? "file://" + tile.modelData.path
                            : tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 240
                    }
                    Rectangle { // A clip's length, a screenshot's camera
                        anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                        width: badge.implicitWidth + 8; height: 16; radius: 5
                        color: Qt.rgba(0, 0, 0, 0.6)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: tile.modelData.kind === "shot"
                            text: "photo_camera"
                            iconSize: 12
                            color: "white"
                        }
                        StyledText {
                            id: badge
                            anchors.centerIn: parent
                            visible: tile.modelData.kind === "clip"
                            text: visible ? `${Math.floor(tile.modelData.duration / 60)}:${String(Math.round(tile.modelData.duration % 60)).padStart(2, "0")}` : " "
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: "white"
                        }
                    }
                    Rectangle { // More than fit: how many, over the last tile
                        anchors.fill: parent
                        visible: tile.index === 2 && root.captures.length > 3
                        color: Qt.rgba(0, 0, 0, 0.55)
                        StyledText {
                            anchors.centerIn: parent
                            text: `+${root.captures.length - 2}`
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: "white"
                        }
                    }
                    Rectangle { // Hover ring
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Appearance.colors.colPrimary
                        visible: mouse.containsMouse
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openCapture(tile.index)
                    }
                }
            }
        }
    }
}
