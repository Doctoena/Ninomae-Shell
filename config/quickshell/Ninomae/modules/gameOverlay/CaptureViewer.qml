pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.gameLauncher
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * The in-game overlay's viewer for this session's captures, as the launcher's: the screenshot large (a clip
 * plays, click to pause), previous and next at its sides, when it was taken and its size under it with
 * Copy, Open and Trash, and a filmstrip of all of them. Keys (from the overlay, handleKey): ←/→ (Home/End)
 * step through, Ctrl+C copies, Delete trashes (to the Trash, so it can be got back), Esc goes back.
 * Copy puts a screenshot on the clipboard as PNG and a clip as its file, ready to paste into Discord.
 */
Item {
    id: root
    // [{ kind: "shot" | "clip", path, time (ms), width, height, thumb (clips), duration (clips) }], newest first
    property var captures: []
    property int index: -1 // Set by the overlay; the viewer asks for another with goTo
    readonly property var current: index >= 0 && index < captures.length ? captures[index] : null
    readonly property bool isClip: current?.kind === "clip"
    signal backRequested()
    signal goTo(int index)
    signal trashed(string path)

    // ── Actions ──
    property string copiedPath: ""
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedPath = "" }
    function copyCurrent() {
        if (!current) return;
        copier.running = false;
        copier.path = current.path;
        copier.command = isClip
            ? ["bash", "-c", 'printf "file://%s\\n" "$0" | wl-copy --type text/uri-list', current.path]
            // As PNG: Chromium/Electron apps (Vesktop, browsers) only paste image/png, and Steam saves JPEGs
            : ["bash", "-o", "pipefail", "-c", 'case "${0,,}" in *.png) wl-copy --type image/png < "$0" ;; *) magick "$0" png:- | wl-copy --type image/png ;; esac', current.path];
        copier.running = true;
    }
    Process {
        id: copier
        property string path
        onExited: exitCode => { if (exitCode === 0) { root.copiedPath = copier.path; copiedTimer.restart(); } }
    }
    function openCurrent() {
        if (current) Quickshell.execDetached(["xdg-open", current.path]);
    }
    // To the Trash. For Steam's screenshots, their small copy in thumbnails/ goes too
    function trashCurrent() {
        if (!current) return;
        const path = current.path;
        const thumb = path.includes("/760/remote/") ? path.replace(/\/([^/]*)$/, "/thumbnails/$1") : "";
        videoLoader.active = false; // Let go of a clip before it goes
        Quickshell.execDetached(["bash", "-c", 'gio trash -- "$0"; [ -n "$1" ] && [ -f "$1" ] && gio trash -- "$1"', path, thumb]);
        root.trashed(path);
        videoLoader.active = Qt.binding(() => root.isClip);
    }
    function togglePlay() {
        const v = videoLoader.item;
        if (!v) return;
        if (v.playbackState === MediaPlayer.PlayingState) v.pause();
        else { if (v.duration > 0 && v.position >= v.duration - 50) v.position = 0; v.play(); }
    }
    // Keys from the overlay; returns whether it used the key
    function handleKey(event) {
        const n = captures.length;
        switch (event.key) {
        case Qt.Key_Escape: backRequested(); return true;
        case Qt.Key_Left: goTo(Math.max(0, index - 1)); return true;
        case Qt.Key_Right: goTo(Math.min(n - 1, index + 1)); return true;
        case Qt.Key_Home: goTo(0); return true;
        case Qt.Key_End: goTo(n - 1); return true;
        case Qt.Key_Delete: trashCurrent(); return true;
        case Qt.Key_Space: if (isClip) { togglePlay(); return true; } return false;
        case Qt.Key_C: if (event.modifiers & Qt.ControlModifier) { copyCurrent(); return true; } return false;
        }
        return false;
    }
    function timeLabel(ms) {
        const d = new Date(ms);
        return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }
    function lengthLabel(s) {
        return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;
    }

    Rectangle { // Darker than the overlay's own backdrop; a click here goes back to the overlay
        anchors.fill: parent
        anchors.margins: -32 // Past the overlay's margins, to the screen's edges
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea {
            anchors.fill: parent
            onClicked: root.backRequested()
        }
    }

    // ── The capture ──
    Item {
        id: stage
        anchors { top: parent.top; bottom: details.top; bottomMargin: 12; left: parent.left; right: parent.right; leftMargin: 80; rightMargin: 80 }
        readonly property real aspect: (root.current?.width ?? 0) > 0 && (root.current?.height ?? 0) > 0
            ? Math.max(0.5, Math.min(3, root.current.width / root.current.height)) : 16 / 9
        ClippingRectangle {
            id: picture
            anchors.centerIn: parent
            width: Math.round(Math.min(parent.width, parent.height * stage.aspect))
            height: Math.round(width / stage.aspect)
            radius: Appearance.rounding.normal
            color: "black"
            Image { // A screenshot, or a clip's thumbnail until its first frame is up
                anchors.fill: parent
                source: !root.current ? "" : root.isClip ? (root.current.thumb ? "file://" + root.current.thumb : "") : "file://" + root.current.path
                sourceSize.width: root.isClip ? 480 : Math.ceil(picture.width * 1.5) // Sharp without decoding 4K in full
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                retainWhileLoading: true
                visible: !root.isClip || !videoLoader.item || videoLoader.item.position === 0
            }
            Loader { // A player only while a clip is open
                id: videoLoader
                anchors.fill: parent
                active: root.isClip
                sourceComponent: Video {
                    source: root.current ? "file://" + root.current.path : ""
                    fillMode: VideoOutput.PreserveAspectFit
                    onSourceChanged: if (source != "") play()
                    Component.onCompleted: if (source != "") play()
                }
            }
            MouseArea { // Click a clip to pause; a screenshot does nothing (not back to the overlay)
                anchors.fill: parent
                cursorShape: root.isClip ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.togglePlay()
            }
            Rectangle { // A clip paused or ended: a play mark in the middle
                anchors.centerIn: parent
                visible: root.isClip
                width: 64; height: 64
                radius: Appearance.rounding.container + 6
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.3)
                opacity: videoLoader.item && videoLoader.item.playbackState !== MediaPlayer.PlayingState ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: (videoLoader.item?.duration ?? 0) > 0 && videoLoader.item.position >= videoLoader.item.duration - 50 ? "replay" : "play_arrow"
                    fill: 1; iconSize: 34
                    color: Appearance.colors.colOnLayer0
                }
            }
            Rectangle { // A clip's progress, along the bottom
                visible: root.isClip && (videoLoader.item?.duration ?? 0) > 0
                anchors { left: parent.left; bottom: parent.bottom }
                height: 4
                width: parent.width * ((videoLoader.item?.position ?? 0) / Math.max(1, videoLoader.item?.duration ?? 1))
                color: Appearance.colors.colPrimary
            }
        }
        SheetNavButton {
            anchors { right: picture.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            iconName: "chevron_left"; enabled: root.index > 0
            onClicked: root.goTo(root.index - 1)
        }
        SheetNavButton {
            anchors { left: picture.right; leftMargin: 16; verticalCenter: parent.verticalCenter }
            iconName: "chevron_right"; enabled: root.index < root.captures.length - 1
            onClicked: root.goTo(root.index + 1)
        }
    }

    // ── When it was taken, how big, and what to do with it ──
    Rectangle {
        id: details
        anchors { bottom: filmstrip.visible ? filmstrip.top : parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
        width: detailsRow.implicitWidth + 24
        height: 44
        radius: Appearance.rounding.container
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        MouseArea { anchors.fill: parent } // Not back to the overlay
        Row {
            id: detailsRow
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.isClip ? "movie" : "photo_camera"
                iconSize: 18
                color: Appearance.colors.colPrimary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: !root.current ? "" : [
                    root.isClip ? Translation.tr("Clip at %1").arg(root.timeLabel(root.current.time)) : Translation.tr("Screenshot at %1").arg(root.timeLabel(root.current.time)),
                    root.isClip && root.current.duration > 0 ? root.lengthLabel(root.current.duration) : "",
                    root.current.width > 0 ? `${root.current.width} × ${root.current.height}` : "",
                    Translation.tr("%1 of %2").arg(root.index + 1).arg(root.captures.length)
                ].filter(t => t).join("  ·  ")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
            }
            Item { width: 6; height: 1 }
            ViewerAction {
                icon: root.copiedPath !== "" && root.copiedPath === root.current?.path ? "check" : "content_copy"
                tip: root.isClip ? Translation.tr("Copy the clip (Ctrl+C), ready to paste into Discord")
                    : Translation.tr("Copy the screenshot (Ctrl+C)")
                onClicked: root.copyCurrent()
            }
            ViewerAction {
                icon: "open_in_new"
                tip: root.isClip ? Translation.tr("Open in the video player") : Translation.tr("Open in the image viewer")
                onClicked: root.openCurrent()
            }
            ViewerAction {
                icon: "delete"
                danger: true
                tip: Translation.tr("Move to the Trash (Delete)")
                onClicked: root.trashCurrent()
            }
        }
    }

    // ── All of this session's captures; the current one in the middle, with a ring ──
    ListView {
        id: filmstrip
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        readonly property int pad: 4
        width: Math.min(parent.width - 160, contentWidth + pad * 2)
        height: 60 + pad * 2
        leftMargin: pad; rightMargin: pad
        visible: root.captures.length > 1
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.captures
        currentIndex: root.index
        highlightFollowsCurrentItem: true
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: width / 2 - 60
        preferredHighlightEnd: width / 2 + 60
        highlightMoveDuration: 260
        highlight: Item {}
        delegate: Item {
            id: filmItem
            required property var modelData
            required property int index
            width: 107; height: filmstrip.height
            Rectangle {
                anchors.centerIn: parent
                width: parent.width; height: 60
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                ClippingRectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    Image {
                        anchors.fill: parent
                        source: filmItem.modelData.kind === "clip" ? (filmItem.modelData.thumb ? "file://" + filmItem.modelData.thumb : "")
                            : "file://" + filmItem.modelData.path
                        sourceSize.width: 214
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                MaterialSymbol { // A clip
                    anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                    visible: filmItem.modelData.kind === "clip"
                    text: "play_circle"; fill: 1; iconSize: 16
                    color: "white"
                }
                Rectangle { // Current, or hovered
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: parent.radius + 3
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                    visible: filmItem.index === root.index || filmMouse.containsMouse
                    opacity: filmItem.index === root.index ? 1 : 0.5
                }
                MouseArea {
                    id: filmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goTo(filmItem.index)
                }
            }
        }
    }

    // An icon button in the details bar, with its tooltip
    component ViewerAction: Rectangle {
        id: viewerAction
        property string icon
        property string tip
        property bool danger: false
        signal clicked()
        anchors.verticalCenter: parent.verticalCenter
        width: 32; height: 32; radius: Appearance.rounding.segment
        color: actionMouse.containsMouse ? (danger ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2Hover) : Appearance.colors.colLayer2
        MaterialSymbol {
            anchors.centerIn: parent
            text: viewerAction.icon
            iconSize: 18
            color: viewerAction.danger && actionMouse.containsMouse ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: viewerAction.clicked()
        }
        StyledToolTip {
            extraVisibleCondition: actionMouse.containsMouse
            text: viewerAction.tip
        }
    }
}
