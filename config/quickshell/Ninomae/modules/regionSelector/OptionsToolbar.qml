pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

// Region selector toolbar, in the shell's joined pieces: a line saying how to pick and what letting go does (it
// follows the action and the shape), then what a release does (screenshot / edit / search / text), the
// selection's shape, then whole screen and close, each group a joined strip on the cards' colour like the
// sidebar's toggles. The one in use is tinted, its icon on an accent squircle (an action also shows its name).
// Picks go up through actionPicked and selectionModePicked: the selector keeps them, for every screen. Every
// button has its key in its tooltip
Item {
    id: root
    property var action
    property var selectionMode
    signal actionPicked(var action)
    signal selectionModePicked(var mode)
    signal dismiss()
    signal captureScreen()

    readonly property string pickHint: selectionMode === RegionSelection.SelectionMode.Circle ? Translation.tr("Circle around it")
        : Translation.tr("Drag a box, or click a window")
    readonly property string releaseHint: {
        switch (action) {
            case RegionSelection.SnipAction.Edit: return Translation.tr("letting go saves it and opens it to draw on");
            case RegionSelection.SnipAction.Search: return Translation.tr("letting go searches the web for it");
            case RegionSelection.SnipAction.CharRecognition: return Translation.tr("letting go copies the text in it");
            default: return Translation.tr("letting go saves and copies it");
        }
    }

    implicitWidth: panel.implicitWidth
    implicitHeight: panel.implicitHeight
    StyledRectangularShadow {
        target: panel
    }
    Rectangle {
        id: panel
        anchors.fill: parent
        implicitWidth: column.implicitWidth + 16
        implicitHeight: column.implicitHeight + 16
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: 4
            Rectangle { // How to pick, and what letting go does
                Layout.fillWidth: true
                implicitHeight: 34
                topLeftRadius: Appearance.rounding.normal
                topRightRadius: Appearance.rounding.normal
                bottomLeftRadius: Appearance.rounding.joined
                bottomRightRadius: Appearance.rounding.joined
                color: ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colPrimary, 0.92)
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 8
                    MaterialSymbol {
                        text: "mouse"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.pickHint} · ${root.releaseHint}`
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            RowLayout {
                spacing: 8
                Strip {
                    model: [
                        { action: RegionSelection.SnipAction.Copy, icon: "screenshot_region", label: Translation.tr("Screenshot"),
                            tip: Translation.tr("Save and copy (S)") },
                        { action: RegionSelection.SnipAction.Edit, icon: "edit", label: Translation.tr("Edit"),
                            tip: Translation.tr("Save, copy and draw on it (E). A right-button release does it too") },
                        { action: RegionSelection.SnipAction.Search, icon: "image_search", label: Translation.tr("Search"),
                            tip: Translation.tr("Search the web for it (F). Uploads it to a public file host first") },
                        { action: RegionSelection.SnipAction.CharRecognition, icon: "document_scanner", label: Translation.tr("Text"),
                            tip: Translation.tr("Copy the text in it (T)") },
                    ]
                    isActive: entry => root.action === entry.action
                    onPicked: entry => root.actionPicked(entry.action)
                }
                Strip {
                    model: [
                        { mode: RegionSelection.SelectionMode.RectCorners, icon: "crop_free", tip: Translation.tr("Rectangle, or click a window (Tab)") },
                        { mode: RegionSelection.SelectionMode.Circle, icon: "gesture", tip: Translation.tr("Circle around it (Tab)") },
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
        }
    }

    // A joined strip of buttons: round at its ends, slight between
    component Strip: Row {
        id: strip
        property var model: []
        property var isActive: entry => false
        signal picked(var entry)
        spacing: 3
        Repeater {
            model: strip.model
            delegate: Chip {
                required property var modelData
                required property int index
                icon: modelData.icon
                label: modelData.label ?? ""
                tip: modelData.tip
                active: strip.isActive(modelData)
                first: index === 0
                last: index === strip.model.length - 1
                onClicked: strip.picked(modelData)
            }
        }
    }
    // A piece of a strip: its icon, on the accent squircle when it's the one in use (tinted, its name beside it then,
    // if it has one). A shade on hover
    component Chip: Rectangle {
        id: chip
        property string icon
        property string label: ""
        property string tip
        property bool active: false
        property bool first: false
        property bool last: false
        signal clicked()
        readonly property bool showLabel: active && label !== ""
        implicitWidth: showLabel ? labelText.implicitWidth + 44 + 12 : 44
        implicitHeight: 44
        Behavior on implicitWidth { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        topLeftRadius: first ? Appearance.rounding.small : 4
        bottomLeftRadius: topLeftRadius
        topRightRadius: last ? Appearance.rounding.small : 4
        bottomRightRadius: topRightRadius
        color: active ? ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colPrimary, 0.9)
            : mouse.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        clip: true
        Rectangle {
            id: squircle
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 28; height: 28
            radius: Appearance.rounding.chip
            color: chip.active ? Appearance.colors.colPrimary : "transparent"
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
