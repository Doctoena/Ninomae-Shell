import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Settings' header (and the control centre's): the page's icon on an accent squircle, its group small over its
 * name (large and bold) and the line about it, and the search box (Ctrl K) and Close on the right. In Settings'
 * glass (`titledWells`) it's a compact banner, a faint accent wash fading out by its middle, without the group.
 * The search's keys come out as signals, so the window decides what Up, Down and Enter do. `searchable: false`
 * leaves the search out; children go on the right, before Close (the control centre's on/off switch).
 */
Item {
    id: header
    // In a glass window (`glass: true`: Settings, the control centre): Appearance's colWindowGlass* shades
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    readonly property bool titled: glass && (QsWindow.window?.titledWells ?? Window.window?.titledWells ?? false)
    required property var page // { name, group, icon, iconRotation, description }
    property alias searchField: field
    property alias searchBox: searchBox // The results panel hangs just under it
    property bool searchable: true
    default property alias extras: extraRow.data
    signal closeClicked()
    signal searchMoved(int step) // Up / Down in the results
    signal searchAccepted() // Enter
    implicitHeight: titled ? 76 : row.implicitHeight

    Rectangle { // Settings' glass: the faint accent wash, gone by the middle
        visible: header.titled
        anchors.fill: parent
        radius: Appearance.rounding.large
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84) }
            GradientStop { position: 0.5; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 1) }
        }
    }
    RowLayout {
        id: row
        anchors {
            left: parent.left; right: parent.right
            leftMargin: header.titled ? 16 : 0; rightMargin: header.titled ? 16 : 0
            verticalCenter: header.titled ? parent.verticalCenter : undefined
        }
        spacing: 16

        Rectangle {
            Layout.alignment: header.titled ? Qt.AlignVCenter : Qt.AlignBottom
            Layout.bottomMargin: header.titled ? 0 : 4
            implicitWidth: header.titled ? 44 : 52
            implicitHeight: implicitWidth
            radius: header.titled ? 14 : Appearance.rounding.normal
            color: Appearance.colors.colPrimary
            EdgeLight { // Glass: a light along its top, as the shell's other accent squircles
                visible: header.glass
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 1 }
                strength: 0.6
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: header.page.icon
                rotation: header.page.iconRotation || 0
                iconSize: header.titled ? 24 : 28
                fill: 1
                color: Appearance.colors.colOnPrimary
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                visible: (header.page.group ?? "") !== "" && !header.titled
                text: header.page.group ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: header.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: header.page.name
                font.family: Appearance.font.family.title
                font.pixelSize: header.titled ? 26 : 34
                font.weight: Font.Black
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: header.page.description ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: header.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: extraRow
            Layout.alignment: header.titled ? Qt.AlignVCenter : Qt.AlignTop
            Layout.minimumHeight: 42 // As tall as Close: what's in it lines up with it
            visible: children.length > 0
            spacing: 8
        }
        Rectangle { // Search: any option on any page, and keybinds
            id: searchBox
            visible: header.searchable
            Layout.alignment: header.titled ? Qt.AlignVCenter : Qt.AlignTop
            Layout.preferredWidth: Math.min(300, header.width * 0.36)
            implicitHeight: 42
            radius: height / 2
            // Settings' glass: a darker field with a fine rim, as the launcher's search
            color: header.titled ? Appearance.colors.colGlassField : Appearance.m3colors.m3surfaceContainerHigh
            border.width: field.activeFocus ? 2 : header.titled ? 1 : 0
            border.color: field.activeFocus ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : Appearance.colors.colGlassFieldRim
            MaterialSymbol {
                id: searchIcon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "search"
                iconSize: 18
                color: Appearance.colors.colOnSurfaceVariant
            }
            TextField {
                id: field
                anchors {
                    left: searchIcon.right; leftMargin: 8
                    right: field.text !== "" ? clearButton.left : keyHint.left; rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                background: null
                padding: 0
                color: Appearance.colors.colOnLayer1
                placeholderText: Translation.tr("Search settings")
                placeholderTextColor: Appearance.colors.colSubtext
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smallie
                selectionColor: Appearance.colors.colSecondaryContainer
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Down) header.searchMoved(1);
                    else if (event.key === Qt.Key_Up) header.searchMoved(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) header.searchAccepted();
                    else if (event.key === Qt.Key_Escape && text !== "") text = "";
                    else return;
                    event.accepted = true;
                }
            }
            Rectangle { // The shortcut, until something's typed
                id: keyHint
                visible: field.text === ""
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                implicitWidth: hintText.implicitWidth + 12
                implicitHeight: 22
                radius: Appearance.rounding.chip
                color: "transparent"
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                StyledText {
                    id: hintText
                    anchors.centerIn: parent
                    text: "Ctrl K"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButton {
                id: clearButton
                visible: field.text !== ""
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: 15
                colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
                onClicked: field.text = ""
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: 16
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
        RippleButton { // Close: a compact squircle in the cards' shade (on glass, the soft card)
            Layout.alignment: header.titled ? Qt.AlignVCenter : Qt.AlignTop
            Layout.topMargin: header.titled ? 0 : 6
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: 9
            colBackground: header.glass ? Appearance.colors.colWellRowHover : Appearance.m3colors.m3surfaceContainer
            colBackgroundHover: header.glass ? Appearance.colors.colWellRowActive : Appearance.m3colors.m3surfaceContainerHigh
            colRipple: header.glass ? Appearance.colors.colWellRowActive : Appearance.m3colors.m3surfaceContainerHighest
            onClicked: header.closeClicked()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "close"
                iconSize: 18
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
