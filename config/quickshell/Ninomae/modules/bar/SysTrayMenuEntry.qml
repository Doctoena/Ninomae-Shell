pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

/**
 * One row of a tray icon's menu, a piece of its section's joined group (sections are the app's own separators,
 * shown as gaps). Compact: 34 px. The row you're on takes a light accent tint, its name the accent and an arrow;
 * a submenu has a ›. On/off entries are switches, choices radio buttons, on the right. "Quit" / "Exit" are red.
 * Entries the app greys out stay dim. A separator is just the gap between two sections.
 */
RippleButton {
    id: root
    required property QsMenuEntry menuEntry
    property bool forceIconColumn: false
    property bool firstInSection: true
    property bool lastInSection: true
    property bool lastInMenu: false // Rounds the menu's bottom corners
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
    implicitHeight: menuEntry.isSeparator ? 2 : 34 // A separator: the gap between sections (with the column's spacing)
    Layout.fillWidth: true

    buttonRadius: Appearance.rounding.small
    buttonRadiusTopLeft: firstInSection ? Appearance.rounding.small : 4
    buttonRadiusTopRight: buttonRadiusTopLeft
    buttonRadiusBottomLeft: lastInMenu ? Appearance.rounding.normal : lastInSection ? Appearance.rounding.small : 4
    buttonRadiusBottomRight: buttonRadiusBottomLeft
    colBackground: menuEntry.isSeparator ? "transparent"
        : danger ? ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colError, 0.9) : Appearance.colors.colLayer3
    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer3, accent, 0.84)
    colRipple: ColorUtils.mix(Appearance.colors.colLayer3, accent, 0.72)

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
