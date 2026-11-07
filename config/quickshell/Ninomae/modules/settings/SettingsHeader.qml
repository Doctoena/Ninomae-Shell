import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Settings' header (and the control centre's): the page's icon on an accent squircle, its group small over its
 * name (large and bold) and the line about it, and the search box (Ctrl K) and Close on the right.
 * The search's keys come out as signals, so the window decides what Up, Down and Enter do. `searchable: false`
 * leaves the search out; children go on the right, before Close (the control centre's on/off switch).
 */
Item {
    id: header
    required property var page // { name, group, icon, iconRotation, description }
    property alias searchField: field
    property alias searchBox: searchBox // The results panel hangs just under it
    property bool searchable: true
    default property alias extras: extraRow.data
    signal closeClicked()
    signal searchMoved(int step) // Up / Down in the results
    signal searchAccepted() // Enter
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right }
        spacing: 16

        Rectangle {
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 4
            implicitWidth: 52
            implicitHeight: 52
            radius: Appearance.rounding.normal
            color: Appearance.colors.colPrimary
            MaterialSymbol {
                anchors.centerIn: parent
                text: header.page.icon
                rotation: header.page.iconRotation || 0
                iconSize: 28
                fill: 1
                color: Appearance.colors.colOnPrimary
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: header.page.group
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: header.page.name
                font.family: Appearance.font.family.title
                font.pixelSize: 34
                font.weight: Font.Black
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: header.page.description ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: extraRow
            Layout.alignment: Qt.AlignTop
            Layout.minimumHeight: 42 // As tall as Close: what's in it lines up with it
            visible: children.length > 0
            spacing: 8
        }
        Rectangle { // Search: any option on any page, and keybinds
            id: searchBox
            visible: header.searchable
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Math.min(300, header.width * 0.36)
            implicitHeight: 42
            radius: height / 2
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: field.activeFocus ? 2 : 0
            border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
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
        RippleButton {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 42
            implicitHeight: 42
            buttonRadius: 21
            colBackground: Appearance.m3colors.m3surfaceContainerHigh
            colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
            onClicked: header.closeClicked()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "close"
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
