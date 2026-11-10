import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Reload result: a drawer that drops out of the middle of the bar with the gooey blob animation,
// the same pieces as onScreenDisplay/OnScreenDisplay.qml.
// - Reloaded: a small pill naming the file you saved. The first good reload after a failure says it's fixed.
// - Failed: a red card whose title is the error, the file and line under it, the code around that line,
//   and Dismiss / Copy error / Open in editor. It stays while hovered.
Scope {
    id: root
    property bool open: false
    property bool failed: false
    property string errorString: ""
    property string savedFile: "" // The file whose save caused this reload, if it can be told
    property string fixedWhat: "" // What the failure before this good reload pointed at ("BarContent.qml line 42")
    readonly property bool fixed: !failed && fixedWhat !== ""

    // Where it broke: the last "caused by @path[line:col]: message" is the root cause
    property string errorPath: "" // Relative to the shell's folder
    property int errorLine: -1
    property int errorColumn: -1
    property string errorMessage: ""
    property var codeLines: [] // [{ n, text }] around errorLine

    readonly property string errorFile: errorPath.split("/").pop()
    readonly property string errorFullPath: errorPath === "" ? "" : FileUtils.trimFileProtocol(Quickshell.shellPath(errorPath))
    readonly property int lifetime: failed ? 10000 : (fixed ? 2800 : 1800)

    // Survives the reload, so the next good one knows the last one failed and where
    PersistentProperties {
        id: persist
        reloadableId: "reloadPopup"
        property string lastFailure: "" // "BarContent.qml line 42"
    }

    function parseError(error) {
        // "[-1:-1]" lines ("Type X unavailable") only pass the blame on, so the cause is the last one with a line
        const pattern = /@([^\s\[]+)\[(-?\d+):(-?\d+)\]:\s*(.+)/g;
        let cause = null;
        let last = null;
        for (let m; (m = pattern.exec(error)) !== null; last = m)
            if (parseInt(m[2]) > 0) cause = m;
        errorPath = cause ? cause[1] : "";
        errorLine = cause ? parseInt(cause[2]) : -1;
        errorColumn = cause ? parseInt(cause[3]) : -1;
        errorMessage = (cause ?? last)?.[4].trim() ?? "";
        codeLines = [];
        if (cause) {
            const first = Math.max(1, errorLine - 2);
            codeProcess.command = ["awk", `NR>=${first} && NR<=${errorLine + 1} { print NR "\\t" $0 }`, errorFullPath];
            codeProcess.running = true;
        }
    }

    function showFailure(error) {
        failed = true;
        errorString = (error ?? "").trim();
        parseError(errorString);
        persist.lastFailure = errorPath !== ""
            ? Translation.tr("%1 line %2").arg(errorFile).arg(errorLine)
            : Translation.tr("The config");
        open = true;
        countdown.restart();
    }

    function showSuccess() {
        failed = false;
        fixedWhat = persist.lastFailure;
        persist.lastFailure = "";
        open = true;
        countdown.restart();
    }

    function openInEditor() {
        if (errorFullPath === "") return;
        Quickshell.execDetached(["bash", "-c",
            'if command -v code >/dev/null; then code -g "$1:$2:$3"; else xdg-open "$1"; fi',
            "_", errorFullPath, String(Math.max(1, errorLine)), String(Math.max(1, errorColumn))]);
        open = false;
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { savedFileProcess.running = true; } // Shown once it's known what was saved
        function onReloadFailed(error: string) { root.showFailure(error); }
    }

    Process { // The code around the broken line
        id: codeProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.codeLines = text.split("\n").filter(l => l !== "").map(l => {
                    const tab = l.indexOf("\t");
                    return { n: parseInt(l.slice(0, tab)), text: l.slice(tab + 1).replace(/\t/g, "    ") };
                });
            }
        }
    }

    Process { // The QML file saved in the last few seconds, which is what reloaded the shell
        id: savedFileProcess
        command: ["bash", "-c", 'find "$1" -name "*.qml" -mmin -1 -printf "%T@ %f\\n" 2>/dev/null | sort -n | tail -1 | cut -d" " -f2-',
            "_", FileUtils.trimFileProtocol(Quickshell.shellPath(""))]
        stdout: StdioCollector {
            onStreamFinished: root.savedFile = text.trim()
        }
        onExited: root.showSuccess()
    }

    // 1 → 0 over the lifetime; paused while the pointer is on the drawer
    property real remaining: 1
    NumberAnimation {
        id: countdown
        target: root; property: "remaining"
        from: 1; to: 0
        duration: root.lifetime
        paused: running && drawer.hovered
        onFinished: root.open = false
    }

    PanelWindow {
        id: drawer
        readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
        readonly property real padding: root.failed ? 16 : 10
        readonly property real bottomRadius: root.failed ? Appearance.rounding.large : 22
        readonly property real hiddenExtra: 60
        readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        readonly property real failureWidth: 508
        readonly property real panelWidth: (root.failed ? failureWidth : successContent.implicitWidth) + padding * 2
        readonly property real fullHeight: (root.failed ? failureContent.implicitHeight + 10 : successContent.implicitHeight) + padding * 2 // + countdown line
        readonly property bool hovered: hoverArea.containsMouse

        readonly property bool ready: readiness.ready // Slide only once the window is on screen

        // 0 = out, 1 = tucked under the bar
        property real offsetScale: (root.open && ready) ? 0 : 1
        Behavior on offsetScale {
            NumberAnimation {
                duration: root.open ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.open ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
        readonly property real drawerY: Math.min(0, drawerTop)
        readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
        readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

        visible: root.open || offsetScale < 1 // Stay mapped while retracting
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"
        WlrLayershell.namespace: "quickshell:reloadPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: !GlobalStates.barAtBottom // Horizontally centred
        anchors.bottom: GlobalStates.barAtBottom
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins.bottom: GlobalStates.barAtBottom ? barBottom : 0 // Or right above it, along the bottom
        margins.top: GlobalStates.barAtBottom ? 0 : barBottom // Directly below the bar, which skips its border here (BarJoin)
        implicitWidth: panelWidth + sideMargin * 2
        implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
        mask: Region { item: maskArea }

        Item {
            id: maskArea
            x: drawer.sideMargin
            y: GlobalStates.barAtBottom ? drawer.height - height : 0
            width: drawer.panelWidth
            height: drawer.visibleHeight
            MouseArea { // Hover pauses the countdown; a click anywhere else on the drawer dismisses it
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open = false
            }
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true
            transform: BarSideFlip { size: stage.height } // Bar along the bottom: rises from it

            DrawerReadiness {
                id: readiness
                active: drawer.visible
            }
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                name: "reloadPopup"
                active: drawer.visible && drawer.visibleHeight > 0
                joinX: ((drawer.screen?.width ?? 0) - drawer.implicitWidth) / 2 + drawer.sideMargin
                joinWidth: drawer.panelWidth
            }

            DrawerBackground { // Shared with the other drawers
                id: background
                anchors.fill: parent
                active: drawer.visible
                drawerX: drawer.sideMargin
                drawerY: drawer.drawerY
                drawerWidth: drawer.panelWidth
                drawerHeight: drawer.drawerHeight
                drawerRadius: Math.min(drawer.bottomRadius, drawer.visibleHeight / 2)
                fallbackRadius: drawer.bottomRadius
            }

            Item {
                id: contentFrame
                x: drawer.sideMargin
                y: drawer.drawerY
                width: drawer.panelWidth
                height: drawer.fullHeight
                opacity: 1 - drawer.offsetScale
                transform: [
                    BarSideFlip { size: drawer.fullHeight }, // Upright in a flipped stage
                    Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob
                ]

                // ── Reloaded ──
                RowLayout {
                    id: successContent
                    visible: !root.failed
                    x: drawer.padding
                    y: drawer.padding
                    spacing: 10

                    Item {
                        implicitWidth: 30
                        implicitHeight: 30
                        Halo { // Only for "fixed": the moment worth noticing
                            visible: root.fixed
                            colour: Appearance.colors.colPrimary
                            strength: 0.45
                            reach: 24
                            centreX: 15
                            centreY: 15
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.segment
                            color: root.fixed ? Appearance.colors.colLayer4 : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            border.width: root.fixed ? 1 : 0
                            border.color: Qt.rgba(1, 1, 1, 0.06)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.fixed ? "task_alt" : "check"
                                iconSize: 18
                                fill: 1
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            Layout.rightMargin: 6
                            text: root.fixed ? Translation.tr("Fixed, shell reloaded") : Translation.tr("Shell reloaded")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: root.fixed ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.rightMargin: 6
                            visible: text !== ""
                            text: root.fixed ? Translation.tr("%1 works now").arg(root.fixedWhat) : root.savedFile
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // ── Reload failed ──
                ColumnLayout {
                    id: failureContent
                    visible: root.failed
                    x: drawer.padding
                    y: drawer.padding
                    width: drawer.failureWidth
                    spacing: 4

                    // What broke, and where
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(cardColumn.implicitHeight, errorTile.height) + 32
                        topLeftRadius: Appearance.rounding.normal
                        topRightRadius: Appearance.rounding.normal
                        bottomLeftRadius: Appearance.rounding.joined
                        bottomRightRadius: Appearance.rounding.joined
                        color: ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colError, 0.88)
                        border.width: 1.5
                        border.color: ColorUtils.transparentize(Appearance.colors.colError, 0.6)
                        clip: true

                        Halo {
                            colour: Appearance.colors.colError
                            strength: 0.38
                            reach: 42
                            centreX: errorTile.x + errorTile.width / 2
                            centreY: errorTile.y + errorTile.height / 2
                        }
                        Rectangle {
                            id: errorTile
                            x: 16
                            y: 16
                            width: 56
                            height: 56
                            radius: width * 0.28
                            color: Appearance.colors.colLayer4
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.06)
                            MaterialSymbol {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "error"
                                iconSize: 32
                                fill: 1
                                color: Appearance.colors.colError
                            }
                        }
                        ColumnLayout {
                            id: cardColumn
                            anchors { left: errorTile.right; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 16 }
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Reload failed · still running the last working config")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: ColorUtils.mix(Appearance.colors.colSubtext, Appearance.colors.colError, 0.65)
                            }
                            StyledText { // The error itself is the title
                                Layout.fillWidth: true
                                text: root.errorMessage !== "" ? root.errorMessage : Translation.tr("Reload failed")
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.title
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colError
                            }
                            RowLayout {
                                Layout.topMargin: 4
                                visible: root.errorPath !== ""
                                spacing: 6
                                MaterialSymbol {
                                    text: "description"
                                    iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    readonly property string folder: root.errorPath.slice(0, root.errorPath.length - root.errorFile.length)
                                    textFormat: Text.StyledText
                                    text: `${StringUtils.escapeHtml(folder)}<b>${StringUtils.escapeHtml(root.errorFile)}</b>  ·  ${Translation.tr("line %1").arg(root.errorLine)}`
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer3
                                }
                            }
                        }
                    }

                    // The code around it, the broken line marked
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.codeLines.length > 0
                        implicitHeight: codeColumn.implicitHeight + 20
                        radius: Appearance.rounding.joined
                        color: Appearance.colors.colLayer3
                        clip: true
                        Column {
                            id: codeColumn
                            y: 10
                            width: parent.width
                            Repeater {
                                model: root.codeLines
                                Rectangle {
                                    required property var modelData
                                    readonly property bool broken: modelData.n === root.errorLine
                                    width: codeColumn.width
                                    height: 22
                                    color: broken ? ColorUtils.transparentize(Appearance.colors.colError, 0.86) : "transparent"
                                    Rectangle {
                                        visible: parent.broken
                                        width: 3
                                        height: parent.height
                                        color: Appearance.colors.colError
                                    }
                                    StyledText {
                                        x: 14
                                        width: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: parent.modelData.n
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: parent.broken ? Appearance.colors.colError : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        x: 54
                                        width: parent.width - x - 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.text
                                        elide: Text.ElideRight
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: parent.broken ? Appearance.colors.colOnLayer3 : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.4)
                                    }
                                }
                            }
                        }
                    }

                    // No file to point at: the whole error, as it came
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.codeLines.length === 0 && root.errorString !== ""
                        implicitHeight: rawError.implicitHeight + 20
                        radius: Appearance.rounding.joined
                        color: Appearance.colors.colLayer3
                        StyledText {
                            id: rawError
                            x: 14
                            y: 10
                            width: parent.width - 28
                            text: root.errorString
                            wrapMode: Text.WrapAnywhere // Paths and type names have no spaces to break at
                            maximumLineCount: 10
                            elide: Text.ElideRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer3
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        PopupButton {
                            Layout.preferredWidth: 110
                            buttonRadiusBottomLeft: Appearance.rounding.normal
                            label: Translation.tr("Dismiss")
                            onClicked: root.open = false
                        }
                        PopupButton {
                            id: copyButton
                            property bool copied: false
                            Layout.preferredWidth: 130
                            Layout.fillWidth: root.errorPath === ""
                            buttonRadiusBottomRight: root.errorPath === "" ? Appearance.rounding.normal : Appearance.rounding.joined
                            label: copied ? Translation.tr("Copied") : Translation.tr("Copy error")
                            onClicked: {
                                Quickshell.clipboardText = root.errorString;
                                copied = true;
                                copiedReset.restart();
                            }
                            Timer { id: copiedReset; interval: 1500; onTriggered: copyButton.copied = false }
                        }
                        PopupButton {
                            Layout.fillWidth: true
                            visible: root.errorPath !== ""
                            primary: true
                            buttonRadiusBottomRight: Appearance.rounding.normal
                            label: Translation.tr("Open in editor")
                            onClicked: root.openInEditor()
                        }
                    }
                }

                // Countdown to auto-dismiss (paused while hovered)
                Rectangle {
                    visible: root.failed
                    anchors { bottom: parent.bottom; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
                    width: (parent.width - drawer.bottomRadius * 2) * root.remaining
                    height: 3
                    radius: 1.5
                    color: Appearance.colors.colError
                    opacity: drawer.hovered ? 0.35 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }
        }
    }

    component PopupButton: RippleButton {
        id: popupButton
        property bool primary: false
        property string label
        implicitHeight: 44
        buttonRadius: Appearance.rounding.joined
        colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
        contentItem: StyledText {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: popupButton.label
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: popupButton.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
        }
    }
}
