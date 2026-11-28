pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

/**
 * One row of a tray icon's menu (T2b), straight on the menu's well. Compact: 34 px. The row you're on is the glass's
 * soft card with a short accent bar at its left edge, its name the accent and an arrow; a submenu has a ›. On/off
 * entries are switches, choices radio buttons, on the right. "Quit" / "Exit" are red. Entries the app greys out
 * stay dim. A separator (the app's sections) is a hairline.
 */
RippleButton {
    id: root
    required property QsMenuEntry menuEntry
    property bool forceIconColumn: false
    readonly property bool hasIcon: menuEntry.icon.length > 0
    readonly property bool isCheck: menuEntry.buttonType === QsMenuButtonType.CheckBox
    readonly property bool isRadio: menuEntry.buttonType === QsMenuButtonType.RadioButton
    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle, title: string)
    readonly property bool danger: /^(quit|exit)\b/i.test(menuEntry.text ?? "")
    readonly property bool lit: hovered && enabled && !menuEntry.isSeparator
    readonly property color accent: danger ? Appearance.colors.colError : Appearance.colors.colPrimary

    enabled: !menuEntry.isSeparator && menuEntry.enabled !== false
    opacity: menuEntry.isSeparator || menuEntry.enabled !== false ? 1 : 0.45
    implicitWidth: Math.max(220, contentItem.implicitWidth + 28)
    implicitHeight: menuEntry.isSeparator ? 7 : 34
    Layout.fillWidth: true

    buttonRadius: Appearance.rounding.normal - 4 // 4 px in from the well's edge: concentric with its corners
    colBackground: "transparent"
    colBackgroundHover: menuEntry.isSeparator ? "transparent" : Appearance.colors.colWellRowHover
    colRipple: Appearance.colors.colWellRowActive

    Rectangle { // A separator: a hairline across the well
        visible: root.menuEntry.isSeparator
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
        height: 1
        color: Appearance.colors.colWellHairline
    }
    LitBar {
        shown: root.lit
        color: root.accent
    }

    releaseAction: () => {
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry, root.menuEntry.text);
            return;
        }
        menuEntry.triggered();
        if (!root.isCheck && !root.isRadio) root.dismiss(); // A switch or choice stays open to see it change
    }
    altAction: (event) => { // Not hog right-click
        event.accepted = false;
    }
    contentItem: RowLayout {
        id: contentItem
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: 14
            rightMargin: 10
        }
        spacing: 10
        visible: !root.menuEntry.isSeparator
        Item { // The entry's own icon, when the app sends one (a column for all when any has one)
            visible: root.hasIcon || root.forceIconColumn
            implicitWidth: 18
            implicitHeight: 18
            Loader {
                anchors.centerIn: parent
                active: root.hasIcon
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.menuEntry.icon
                    implicitSize: 18
                    mipmap: true
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.menuEntry.text
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: root.danger || root.lit ? root.accent : Appearance.colors.colOnLayer3
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Loader { // On / off: a switch; one of a few choices: a radio button (made only for those rows)
            active: root.isCheck || root.isRadio
            visible: active
            sourceComponent: root.isCheck ? switchComponent : radioComponent
        }
        MaterialSymbol { // A submenu, or (on the row you're on) where a click goes
            visible: root.menuEntry.hasChildren || (root.lit && !root.isCheck && !root.isRadio)
            text: root.menuEntry.hasChildren ? "chevron_right" : "arrow_forward"
            iconSize: 17
            color: root.lit ? root.accent : Appearance.colors.colSubtext
        }
    }
    Component {
        id: switchComponent
        StyledSwitch {
            enabled: false // The row toggles it
            checked: root.menuEntry.checkState === Qt.Checked
        }
    }
    Component {
        id: radioComponent
        StyledRadioButton {
            enabled: false
            padding: 0
            checked: root.menuEntry.checkState === Qt.Checked
        }
    }
}
