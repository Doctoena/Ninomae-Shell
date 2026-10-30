pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
RippleButton {
    id: root
    required property QsMenuEntry menuEntry
    property bool forceIconColumn: false
    property bool forceSpecialInteractionColumn: false
    readonly property bool hasIcon: menuEntry.icon.length > 0
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None
    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)
    // "Quit"/"Exit" entries are shown in red
    readonly property bool danger: /^(quit|exit)\b/i.test(menuEntry.text ?? "")
    readonly property color textColor: danger ? Appearance.colors.colError : Appearance.colors.colOnLayer0
    colBackground: menuEntry.isSeparator ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
    colBackgroundHover: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.88) : Appearance.m3colors.m3surfaceContainerHigh
    colRipple: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.75) : Appearance.m3colors.m3surfaceContainerHighest
    enabled: !menuEntry.isSeparator
    opacity: menuEntry.enabled !== false ? 1 : 0.45
    buttonRadius: menuEntry.isSeparator ? 0 : height / 2 // Pill rows
    horizontalPadding: 14
    implicitWidth: Math.max(200, contentItem.implicitWidth + horizontalPadding * 2)
    implicitHeight: menuEntry.isSeparator ? 1 : 38
    Layout.topMargin: menuEntry.isSeparator ? 4 : 0
    Layout.bottomMargin: menuEntry.isSeparator ? 4 : 0
    Layout.leftMargin: menuEntry.isSeparator ? 12 : 0
    Layout.rightMargin: menuEntry.isSeparator ? 12 : 0
    Layout.fillWidth: true
    Component.onCompleted: {
        if (menuEntry.isSeparator) {
            root.buttonColor = root.colBackground;
        }
    }
    releaseAction: () => {
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry);
            return;
        }
        menuEntry.triggered();
        root.dismiss();
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
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 8
        visible: !root.menuEntry.isSeparator
        // Interaction: checkbox or radio button
        Item {
            visible: root.hasSpecialInteraction || root.forceSpecialInteractionColumn
            implicitWidth: 20
            implicitHeight: 20
            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.RadioButton
                sourceComponent: StyledRadioButton {
                    enabled: false
                    padding: 0
                    checked: root.menuEntry.checkState === Qt.Checked
                }
            }
            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox && root.menuEntry.checkState !== Qt.Unchecked
                sourceComponent: MaterialSymbol {
                    text: root.menuEntry.checkState === Qt.PartiallyChecked ? "check_indeterminate_small" : "check"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }
            }
        }
        // Button icon
        Item {
            visible: root.hasIcon || root.forceIconColumn
            implicitWidth: 20
            implicitHeight: 20
            Loader {
                anchors.centerIn: parent
                active: root.menuEntry.icon.length > 0
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.menuEntry.icon
                    implicitSize: 20
                    mipmap: true
                }
            }
        }
        StyledText {
            id: label
            text: root.menuEntry.text
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.textColor
            Layout.fillWidth: true
        }
        Loader {
            active: root.menuEntry.hasChildren
            sourceComponent: MaterialSymbol {
                text: "chevron_right"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
    }
}
