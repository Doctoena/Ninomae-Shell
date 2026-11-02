import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
Rectangle {
    id: root
    property string entry
    property real maxWidth
    property real maxHeight
    property string imageDecodePath: Directories.cliphistDecode
    property string imageDecodeFileName: `${entryNumber}`
    property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
    property string source
    property int entryNumber: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/^(\d+)\t/);
        return match ? parseInt(match[1]) : 0;
    }
    property int imageWidth: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/(\d+)x(\d+)/);
        return match ? parseInt(match[1]) : 0;
    }
    property int imageHeight: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/(\d+)x(\d+)/);
        return match ? parseInt(match[2]) : 0;
    }
    property real imageScale: {
        return Math.min(root.maxWidth / imageWidth, root.maxHeight / imageHeight, 1);
    }
    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.small
    implicitHeight: imageHeight * scale
    implicitWidth: imageWidth * scale
    Component.onCompleted: {
        decodeImageProcess.running = true;
    }
    Process {
        id: decodeImageProcess
        // Path and entry are arguments, not script text
        command: ["bash", "-c", `bin="$0" out="$1" e="$2"; [ -s "$out" ] || ${Cliphist.decodeCommand()} > "$out"`,
            Cliphist.cliphistBinary, root.imageDecodeFilePath, root.entry]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.source = imageDecodeFilePath;
            } else {
                console.error("[CliphistImage] Failed to decode image for entry:", root.entry);
                root.source = "";
            }
        }
    }
    Component.onDestruction: {
        Quickshell.execDetached(["rm", "-f", "--", imageDecodeFilePath]);
    }
    layer.enabled: true
    layer.effect: RoundedMask { maskWidth: image.width; maskHeight: image.height; radius: root.radius }
    StyledImage {
        id: image
        anchors.fill: parent
        source: Qt.resolvedUrl(root.source)
        fillMode: Image.PreserveAspectFit
        antialiasing: true
        asynchronous: true
        width: root.imageWidth * root.imageScale
        height: root.imageHeight * root.imageScale
        // Width only (the picture keeps its shape), in steps: the overview's preview pane sizes it from its
        // own height, which eases as the drawer opens, and every new sourceSize decodes the picture again.
        // Never past its own width (that would enlarge it), and never 0 (that's full size)
        sourceSize.width: Math.max(1, Math.min(root.imageWidth, Math.ceil(width / 128) * 128))
    }
}
