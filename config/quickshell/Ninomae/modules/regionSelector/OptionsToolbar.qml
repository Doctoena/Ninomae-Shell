pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
// Region selector toolbar: the action (screenshot / search / text), the selection shape, whole screen
// and close. Picking an action here changes what happens on release. Squircle style like the rest of
// the shell: a neutral surface, and the active choice shows as an accent squircle behind its icon
Toolbar {
    id: root
    colBackground: Appearance.colors.colLayer0
    radius: Appearance.rounding.normal
    padding: 6
    spacing: 2
    enableShadow: true
    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()
    signal captureScreen()

    component Divider: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        implicitWidth: 1
        implicitHeight: 24
        color: Appearance.colors.colOutlineVariant
    }
    // Same button as the sidebar's quick-toggle tiles (GroupButton): a shade on hover, a deeper one
    // and a little bounce while pressed, corners rounding off toward a pill as it's held
    component ChipButton: GroupButton {
        id: chip
        property string iconName
        property string label: ""
        property string tooltip: ""
        Layout.fillWidth: false
        Layout.fillHeight: false
        baseHeight: 40
        baseWidth: label.length > 0 ? chipRow.implicitWidth + 16 : 40
        buttonRadius: 13
        buttonRadiusPressed: height / 2
        // The button itself stays neutral when toggled; only the icon squircle turns accent
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0Hover, 1)
        colBackgroundHover: Appearance.colors.colLayer0Hover
        colBackgroundActive: Appearance.colors.colLayer0Active
        colBackgroundToggled: colBackground
        colBackgroundToggledHover: Appearance.colors.colLayer0Hover
        colBackgroundToggledActive: Appearance.colors.colLayer0Active
        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 10
                    color: chip.toggled ? Appearance.colors.colPrimary : "transparent"
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: chip.iconName
                        iconSize: 20
                        fill: chip.toggled ? 1 : 0
                        color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                    }
                }
                StyledText {
                    visible: chip.label.length > 0
                    Layout.rightMargin: 6
                    text: chip.label
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Medium
                    color: chip.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }
        }
        StyledToolTip {
            extraVisibleCondition: chip.tooltip.length > 0
            text: chip.tooltip
        }
    }

    // Actions
    Repeater {
        model: [
            { action: RegionSelection.SnipAction.Copy, icon: "screenshot_region", label: Translation.tr("Screenshot"),
                tooltip: Translation.tr("Save and copy (S)\nRelease with the right button to edit") },
            { action: RegionSelection.SnipAction.Search, icon: "image_search", label: Translation.tr("Search"),
                tooltip: Translation.tr("Search the web for this image (F)\nUploads it to a public file host first") },
            { action: RegionSelection.SnipAction.CharRecognition, icon: "document_scanner", label: Translation.tr("Text"),
                tooltip: Translation.tr("Copy the text in it (T)") },
        ]
        delegate: ChipButton {
            required property var modelData
            iconName: modelData.icon
            label: modelData.label
            tooltip: modelData.tooltip
            toggled: modelData.action === RegionSelection.SnipAction.Copy ? (root.action === RegionSelection.SnipAction.Copy || root.action === RegionSelection.SnipAction.Edit)
                : root.action === modelData.action
            onClicked: root.action = modelData.action
        }
    }
    Divider {}

    // Selection shape
    ChipButton {
        iconName: "crop_free"
        tooltip: Translation.tr("Rectangle (Tab)")
        toggled: root.selectionMode === RegionSelection.SelectionMode.RectCorners
        onClicked: root.selectionMode = RegionSelection.SelectionMode.RectCorners
    }
    ChipButton {
        iconName: "gesture"
        tooltip: Translation.tr("Circle to select (Tab)")
        toggled: root.selectionMode === RegionSelection.SelectionMode.Circle
        onClicked: root.selectionMode = RegionSelection.SelectionMode.Circle
    }
    ChipButton {
        iconName: "fullscreen"
        tooltip: Translation.tr("Whole screen (Enter)")
        onClicked: root.captureScreen()
    }

    Divider {}

    // Close
    ChipButton {
        iconName: "close"
        tooltip: Translation.tr("Close (Esc)")
        onClicked: root.dismiss()
    }
}
