pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Settings' page list: you at the top (your picture or initial, your name, the system), the pages in their groups
 * with a hairline between groups, and Collapse at the bottom (icons only). The open page: its icon on an accent
 * squircle and its name in accent, on a neutral row
 */
Rectangle {
    id: nav
    required property var pages
    required property int currentPage
    property bool expanded: true
    signal pageChosen(int index)
    signal collapseToggled()
    color: Appearance.m3colors.m3surfaceContainerLow
    radius: Appearance.rounding.windowRounding

    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 2

        RowLayout { // You
            Layout.fillWidth: true
            Layout.leftMargin: nav.expanded ? 4 : 0
            Layout.alignment: nav.expanded ? Qt.AlignLeft : Qt.AlignHCenter
            Layout.topMargin: 4
            Layout.bottomMargin: 14
            spacing: 12
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: 22
                color: Appearance.colors.colSecondaryContainer
                border.width: 2
                border.color: Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    visible: face.status !== Image.Ready
                    text: SystemInfo.username.charAt(0).toUpperCase()
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
                FileView { // ~/.face, only when there is one; a new picture shows right away
                    id: faceFile
                    path: `${FileUtils.trimFileProtocol(Directories.home)}/.face`
                    printErrors: false
                    watchChanges: true
                    onFileChanged: reload()
                    onLoaded: { face.source = ""; face.source = `file://${path}`; }
                }
                StyledImage {
                    id: face
                    anchors.centerIn: parent
                    width: 38
                    height: 38
                    cache: false // The same path with a new picture in it
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(88, 88)
                    visible: status === Image.Ready
                    layer.enabled: visible
                    layer.effect: RoundedMask { maskWidth: 38; maskHeight: 38; radius: 19 }
                }
                Rectangle { // Pointed at: a pencil, a click picks a new picture
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.rgba(0, 0, 0, 0.45)
                    opacity: faceArea.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "edit"
                        iconSize: 18
                        color: "white"
                    }
                }
                MouseArea {
                    id: faceArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/set-avatar.sh")])
                }
                SideToolTip {
                    text: Translation.tr("Change your picture")
                    visible: faceArea.containsMouse
                }
            }
            ColumnLayout {
                visible: nav.expanded
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: SystemInfo.username
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: SystemInfo.distroName.replace(/\s*\(.*\)$/, "") // "Fedora Linux 44", not the edition
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        Repeater {
            model: nav.pages
            delegate: ColumnLayout {
                id: entry
                required property int index
                required property var modelData
                readonly property bool startsGroup: index > 0 && nav.pages[index - 1].group !== modelData.group
                Layout.fillWidth: true
                spacing: 2
                Hairline { // Between groups
                    visible: entry.startsGroup
                    Layout.topMargin: 6
                }
                NavButton {
                    symbol: entry.modelData.icon
                    symbolRotation: entry.modelData.iconRotation || 0
                    text: entry.modelData.name
                    toggled: nav.currentPage === entry.index
                    onClicked: nav.pageChosen(entry.index)
                }
            }
        }
        Item { Layout.fillHeight: true }
        Hairline {}
        NavButton {
            symbol: nav.expanded ? "left_panel_close" : "left_panel_open"
            text: nav.expanded ? Translation.tr("Collapse") : Translation.tr("Expand")
            onClicked: nav.collapseToggled()
        }
    }

    // Beside what it's for, centred on it: above, the window's edge would push it off centre
    component SideToolTip: StyledToolTip {
        x: parent.width + 8
        y: (parent.height - height) / 2
    }
    component Hairline: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.bottomMargin: 6
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }
    component NavButton: RippleButton {
        id: button
        property string symbol
        property real symbolRotation: 0
        Layout.fillWidth: true
        implicitHeight: 44
        buttonRadius: Appearance.rounding.normal
        colBackground: "transparent"
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundToggled: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundToggledHover: Appearance.m3colors.m3surfaceContainerHighest
        colRippleToggled: Appearance.m3colors.m3surfaceContainerHighest
        SideToolTip { // Icons only: the name on hover
            text: button.text
            visible: !nav.expanded && button.hovered
        }
        leftPadding: 0
        rightPadding: 0
        contentItem: Item { // Placed by hand: collapsed, the squircle sits exactly in the middle of the row
            implicitHeight: 30
            Rectangle {
                id: squircle
                x: nav.expanded ? 6 : Math.round((parent.width - width) / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: Appearance.rounding.segment
                color: button.toggled ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary) // Not black: no dark flash
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: button.symbol
                    rotation: button.symbolRotation
                    iconSize: Appearance.font.pixelSize.larger
                    fill: button.toggled ? 1 : 0
                    color: button.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }
            }
            StyledText {
                visible: nav.expanded
                anchors { left: squircle.right; leftMargin: 12; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: button.text
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: button.toggled ? Font.DemiBold : Font.Medium
                color: button.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
        }
    }
}
