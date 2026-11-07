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
 * A window's page list (Settings, the control centre): you at the top (your picture or initial, your name, the
 * system; or `title`, `subtitle` and a `badgeIcon` instead), the pages in their groups with a hairline between
 * groups, `extras` and Collapse at the bottom. The open page: its icon on an accent squircle and its name in
 * accent, on a neutral row. Collapse (icons only) is kept for next time in `stateFile`; `narrow` shows icons only
 * too, without changing it.
 *   pages: [{ name, icon, iconRotation?, group? }]
 */
Rectangle {
    id: nav
    required property var pages
    required property int currentPage
    required property string stateFile
    property bool narrow: false
    property real expandedWidth: 236
    property string title: SystemInfo.username
    property string subtitle: SystemInfo.distroName.replace(/\s*\(.*\)$/, "") // "Fedora Linux 44", not the edition
    property string badgeIcon: "" // Shown in the circle instead of your picture
    default property alias extras: extraColumn.data
    readonly property bool collapsed: navState.value.navCollapsed ?? false
    readonly property bool expanded: !collapsed && !narrow
    signal pageChosen(int index)
    color: Appearance.m3colors.m3surfaceContainerLow
    radius: Appearance.rounding.windowRounding
    Layout.fillHeight: true
    Layout.fillWidth: false
    Layout.preferredWidth: expanded ? expandedWidth : 64
    Behavior on Layout.preferredWidth {
        enabled: navState.ready
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    JsonStore {
        id: navState
        property bool ready: false // Until then the list is at its default: it snaps to the saved state, no slide
        filePath: nav.stateFile
        onLoaded: ready = true
    }

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
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: nav.badgeIcon !== ""
                    text: nav.badgeIcon
                    iconSize: 22
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: nav.badgeIcon === "" && face.status !== Image.Ready
                    text: SystemInfo.username.charAt(0).toUpperCase()
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
                FileView { // ~/.face, only when there is one; a new picture shows right away
                    id: faceFile
                    path: nav.badgeIcon === "" ? `${FileUtils.trimFileProtocol(Directories.home)}/.face` : ""
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
                    visible: nav.badgeIcon === ""
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
                    enabled: nav.badgeIcon === ""
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
                    text: nav.title
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: nav.subtitle
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
                NavRow {
                    Layout.fillWidth: true
                    expanded: nav.expanded
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
        ColumnLayout {
            id: extraColumn
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: 2
        }
        NavRow {
            Layout.fillWidth: true
            expanded: nav.expanded
            symbol: nav.expanded ? "left_panel_close" : "left_panel_open"
            text: nav.expanded ? Translation.tr("Collapse") : Translation.tr("Expand")
            onClicked: navState.commit(Object.assign({}, navState.value, { navCollapsed: !nav.collapsed }))
        }
    }

    // Beside what it's for, centred on it: above, the window's edge would push it off centre
    component SideToolTip: StyledToolTip {
        x: parent.width + 8
        y: (parent.height - height) / 2
    }
}
