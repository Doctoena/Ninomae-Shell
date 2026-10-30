import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
// A settings section: a solid card with its icon in a neutral squircle (accent is only for what's
// active, as in the rest of the shell) and a title
Rectangle {
    id: root
    property string title
    property string icon: ""
    // An option to switch the whole card on and off from its title ("crosshair.dot"); hide the rest with it
    property string toggleOption: ""
    readonly property bool toggledOn: toggleOption === "" || !!Config.get(toggleOption)
    property alias spacing: sectionContent.spacing
    default property alias contentData: sectionContent.data
    readonly property real padding: 16
    Layout.fillWidth: true
    implicitWidth: cardColumn.implicitWidth + padding * 2
    implicitHeight: cardColumn.implicitHeight + padding * 2
    color: Appearance.m3colors.m3surfaceContainer
    radius: Appearance.rounding.large
    ColumnLayout {
        id: cardColumn
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: root.padding
        }
        spacing: 12
        RowLayout {
            visible: root.title.length > 0
            spacing: 10
            Rectangle {
                visible: root.icon.length > 0
                implicitWidth: 32
                implicitHeight: 32
                radius: 11
                color: Appearance.m3colors.m3surfaceContainerHighest
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledSwitch {
                visible: root.toggleOption !== ""
                Layout.rightMargin: 4
                sizeScale: 0.6
                checked: root.toggledOn
                onClicked: Config.set(root.toggleOption, checked)
            }
        }
        ColumnLayout {
            id: sectionContent
            visible: root.toggledOn // Switched off from the title: just the title row
            Layout.fillWidth: true
            spacing: 4
        }
    }
}
