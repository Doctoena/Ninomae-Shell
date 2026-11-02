import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// The in-game overlay's clips and screenshots from this session, in their own column down the right of the screen
// (there can be many): how many of each, buttons to their folders, and all of them two to a row, newest first,
// scrolling down. A tile opens the overlay's viewer (openCapture). As tall as it needs, up to maxHeight. None
// yet: one line on how to save one
OverlayPanel {
    id: root
    property var captures: [] // [{ kind: "clip" | "shot", path, thumb (clips), duration (clips), … }], newest first
    property string clipsFolder: ""
    property string shotsFolder: ""
    property bool recording: false
    property real maxHeight: 1000
    signal openCapture(int index)
    signal openFolder(string folder)
    readonly property int clipCount: captures.filter(c => c.kind === "clip").length
    readonly property int shotCount: captures.length - clipCount
    readonly property int gap: 8
    readonly property real tileWidth: (column.width - gap) / 2
    readonly property real tileHeight: Math.round(tileWidth * 9 / 16)
    implicitHeight: Math.min(maxHeight, column.implicitHeight + 28)
    ColumnLayout {
        id: column
        anchors { fill: parent; margins: 14 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            OverlayPanelTitle { Layout.fillWidth: true; icon: "photo_library"; text: Translation.tr("Captures") }
            StyledText { // How many of each
                visible: root.captures.length > 0
                text: [root.clipCount === 1 ? Translation.tr("1 clip") : root.clipCount > 1 ? Translation.tr("%1 clips").arg(root.clipCount) : "",
                       root.shotCount === 1 ? Translation.tr("1 screenshot") : root.shotCount > 1 ? Translation.tr("%1 screenshots").arg(root.shotCount) : ""]
                    .filter(t => t).join("  ·  ")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        RowLayout { // None yet: how to save one in the game
            Layout.fillWidth: true
            visible: root.captures.length === 0
            spacing: 6
            StyledText {
                text: root.recording ? Translation.tr("None yet. In the game, save a clip with") : Translation.tr("None yet")
                font.pixelSize: Appearance.font.pixelSize.smaller
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
        RowLayout { // Their folders
            Layout.fillWidth: true
            spacing: 6
            OverlayChip {
                Layout.fillWidth: true
                visible: root.clipsFolder !== ""
                icon: "movie"
                text: Translation.tr("Clips folder")
                onClicked: root.openFolder(root.clipsFolder)
            }
            OverlayChip {
                Layout.fillWidth: true
                visible: root.shotsFolder !== ""
                icon: "photo"
                text: Translation.tr("Screenshots folder")
                onClicked: root.openFolder(root.shotsFolder)
            }
        }
        GridView { // All of them, newest first, two to a row
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: contentHeight
            visible: root.captures.length > 0
            // Two cells share the width; each tile sits to its cell's outer side, so the gap is between them
            cellWidth: width / 2
            cellHeight: root.tileHeight + root.gap
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.captures
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: grid.cellWidth
                height: grid.cellHeight
                ClippingRectangle { // Its picture cut to the round corners
                    id: tile
                    readonly property var modelData: cell.modelData
                    readonly property int index: cell.index
                    x: index % 2 === 1 ? root.gap / 2 : 0
                    width: root.tileWidth
                    height: root.tileHeight
                    radius: Appearance.rounding.container
                    color: Appearance.colors.colLayer2
                    Image { // A clip's thumbnail, or the screenshot itself
                        anchors.fill: parent
                        source: tile.modelData.kind === "shot" ? "file://" + tile.modelData.path
                            : tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 384
                    }
                    Rectangle { // A clip's length, a screenshot's camera
                        anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                        width: badge.implicitWidth + 10; height: 18; radius: 6
                        color: Qt.rgba(0, 0, 0, 0.6)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: tile.modelData.kind === "shot"
                            text: "photo_camera"
                            iconSize: 13
                            color: "white"
                        }
                        StyledText {
                            id: badge
                            anchors.centerIn: parent
                            visible: tile.modelData.kind === "clip"
                            text: visible ? `${Math.floor(tile.modelData.duration / 60)}:${String(Math.floor(tile.modelData.duration % 60)).padStart(2, "0")}` : " "
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: "white"
                        }
                    }
                    Rectangle { // Hover ring
                        anchors.fill: parent
                        radius: tile.radius
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
