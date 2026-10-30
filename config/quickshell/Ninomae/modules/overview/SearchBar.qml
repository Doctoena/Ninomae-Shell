import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
// Pill search field in the style of caelestia-dots/shell's launcher
Rectangle {
    id: root
    property bool animateWidth: false // Kept for Overview.qml's API; the drawer is fixed-width
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

    implicitHeight: 50
    radius: 14 // Rounded rectangle, like the rest of the shell
    color: Appearance.colors.colLayer1

    MaterialSymbol {
        id: searchIcon
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        iconSize: Appearance.font.pixelSize.huge
        color: Appearance.colors.colOnSurfaceVariant
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
            right: clearButton.left
            leftMargin: 8
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        implicitHeight: root.height
        padding: 4
        colBackground: "transparent"
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: Translation.tr("Type \"%1\" for actions").arg(Config.options.search.prefix.action)
        onTextChanged: root.searchingText = text
        onAccepted: {
            if (appResults.count > 0) {
                let item = appResults.itemAtIndex(Math.max(0, appResults.currentIndex));
                if (item && item.clicked) {
                    item.clicked();
                }
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

    MaterialSymbol { // Clear
        id: clearButton
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        text: "close"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSurfaceVariant
        visible: searchInput.text.length > 0
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
