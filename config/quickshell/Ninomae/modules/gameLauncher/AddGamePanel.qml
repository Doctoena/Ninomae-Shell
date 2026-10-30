import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

/**
 * Add a game: any installed app (a Flatpak, an AppImage with a desktop entry, an emulator) into the
 * library, as Steam's "Add a non-Steam game" does. A panel growing up out of the launcher
 * (LauncherTopPanel), like the details page's Captures and News, from the search bar's Add button.
 * The apps' desktop entries in a grid, games first, searched from the header; Steam and Lutris, and their
 * game shortcuts, are left out (those games are in already). Picking one adds it
 * (GameLauncherService.addCustomGame), with art from SteamGridDB when there's a key; the panel stays
 * open to add more. ↑/↓/←/→ move, Enter adds, Esc closes.
 */
LauncherTopPanel {
    id: root
    panelWidth: 1100
    panelHeight: 480
    clipContent: true
    onShownChanged: if (shown) { search.text = ""; grid.currentIndex = 0; search.forceActiveFocus(); }

    // Apps that can be added: shown, with a command, and not Steam, Lutris or a shortcut into them
    readonly property var apps: {
        const added = new Set(GameLauncherService.customGames.map(g => g.name));
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || !e.command || e.command.length === 0) continue;
            const exec = e.command.join(" ");
            if (/steam:\/\/rungameid|lutris:rungame|^steam( |$)|\/steam( |$)/.test(exec)) continue;
            if (/^(net\.lutris\.Lutris|lutris|steam)(\.desktop)?$/.test(e.id)) continue;
            out.push({ entry: e, name: e.name, isGame: (e.categories ?? []).includes("Game"), added: added.has(e.name),
                       flatpak: /(^|\/)flatpak run/.test(exec) });
        }
        return out.sort((a, b) => (b.isGame - a.isGame) || a.name.localeCompare(b.name));
    }
    readonly property var matches: { // The apps the search matches
        const q = search.text.trim().toLowerCase();
        return q === "" ? apps : apps.filter(a => a.name.toLowerCase().includes(q));
    }
    function pick(app) {
        if (!app || app.added) return;
        GameLauncherService.addCustomGame({ id: app.entry.id, name: app.entry.name, command: Array.from(app.entry.command),
                                            icon: app.entry.icon, workingDirectory: app.entry.workingDirectory });
    }

    SheetHeader {
        id: header
        icon: "library_add"
        title: Translation.tr("Add a game")
        subtitle: Translation.tr("Any app: a Flatpak, an AppImage, an emulator")
        onCloseRequested: root.closeRequested()
        Rectangle { // Search
            width: 300; height: 32
            radius: Appearance.rounding.segment
            color: search.activeFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: 140 } }
            MaterialSymbol {
                id: searchIcon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "search"; iconSize: 17
                color: search.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            }
            ToolbarTextField {
                id: search
                anchors { left: searchIcon.right; leftMargin: 6; right: parent.right; rightMargin: 8; top: parent.top; bottom: parent.bottom }
                padding: 0
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                colBackground: "transparent"
                placeholderText: Translation.tr("Search apps...")
                onTextChanged: grid.currentIndex = 0
                Keys.onPressed: event => {
                    const step = { [Qt.Key_Right]: 1, [Qt.Key_Left]: -1, [Qt.Key_Down]: grid.columns, [Qt.Key_Up]: -grid.columns }[event.key];
                    if (step !== undefined) {
                        grid.currentIndex = Math.max(0, Math.min(grid.count - 1, grid.currentIndex + step));
                        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.pick(root.matches[grid.currentIndex]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.closeRequested();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    GridView {
        id: grid
        anchors { top: header.bottom; topMargin: 12; bottom: parent.bottom; bottomMargin: 12; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16 }
        readonly property int columns: Math.max(1, Math.floor(width / 300))
        cellWidth: Math.floor(width / columns)
        cellHeight: 56
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.matches
        currentIndex: 0
        highlightMoveDuration: 0
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            Rectangle {
                id: row
                anchors { fill: parent; margins: 3 }
                radius: Appearance.rounding.normal
                readonly property bool lit: rowArea.containsMouse || grid.currentIndex === cell.index
                color: lit && !cell.modelData.added ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                opacity: cell.modelData.added ? 0.6 : 1
                Behavior on color { ColorAnimation { duration: 100 } }
                IconImage {
                    id: appIcon
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    implicitSize: 30
                    source: Quickshell.iconPath(cell.modelData.entry.icon ?? "", "application-x-executable")
                }
                Column {
                    anchors { left: appIcon.right; leftMargin: 10; right: trailing.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    StyledText {
                        width: parent.width
                        text: cell.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        width: parent.width
                        visible: text !== ""
                        text: cell.modelData.added ? Translation.tr("In your library")
                            : [cell.modelData.isGame ? Translation.tr("Game") : "", cell.modelData.flatpak ? "Flatpak" : ""].filter(t => t).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                MaterialSymbol {
                    id: trailing
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: cell.modelData.added ? "check" : "add"
                    iconSize: 18
                    opacity: cell.modelData.added || row.lit ? 1 : 0
                    color: cell.modelData.added ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !cell.modelData.added
                    cursorShape: Qt.PointingHandCursor
                    onEntered: grid.currentIndex = cell.index
                    onClicked: root.pick(cell.modelData)
                }
            }
        }
    }
    SheetEdgeFade {
        anchors { left: grid.left; right: grid.right; bottom: grid.bottom }
        height: 24; reversed: true
        sheetColor: root.backgroundColor
        active: !grid.atYEnd
    }
    SheetEmptyState {
        anchors.centerIn: grid
        visible: root.matches.length === 0
        icon: "search_off"
        text: Translation.tr("No apps match")
        hint: ""
    }
}
