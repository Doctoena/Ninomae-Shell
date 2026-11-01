pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

// Region selector toolbar: what a release does (screenshot / edit / search / text) and the selection's shape,
// each a neutral group where the one in use has its icon on an accent squircle (the action also shows its
// name), then whole screen and close. Picks go up through actionPicked and selectionModePicked: the selector
// keeps them, for every screen. Every button has its key in its tooltip
Toolbar {
    id: root
    colBackground: Appearance.colors.colLayer0
    radius: Appearance.rounding.large
    padding: 6
    spacing: 6
    enableShadow: true
    property var action
    property var selectionMode
    signal actionPicked(var action)
    signal selectionModePicked(var mode)
    signal dismiss()
    signal captureScreen()

    Group {
        Repeater {
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
            delegate: Chip {
                required property var modelData
                icon: modelData.icon
                label: modelData.label
                tip: modelData.tip
                active: root.action === modelData.action
                onClicked: root.actionPicked(modelData.action)
            }
        }
    }
    Group {
        Chip {
            icon: "crop_free"
            tip: Translation.tr("Rectangle, or click a window (Tab)")
            active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
            onClicked: root.selectionModePicked(RegionSelection.SelectionMode.RectCorners)
        }
        Chip {
            icon: "gesture"
            tip: Translation.tr("Circle around it (Tab)")
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            onClicked: root.selectionModePicked(RegionSelection.SelectionMode.Circle)
        }
    }
    Chip {
        icon: "fullscreen"
        tip: Translation.tr("Whole screen (Enter)")
        onClicked: root.captureScreen()
    }
    Chip {
        icon: "close"
        tip: Translation.tr("Close (Esc)")
        onClicked: root.dismiss()
    }

    // A neutral group of chips
    component Group: Rectangle {
        default property alias chips: row.data
        implicitWidth: row.implicitWidth + 8
        implicitHeight: row.implicitHeight + 8
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 2
        }
    }
    // A button: its icon, on the accent squircle when it's the one in use, with its name beside it then (if it
    // has one). A shade on hover
    component Chip: Rectangle {
        id: chip
        property string icon
        property string label: ""
        property string tip
        property bool active: false
        signal clicked()
        readonly property bool showLabel: active && label !== ""
        implicitWidth: showLabel ? labelText.implicitWidth + 36 + 12 : 36
        implicitHeight: 36
        Behavior on implicitWidth { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        radius: Appearance.rounding.normal - 4
        color: mouse.containsMouse && !active ? Appearance.colors.colLayer2Hover : "transparent"
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        clip: true
        Rectangle {
            id: squircle
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            width: 28; height: 28
            radius: Appearance.rounding.chip
            color: chip.active ? Appearance.colors.colPrimary : "transparent"
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                text: chip.icon
                iconSize: 20
                fill: chip.active ? 1 : 0
                color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
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
