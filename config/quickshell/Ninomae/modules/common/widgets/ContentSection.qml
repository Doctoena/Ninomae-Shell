import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A group of settings: its name small above, then its rows, each a card of its own (ConfigSwitch, SettingRow…,
 * or SettingsCard for anything else). In a glass window the rows sit straight on one well instead; in Settings'
 * glass (the window's `titledWells`) the name goes inside the well as its title, after its `icon` on a light
 * squircle, a hairline under it and between the rows. `toggleOption: "crosshair.dot"` puts the group's on/off switch
 * beside its name and hides the rows while it's off. `busy` puts a spinning "Searching" at the name's end.
 */
ColumnLayout {
    id: root
    // In a glass window (`glass: true`: Settings, the control centre): the rows in a well
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    // Settings' glass: the name inside the well, as its title
    readonly property bool titled: glass && (QsWindow.window?.titledWells ?? Window.window?.titledWells ?? false)
    property string title
    property string icon: ""
    property string toggleOption: ""
    property bool busy: false
    property string busyText: Translation.tr("Searching")
    readonly property bool toggledOn: toggleOption === "" || !!Config.get(toggleOption)
    default property alias contentData: sectionContent.data
    Layout.fillWidth: true
    Layout.topMargin: 4
    spacing: 8
    TitleRow { // Above the rows (no glass, or the control centre's)
        visible: root.title.length > 0 && !root.titled
        Layout.leftMargin: 4
        Layout.rightMargin: 4
    }
    Item { // The rows; with glass, in a well (6 px round them)
        visible: root.toggledOn || root.titled // Switched off from the name: just the name (in its well, titled)
        Layout.fillWidth: true
        implicitHeight: wellColumn.implicitHeight + (root.glass ? 12 : 0)
        GlassWell {
            visible: root.glass
            anchors.fill: parent
        }
        ColumnLayout {
            id: wellColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.glass ? 6 : 0 }
            spacing: 0
            TitleRow { // Settings' glass: the title inside the well
                visible: root.titled && root.title.length > 0
                Layout.preferredHeight: 46
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                inWell: true
            }
            Rectangle { // Under the title, over the first row
                visible: root.titled && root.title.length > 0 && root.toggledOn
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                implicitHeight: 1
                color: Appearance.colors.colWellHairline
            }
            ColumnLayout {
                id: sectionContent
                visible: root.toggledOn
                Layout.fillWidth: true
                spacing: root.titled ? 0 : root.glass ? 2 : 4 // Titled: the rows' hairlines part them
            }
        }
    }

    // The name with, at its end, the busy spinner and the group's on/off switch. In the well: bigger, after its icon
    component TitleRow: RowLayout {
        id: titleRow
        property bool inWell: false
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            visible: parent.inWell && root.icon !== ""
            implicitWidth: 30
            implicitHeight: 30
            radius: 10
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 17
                fill: 1
                color: Appearance.colors.colPrimary
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.title
            elide: Text.ElideRight
            font.family: parent.inWell ? Appearance.font.family.title : Appearance.font.family.main
            font.pixelSize: parent.inWell ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small
            font.weight: parent.inWell ? Font.Black : Font.Medium
            color: parent.inWell ? Appearance.colors.colOnLayer1 : root.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
        }
        RowLayout {
            visible: root.busy
            spacing: 5
            MaterialSymbol {
                text: "progress_activity"
                iconSize: 15
                color: Appearance.colors.colPrimary
                RotationAnimation on rotation {
                    running: root.busy && titleRow.visible // Only the shown one of the two title rows
                    from: 0; to: 360; duration: 1000
                    loops: Animation.Infinite
                }
            }
            StyledText {
                text: root.busyText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
            }
        }
        StyledSwitch {
            visible: root.toggleOption !== ""
            sizeScale: 0.6
            checked: root.toggledOn
            onClicked: Config.set(root.toggleOption, checked)
        }
    }
}
