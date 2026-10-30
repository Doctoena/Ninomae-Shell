import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Settings → Appearance: the wallpapers in ~/Pictures/Wallpapers as a carousel (as Caelestia's picker): the
 * one in the middle is large, the rest shrink and fade towards the sides. Scroll or ←/→ to look through
 * them, click one (or Enter) to apply it through switchwall.sh, which also makes the colours from it.
 * The current wallpaper is in the list even when it lives somewhere else. Browse… is the file dialog.
 */
ColumnLayout {
    id: root
    spacing: 12

    readonly property string folder: `${FileUtils.trimFileProtocol(Directories.home)}/Pictures/Wallpapers`
    readonly property string current: Config.wallpaperPath
    readonly property bool currentIsVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(current)
    property var found: [] // Images in the folder, by name
    // The folder's images, with the current wallpaper first when it isn't one of them
    readonly property var wallpapers: {
        if (current === "" || indexIn(found, current) >= 0) return found;
        return [current].concat(found);
    }
    readonly property int currentIndex: indexIn(wallpapers, current)

    // Paths can differ only by ~ or a symlinked folder: fall back to the file name
    function indexIn(list, path) {
        const name = p => p.replace(/^.*\//, "");
        const exact = list.indexOf(path);
        return exact >= 0 ? exact : list.findIndex(p => name(p) === name(path));
    }
    function apply(path) {
        if (path === current) return;
        Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--image", path]);
    }
    function refresh() {
        lister.running = false;
        lister.running = true;
    }
    Component.onCompleted: refresh()
    onCurrentChanged: refresh() // Browse… moves a picked file into the folder: list it
    Process {
        id: lister
        command: ["find", "-L", root.folder, "-maxdepth", "2", "-type", "f",
            "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l.length > 0).sort((a, b) => a.localeCompare(b));
                if (list.join("\n") !== root.found.join("\n")) root.found = list;
            }
        }
    }
    // A new wallpaper (from here, the overview or Browse…): bring it to the middle
    onCurrentIndexChanged: if (currentIndex >= 0) carousel.currentIndex = currentIndex

    // ── Carousel ──
    ListView {
        id: carousel
        readonly property real tileWidth: Math.round(Math.max(220, Math.min(360, width * 0.55))) // Half the card, give or take
        readonly property real tileHeight: Math.round(tileWidth * 9 / 16)
        Layout.fillWidth: true
        Layout.preferredHeight: tileHeight + 8
        orientation: ListView.Horizontal
        spacing: -36 // The side tiles shrink, so they'd float apart without some overlap
        clip: true
        focus: true
        model: root.wallpapers
        // The current tile always sits in the middle
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - tileWidth) / 2
        preferredHighlightEnd: (width + tileWidth) / 2
        highlightMoveDuration: 350
        boundsBehavior: Flickable.StopAtBounds
        // The list arrives after the carousel is built, often before it has a width: jump to the
        // wallpaper in use once both are there (setting currentIndex alone left the first tile centred)
        function centreOnCurrent() {
            if (root.currentIndex < 0 || count === 0 || width <= 0) return;
            currentIndex = root.currentIndex;
            positionViewAtIndex(currentIndex, ListView.SnapPosition);
        }
        onCountChanged: Qt.callLater(centreOnCurrent)
        onWidthChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.SnapPosition)) // A resize keeps the middle one centred
        Keys.onLeftPressed: decrementCurrentIndex()
        Keys.onRightPressed: incrementCurrentIndex()
        Keys.onReturnPressed: root.apply(root.wallpapers[currentIndex])
        Keys.onEnterPressed: root.apply(root.wallpapers[currentIndex])
        // The wheel steps through them (a mouse notch = one; a touchpad's small deltas add up to one)
        WheelHandler {
            property real pending: 0
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                pending += delta;
                while (pending >= 120) { carousel.decrementCurrentIndex(); pending -= 120; }
                while (pending <= -120) { carousel.incrementCurrentIndex(); pending += 120; }
            }
        }
        delegate: Item {
            id: tile
            required property int index
            required property string modelData
            readonly property bool inUse: index === root.currentIndex
            readonly property bool centred: ListView.isCurrentItem
            // 0 in the middle, 1 a tile's width away and further
            readonly property real distance: Math.min(1, Math.abs(x + width / 2 - carousel.contentX - carousel.width / 2) / carousel.tileWidth)
            width: carousel.tileWidth
            height: carousel.height
            z: 10 - distance * 10 // The middle one on top of its neighbours
            scale: (1 - 0.22 * distance) * (tileMouse.pressed ? 0.98 : 1)
            opacity: 1 - 0.5 * distance
            ClippingRectangle { // Rounded without an offscreen layer per tile
                id: frame
                anchors.centerIn: parent
                width: carousel.tileWidth
                height: carousel.tileHeight
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                StyledImage {
                    id: thumb
                    anchors.fill: parent
                    // A video wallpaper shows its saved frame
                    source: tile.inUse && root.currentIsVideo ? Config.thumbnailPath : "file://" + tile.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: 640 // Plenty for a tile, cheap to decode even from a 5K image
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: thumb.status !== Image.Ready
                    text: thumb.status === Image.Error ? "broken_image" : "hourglass_empty"
                    iconSize: 22
                    color: Appearance.colors.colSubtext
                }
            }
            Rectangle { // The wallpaper in use: an accent ring and a check
                anchors.centerIn: frame
                width: frame.width + 6
                height: frame.height + 6
                radius: frame.radius + 3
                color: "transparent"
                border.width: 3
                border.color: Appearance.colors.colPrimary
                visible: tile.inUse
            }
            Rectangle {
                visible: tile.inUse
                anchors { top: frame.top; right: frame.right; margins: 10 }
                width: 28; height: 28
                radius: Appearance.rounding.segment
                color: Appearance.colors.colPrimary
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimary
                }
            }
            MouseArea {
                id: tileMouse
                anchors.fill: frame
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    carousel.currentIndex = tile.index;
                    carousel.forceActiveFocus();
                    root.apply(tile.modelData);
                }
            }
        }
    }

    // Nothing to show yet: say where they come from
    StyledText {
        visible: root.wallpapers.length === 0 && !lister.running
        Layout.alignment: Qt.AlignHCenter
        text: Translation.tr("No wallpapers in %1 yet").arg(root.folder.replace(FileUtils.trimFileProtocol(Directories.home), "~"))
        color: Appearance.colors.colSubtext
    }

    // ── The middle one's name, and the buttons ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            elide: Text.ElideMiddle
            text: (root.wallpapers[carousel.currentIndex] ?? "").replace(/^.*\//, "").replace(/\.[^.]+$/, "")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }
        InfoChip {
            visible: carousel.currentIndex === root.currentIndex && root.currentIndex >= 0
            icon: "check"
            text: Translation.tr("In use")
        }
        RippleButtonWithIcon {
            materialIcon: "folder_open"
            mainText: Translation.tr("Folder")
            onClicked: Qt.openUrlExternally(`file://${root.folder}`)
            StyledToolTip {
                text: Translation.tr("Put images in here to see them in the list")
            }
        }
        RippleButtonWithIcon {
            materialIcon: "image_search"
            mainText: Translation.tr("Browse…")
            onClicked: Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath])
            StyledToolTip {
                text: Translation.tr("Any image or video from your files")
            }
        }
    }
}
