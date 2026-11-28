pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Region selector toolbar (O2): a drawer rising from the bottom edge, joined to it by curves like the bar's drawers.
// What a release does (screenshot / edit / search / text), the selection's shape, then whole screen and close, as
// icons: the one in use on an accent squircle with its name beside it, every key in its tooltip. What letting go does
// is said on the box itself (SelectionCard).
// The selector's dark unblurred glass (a blur would blur the frozen screen, and with Glass panels off it's solid) with a
// fine rim round its curves and top, each group in a well, its buttons straight on it (a soft card when pointed at).
// Picks go up through actionPicked and selectionModePicked: the selector keeps them, for every screen
Item {
    id: root
    property var action
    property var selectionMode
    signal actionPicked(var action)
    signal selectionModePicked(var mode)
    signal dismiss()
    signal captureScreen()
    readonly property real join: Appearance.rounding.large // The curves joining it to the edge
    readonly property real radius: Appearance.rounding.large

    implicitWidth: groups.implicitWidth + 32 + join * 2
    implicitHeight: groups.implicitHeight + 20

    // The drawer: its sides rise from the edge in curves, round at its top
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer // Antialiases by itself: no layer needed
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Appearance.colors.colGlassUnblurred
            startX: 0; startY: root.height
            PathArc { x: root.join; y: root.height - root.join; radiusX: root.join; radiusY: root.join; direction: PathArc.Counterclockwise }
            PathLine { x: root.join; y: root.radius }
            PathArc { x: root.join + root.radius; y: 0; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: root.width - root.join - root.radius; y: 0 }
            PathArc { x: root.width - root.join; y: root.radius; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: root.width - root.join; y: root.height - root.join }
            PathArc { x: root.width; y: root.height; radiusX: root.join; radiusY: root.join; direction: PathArc.Counterclockwise }
        }
        ShapePath { // Glass: the fine rim, from one curve's tip round to the other's (none along the edge)
            strokeWidth: 1
            strokeColor: Appearance.colors.colGlassFieldRim
            fillColor: "transparent"
            startX: 0; startY: root.height
            PathArc { x: root.join; y: root.height - root.join; radiusX: root.join; radiusY: root.join; direction: PathArc.Counterclockwise }
            PathLine { x: root.join; y: root.radius }
            PathArc { x: root.join + root.radius; y: 0; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: root.width - root.join - root.radius; y: 0 }
            PathArc { x: root.width - root.join; y: root.radius; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: root.width - root.join; y: root.height - root.join }
            PathArc { x: root.width; y: root.height; radiusX: root.join; radiusY: root.join; direction: PathArc.Counterclockwise }
        }
    }
    EdgeLight { // Glass: a light along its top, brightest in the middle
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.join + 60; rightMargin: root.join + 60; topMargin: 1 }
        strength: 0.35
    }
    RowLayout {
        id: groups
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 10 }
        spacing: 8
        Strip {
            model: [RegionSelection.SnipAction.Copy, RegionSelection.SnipAction.Edit, RegionSelection.SnipAction.Search,
                RegionSelection.SnipAction.CharRecognition].map(a => {
                const info = RegionFunctions.actionInfo(a);
                return { action: a, icon: info.icon, label: info.name, tip: info.tip };
            })
            isActive: entry => root.action === entry.action
            onPicked: entry => root.actionPicked(entry.action)
        }
        Strip {
            model: [
                { mode: RegionSelection.SelectionMode.RectCorners, icon: "crop_free", label: Translation.tr("Box"), tip: Translation.tr("Rectangle, or click a window (Tab)") },
                { mode: RegionSelection.SelectionMode.Circle, icon: "gesture", label: Translation.tr("Circle"), tip: Translation.tr("Circle around it (Tab)") },
            ]
            isActive: entry => root.selectionMode === entry.mode
            onPicked: entry => root.selectionModePicked(entry.mode)
        }
        Strip {
            model: [
                { id: "screen", icon: "fullscreen", tip: Translation.tr("Whole screen (Enter)") },
                { id: "close", icon: "close", tip: Translation.tr("Close (Esc)") },
            ]
            isActive: entry => false
            onPicked: entry => entry.id === "screen" ? root.captureScreen() : root.dismiss()
        }
    }

    // A group of buttons, in a well, 4 px round them
    component Strip: Item {
        id: strip
        property var model: []
        property var isActive: entry => false
        signal picked(var entry)
        readonly property real pad: 4
        implicitWidth: chips.implicitWidth + pad * 2
        implicitHeight: chips.implicitHeight + pad * 2
        GlassWell {
            anchors.fill: parent
            radius: Appearance.rounding.small + 4
        }
        Row {
            id: chips
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: strip.model
                delegate: Chip {
                    required property var modelData
                    icon: modelData.icon
                    label: modelData.label ?? ""
                    tip: modelData.tip
                    active: strip.isActive(modelData)
                    onClicked: strip.picked(modelData)
                }
            }
        }
    }
    // A button: its icon, on the accent squircle when it's the one in use, its name beside it then. A shade on hover
    component Chip: Rectangle {
        id: chip
        property string icon
        property string label: ""
        property string tip
        property bool active: false
        signal clicked()
        readonly property bool showLabel: active && label !== ""
        implicitWidth: showLabel ? labelText.implicitWidth + 44 + 12 : 44
        implicitHeight: 44
        Behavior on implicitWidth { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        clip: true
        radius: Appearance.rounding.small
        // Glass: straight on its well, the soft card when pointed at
        color: (mouse.containsMouse ? Appearance.colors.colWellRowHover : ColorUtils.transparentize(Appearance.colors.colWellRowHover, 1))
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        Rectangle {
            id: squircle
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 28; height: 28
            radius: Appearance.rounding.chip
            color: chip.active ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 1)
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                text: chip.icon
                iconSize: 20
                fill: chip.active ? 1 : 0
                color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            }
        }
        StyledText {
            id: labelText
            anchors { left: squircle.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            opacity: chip.showLabel ? 1 : 0
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Medium
            color: Appearance.colors.colPrimary
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
        StyledToolTip {
            extraVisibleCondition: mouse.containsMouse
            text: chip.tip
        }
    }
}
