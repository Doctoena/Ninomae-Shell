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
 * Settings → Appearance: the wallpapers in ~/Pictures/Wallpapers as a carousel that goes round: the one in the
 * middle large, its neighbours smaller and dimmed either side. Scroll, drag, ←/→ or the arrows to look through
 * them. A click on a side one brings it to the middle, a click on the middle one (Enter, or Use this) applies it
 * through switchwall.sh, which also makes the colours from it. The current wallpaper is in the list even when it
 * lives somewhere else. Browse… is the file dialog.
 */
ColumnLayout {
    id: root
    spacing: 12

    readonly property string folder: `${FileUtils.trimFileProtocol(Directories.home)}/Pictures/Wallpapers`
    // A size version ("name_5120x1440.png") counts as its plain wallpaper, which the carousel shows instead
    readonly property string current: WallpaperVariants.plainOf(Config.wallpaperPath, found)
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
    property string applying: "" // Clicked, and switchwall.sh is still making its colours
    readonly property string centred: wallpapers[carousel.currentIndex] ?? ""
    readonly property bool centredInUse: carousel.currentIndex === currentIndex && currentIndex >= 0
    function apply(path) {
        if (path === "" || indexIn([path], current) === 0) return;
        root.applying = path;
        applyingTimeout.restart();
        Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--image", path]);
    }
    Timer { id: applyingTimeout; interval: 20000; onTriggered: root.applying = "" } // switchwall.sh gave up
    function refresh() {
        lister.running = false;
        lister.running = true;
    }
    Component.onCompleted: refresh()
    onCurrentChanged: { // Browse… moves a picked file into the folder: list it
        refresh();
        root.applying = "";
    }
    Process {
        id: lister
        command: ["find", "-L", root.folder, "-maxdepth", "2", "-type", "f",
            "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l.length > 0).sort((a, b) => a.localeCompare(b));
                const shown = WallpaperVariants.withoutVariants(list);
                if (shown.join("\n") !== root.found.join("\n")) root.found = shown;
            }
        }
    }
    // A new wallpaper (from here, the overview or Browse…): bring it to the middle
    onCurrentIndexChanged: if (currentIndex >= 0) carousel.stepTo(currentIndex)

    // ── Carousel ──
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: carousel.tileHeight + 12
        PathView {
            id: carousel
            readonly property real tileWidth: Math.round(Math.max(240, Math.min(440, width * 0.42)))
            readonly property real tileHeight: Math.round(tileWidth * 9 / 16)
            readonly property real sideScale: 0.8
            readonly property real step: tileWidth * (1 + sideScale) / 2 + 18 // Centre to centre: an even gap between tiles
            readonly property int shownCount: Math.min(count, 5)
            anchors.fill: parent
            clip: true
            focus: true
            model: root.wallpapers
            pathItemCount: shownCount
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            snapMode: PathView.SnapOneItem
            highlightMoveDuration: Appearance.animation.elementMove.duration
            path: Path { // A straight line through the middle, shownCount steps long: one tile per step
                startX: carousel.width / 2 - carousel.step * carousel.shownCount / 2
                startY: carousel.height / 2
                PathLine {
                    x: carousel.width / 2 + carousel.step * carousel.shownCount / 2
                    y: carousel.height / 2
                }
            }
            cacheItemCount: 4 // Tiles that scroll out stay built: no decoding again when they come back
            // The list arrives after the carousel is built: start on the wallpaper in use, without sliding there
            onCountChanged: Qt.callLater(() => {
                if (root.currentIndex >= 0 && count > 0) positionViewAtIndex(root.currentIndex, PathView.Center);
            })
            // Step to `index` the way the arrows do, round the shorter way, so every move slides the same
            function stepTo(index) {
                if (count === 0 || index < 0) return;
                let delta = (index - currentIndex + count) % count;
                if (delta > count / 2) delta -= count;
                for (; delta > 0; delta--) incrementCurrentIndex();
                for (; delta < 0; delta++) decrementCurrentIndex();
            }
            Keys.onLeftPressed: decrementCurrentIndex()
            Keys.onRightPressed: incrementCurrentIndex()
            Keys.onReturnPressed: root.apply(root.centred)
            Keys.onEnterPressed: root.apply(root.centred)
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
                readonly property bool centred: PathView.isCurrentItem
                readonly property bool busy: root.applying === modelData
                // 0 in the middle, 1 one step away, 2 at the edges
                readonly property real distance: Math.min(2, Math.abs(x + width / 2 - carousel.width / 2) / carousel.step)
                width: carousel.tileWidth
                height: carousel.tileHeight
                z: 10 - distance
                scale: (1 - (1 - carousel.sideScale) * Math.min(1, distance)) * (tileMouse.pressed ? 0.98 : 1)
                opacity: distance <= 1 ? 1 : 2 - distance // Fades out past the neighbours
                Rectangle { // The wallpaper in use: an accent ring
                    anchors { fill: parent; margins: -4 }
                    radius: Appearance.rounding.large + 4
                    color: "transparent"
                    border.width: 3
                    border.color: Appearance.colors.colPrimary
                    visible: tile.inUse
                }
                ClippingRectangle { // Rounded without an offscreen layer per tile
                    id: frame
                    anchors.fill: parent
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer2
                    StyledImage {
                        id: thumb
                        anchors.fill: parent
                        // A video wallpaper shows its saved frame
                        source: tile.inUse && root.currentIsVideo ? Config.thumbnailPath : "file://" + tile.modelData
                        fillMode: Image.PreserveAspectCrop
                        cache: !(tile.inUse && root.currentIsVideo) // A video's saved frame changes under the same path
                        sourceSize.width: 800 // Plenty for a tile, cheap to decode even from a 5K image
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: thumb.status !== Image.Ready
                        text: thumb.status === Image.Error ? "broken_image" : "hourglass_empty"
                        iconSize: 22
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle { // The neighbours sit back: dimmed
                        anchors.fill: parent
                        color: Appearance.colors.colLayer0
                        opacity: (tileMouse.containsMouse ? 0.25 : 0.5) * Math.min(1, tile.distance) // Lighter pointed at
                        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    }
                    Rectangle { // Making its colours
                        anchors.fill: parent
                        visible: tile.busy
                        color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.35)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "progress_activity"
                            iconSize: 30
                            color: Appearance.colors.colPrimary
                            RotationAnimation on rotation { running: tile.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                    }
                }
                Rectangle {
                    visible: tile.inUse
                    anchors { top: parent.top; right: parent.right; margins: 12 }
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
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        carousel.forceActiveFocus();
                        if (tile.centred) root.apply(tile.modelData);
                        else carousel.stepTo(tile.index); // A side one: to the middle first
                    }
                }
            }
        }
        // Arrows either side, over the dimmed neighbours
        ArrowButton {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            symbol: "chevron_left"
            onClicked: carousel.decrementCurrentIndex()
        }
        ArrowButton {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            symbol: "chevron_right"
            onClicked: carousel.incrementCurrentIndex()
        }
    }

    // Where you are in the list: a dot each, the middle one a longer accent pill
    Row {
        visible: carousel.count > 1 && carousel.count <= 20
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        Repeater {
            model: carousel.count
            delegate: Rectangle {
                required property int index
                readonly property bool active: index === carousel.currentIndex
                width: active ? 20 : 6
                height: 6
                radius: 3
                color: active ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                MouseArea {
                    anchors { fill: parent; margins: -4 }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: carousel.stepTo(parent.index)
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
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: root.centred.replace(/^.*\//, "").replace(/\.[^.]+$/, "")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: root.applying !== "" ? Translation.tr("Making the colours…")
                    : root.centredInUse ? Translation.tr("In use") : Translation.tr("Not in use")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.centredInUse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }
        RippleButton { // The accent button: the one thing to do here
            visible: !root.centredInUse && root.centred !== ""
            implicitHeight: 35
            horizontalPadding: 12
            buttonRadius: Appearance.rounding.container
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.apply(root.centred)
            contentItem: RowLayout {
                spacing: 6
                MaterialSymbol {
                    text: "check"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    text: Translation.tr("Use this")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimary
                }
            }
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

    component ArrowButton: RippleButton {
        property string symbol
        visible: carousel.count > 1
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: 20
        colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerHigh, 0.1)
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
        z: 20
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: parent.symbol
            iconSize: 24
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
