import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// The in-game overlay's clips and screenshots from this session, in their own panel down the right: how many of
// each and buttons to their folders, whether the replay is recording (and its key), then the newest big, with
// Open / Copy / Trash on it while pointed at, and the next ones small under it. With more than three, the last
// small tile shows them all, three to a row, scrolling within maxHeight. A tile opens the overlay's viewer
// (openCapture)
OverlayPanel {
    id: root
    property var captures: [] // [{ kind: "clip" | "shot", path, thumb (clips), duration (clips), … }], newest first
    property string clipsFolder: ""
    property string shotsFolder: ""
    property real maxHeight: 1000
    property bool showAll: false
    signal openCapture(int index)
    signal openFolder(string folder)
    signal trashed(string path)
    readonly property int clipCount: captures.filter(c => c.kind === "clip").length
    readonly property int shotCount: captures.length - clipCount
    readonly property var newest: captures[0] ?? null
    readonly property var rest: captures.slice(1)
    // Small tiles: all the rest, or the next two (and "All" on the third when there are more)
    readonly property bool hasMore: rest.length > 3
    readonly property var smallTiles: showAll || !hasMore ? rest : rest.slice(0, 2)
    onCapturesChanged: if (!hasMore) showAll = false
    readonly property real smallWidth: (column.width - 8) / 3
    readonly property real smallHeight: Math.round(smallWidth * 9 / 16)
    implicitHeight: Math.min(maxHeight, column.implicitHeight + 28)

    function lengthText(c) {
        return `${Math.floor(c.duration / 60)}:${String(Math.floor(c.duration % 60)).padStart(2, "0")}`;
    }
    function agoText(c) {
        const minutes = Math.floor((Date.now() - c.time) / 60000);
        return minutes < 1 ? Translation.tr("just now") : minutes < 60 ? Translation.tr("%1 min ago").arg(minutes)
            : Translation.tr("%1 h ago").arg(Math.floor(minutes / 60));
    }

    CaptureActions {
        id: actions
        onTrashed: path => root.trashed(path)
    }
    property string trashArmedPath: "" // Trash asks twice, as the viewer's
    Timer { id: trashDisarm; interval: 4000; onTriggered: root.trashArmedPath = "" }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 4

        OverlayPanelHead {
            Layout.fillWidth: true
            icon: "photo_library"
            title: Translation.tr("Captures")
            detail: root.captures.length === 0 ? Translation.tr("None yet this session")
                : [root.clipCount === 1 ? Translation.tr("1 clip") : root.clipCount > 1 ? Translation.tr("%1 clips").arg(root.clipCount) : "",
                   root.shotCount === 1 ? Translation.tr("1 screenshot") : root.shotCount > 1 ? Translation.tr("%1 screenshots").arg(root.shotCount) : ""]
                    .filter(t => t).join("  ·  ")
            OverlayChip {
                visible: root.clipsFolder !== ""
                iconName: "movie"
                tip: Translation.tr("Clips folder")
                onClicked: root.openFolder(root.clipsFolder)
            }
            OverlayChip {
                visible: root.shotsFolder !== ""
                iconName: "image"
                tip: Translation.tr("Screenshots folder")
                onClicked: root.openFolder(root.shotsFolder)
            }
        }

        Rectangle { // The replay: recording, or why not
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: root.captures.length > 0 ? 6 : 0
            implicitHeight: 30
            radius: Appearance.rounding.small - 3
            color: GameClips.recording ? ColorUtils.transparentize(Appearance.colors.colError, 0.9) : Appearance.colors.colLayer3
            RowLayout {
                anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 8
                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: GameClips.recording ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
                StyledText {
                    text: GameClips.recording ? Translation.tr("Replay on") : Translation.tr("Replay off")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: GameClips.recording ? Translation.tr("saves the last %1 s").arg(GameClips.seconds)
                        : GameClips.enabled ? Translation.tr("records once a game is running") : Translation.tr("clips are off in Settings → In game")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                OverlayKey { // The clip key
                    visible: GameClips.recording
                    text: GameClips.keyLabel
                }
            }
        }

        // ── The newest, big ──
        ClippingRectangle {
            id: big
            Layout.fillWidth: true
            visible: root.newest !== null
            implicitHeight: Math.round(width * 9 / 16)
            topLeftRadius: Appearance.rounding.normal
            topRightRadius: Appearance.rounding.normal
            bottomLeftRadius: root.rest.length > 0 ? Appearance.rounding.joined : Appearance.rounding.normal
            bottomRightRadius: bottomLeftRadius
            color: Appearance.colors.colLayer3
            readonly property bool isClip: root.newest?.kind === "clip"
            readonly property bool armed: root.newest !== null && root.trashArmedPath === root.newest.path
            Image {
                anchors.fill: parent
                source: root.newest === null ? "" : big.isClip ? (root.newest.thumb ? "file://" + root.newest.thumb : "") : "file://" + root.newest.path
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 768
            }
            Rectangle { // Keeps the buttons readable
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, bigMouse.containsMouse ? 0.7 : 0.35) }
                }
            }
            MouseArea {
                id: bigMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCapture(0)
            }
            Rectangle { // What it is and when
                anchors { left: parent.left; top: parent.top; margins: 8 }
                implicitWidth: whatRow.implicitWidth + 12
                implicitHeight: 20
                radius: 6
                color: Qt.rgba(0, 0, 0, 0.6)
                RowLayout {
                    id: whatRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: big.isClip ? "movie" : "photo_camera"
                        iconSize: 12
                        color: "white"
                    }
                    StyledText {
                        text: root.newest === null ? "" : (big.isClip ? Translation.tr("Clip  ·  %1").arg(root.lengthText(root.newest)) : Translation.tr("Screenshot"))
                            + "  ·  " + root.agoText(root.newest)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: "white"
                    }
                }
            }
            Rectangle { // A clip plays
                visible: big.isClip
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -8
                width: 52
                height: 52
                radius: 26
                color: Qt.rgba(0, 0, 0, bigMouse.containsMouse ? 0.65 : 0.45)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.2)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    iconSize: 32
                    fill: 1
                    color: "white"
                }
            }
            RowLayout { // Pointed at, or holding a click to trash: what can be done with it
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                visible: bigMouse.containsMouse || actionsHover.hovered || big.armed
                spacing: 4
                HoverHandler { id: actionsHover }
                OverlayChip {
                    overPicture: true
                    iconName: "open_in_new"
                    label: Translation.tr("Open")
                    tip: big.isClip ? Translation.tr("Open in the video player") : Translation.tr("Open in the image viewer")
                    onClicked: actions.open(root.newest)
                }
                OverlayChip {
                    overPicture: true
                    iconName: actions.copiedPath !== "" && actions.copiedPath === root.newest?.path ? "check" : "content_copy"
                    label: Translation.tr("Copy")
                    tip: big.isClip ? Translation.tr("Copy the clip") : Translation.tr("Copy the screenshot")
                    onClicked: actions.copy(root.newest)
                }
                Item { Layout.fillWidth: true }
                OverlayChip {
                    overPicture: true
                    danger: true
                    armed: big.armed
                    iconName: big.armed ? "delete_forever" : "delete"
                    tip: big.armed ? Translation.tr("Click again to move to the Trash") : Translation.tr("Move to the Trash")
                    onClicked: {
                        if (!big.armed) {
                            root.trashArmedPath = root.newest.path;
                            trashDisarm.restart();
                            return;
                        }
                        root.trashArmedPath = "";
                        actions.trash(root.newest);
                    }
                }
            }
        }

        // ── The next ones, small, three to a row (all of them once "All" is chosen, scrolling) ──
        StyledFlickable {
            Layout.fillWidth: true
            visible: root.rest.length > 0
            implicitHeight: Math.min(grid.implicitHeight, root.maxHeight - 28 - y)
            contentHeight: grid.implicitHeight
            clip: true
            interactive: contentHeight > height
            Grid {
                id: grid
                width: parent.width
                columns: 3
                spacing: 4
                Repeater {
                    model: root.smallTiles
                    ClippingRectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property int count: root.smallTiles.length + (root.hasMore ? 1 : 0)
                        readonly property bool lastRow: index >= Math.floor((count - 1) / 3) * 3
                        width: root.smallWidth
                        height: root.smallHeight
                        radius: Appearance.rounding.joined
                        bottomLeftRadius: lastRow && index % 3 === 0 ? Appearance.rounding.normal : Appearance.rounding.joined
                        bottomRightRadius: lastRow && (index % 3 === 2 || index === count - 1) ? Appearance.rounding.normal : Appearance.rounding.joined
                        color: Appearance.colors.colLayer3
                        Image {
                            anchors.fill: parent
                            source: tile.modelData.kind === "shot" ? "file://" + tile.modelData.path
                                : tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 256
                        }
                        Rectangle { // A clip's length, a screenshot's camera
                            anchors { left: parent.left; bottom: parent.bottom; margins: 5 }
                            width: badge.implicitWidth + 10
                            height: 18
                            radius: 5
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
                                text: visible ? root.lengthText(tile.modelData) : " "
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.numbers
                                color: "white"
                            }
                        }
                        Rectangle { // Hover ring
                            anchors.fill: parent
                            topLeftRadius: tile.topLeftRadius
                            topRightRadius: tile.topRightRadius
                            bottomLeftRadius: tile.bottomLeftRadius
                            bottomRightRadius: tile.bottomRightRadius
                            color: "transparent"
                            border.width: 2
                            border.color: Appearance.colors.colPrimary
                            visible: tileMouse.containsMouse
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openCapture(tile.index + 1)
                        }
                    }
                }
                RippleButton { // All of them, or back to a few
                    visible: root.hasMore
                    width: root.smallWidth
                    height: root.smallHeight
                    buttonRadius: Appearance.rounding.joined
                    buttonRadiusBottomRight: Appearance.rounding.normal
                    buttonRadiusBottomLeft: (root.smallTiles.length % 3 === 0) ? Appearance.rounding.normal : Appearance.rounding.joined
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: root.showAll = !root.showAll
                    contentItem: Item {
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.showAll ? "unfold_less" : "grid_view"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.showAll ? Translation.tr("Fewer") : Translation.tr("All %1").arg(root.captures.length)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
