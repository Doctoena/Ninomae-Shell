import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
// The search field: the top piece of the drawer's joined group (search, shell buttons, results)
Rectangle {
    id: root
    property alias searchInput: searchInput
    property string searchingText
    function forceFocus() {
        searchInput.forceActiveFocus();
    }
    enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, DefaultSearch }
    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app)) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }

    property int resultCount: 0
    implicitHeight: 42
    topLeftRadius: Appearance.rounding.normal
    topRightRadius: Appearance.rounding.normal
    bottomLeftRadius: Appearance.rounding.joined
    bottomRightRadius: Appearance.rounding.joined
    color: Appearance.colors.colLayer3

    MaterialSymbol {
        id: searchIcon
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colPrimary
        animateChange: true
        text: switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return "settings_suggest";
            case SearchBar.SearchPrefixType.App: return "apps";
            case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
            case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
            case SearchBar.SearchPrefixType.Math: return "calculate";
            case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
            case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
            default: return "search";
        }
    }

    ToolbarTextField { // Search box
        id: searchInput
        anchors {
            left: searchIcon.right
            right: trailing.visible ? trailing.left : parent.right
            leftMargin: 8
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        implicitHeight: root.height
        padding: 4
        colBackground: "transparent"
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: Translation.tr("Search apps and settings")
        onTextChanged: root.searchingText = text
        onAccepted: {
            if (appResults.count > 0) {
                let item = appResults.itemAtIndex(Math.max(0, appResults.currentIndex));
                if (item && item.clicked) {
                    item.clicked();
                }
            }
        }
        // Alt+1–9 runs the chosen result's actions, Tab moves into them, Shift+Delete removes a clipboard entry
        Keys.onPressed: event => {
            const item = appResults.currentItem;
            if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                if (item?.runAction(event.key - Qt.Key_1)) event.accepted = true;
            } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier) && item?.isClipboard) {
                item.entry.actions.find(action => action.name === "Delete")?.execute();
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                item?.focusActions();
                event.accepted = true; // Never on to the list's rows
            }
        }
        // Arrows move through the results without leaving the field
        Keys.onDownPressed: event => {
            appResults.incrementCurrentIndex();
            event.accepted = true;
        }
        Keys.onUpPressed: event => {
            appResults.decrementCurrentIndex();
            event.accepted = true;
        }
    }

    Row { // How many results, and clear: only while there's text
        id: trailing
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 12
        visible: searchInput.text.length > 0
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.resultCount === 1 ? Translation.tr("1 result") : Translation.tr("%1 results").arg(root.resultCount)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        MaterialSymbol { // Clear
            anchors.verticalCenter: parent.verticalCenter
            text: "close"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    searchInput.text = "";
                    searchInput.forceActiveFocus();
                }
            }
        }
    }
}
