// pragma NativeMethodBehavior: AcceptThisObject
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
RippleButton {
    id: root
    property var entry
    property string query
    property bool entryShown: entry?.shown ?? true
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property string itemIcon: entry?.icon ?? ""
    function actionSymbol(name) { // A symbol for a desktop action, from its name
        const n = (name ?? "").toLowerCase();
        if (n.includes("private") || n.includes("incognito")) return "visibility_off";
        if (n.includes("window")) return "open_in_new";
        if (n.includes("new")) return "add";
        if (n.includes("setting") || n.includes("preference")) return "settings";
        if (n.includes("quit") || n.includes("exit")) return "close";
        if (n.includes("play") || n.includes("pause")) return "play_pause";
        return "bolt";
    }
    property string fontType: entry?.fontType ?? "main"
    property string itemClickActionName: entry?.clickActionName ?? "Open"
    property string bigText: entry?.bigText ?? ""
    property string materialSymbol: entry?.materialSymbol ?? ""
    property string cliphistRawString: entry?.cliphistRawString ?? ""
    visible: root.entryShown
    // Apps carry a DesktopEntry: show its comment / generic name under the title
    property string itemSubtitle: entry?.comment || entry?.genericName || ""
    property real minHeight: 0
    property int horizontalMargin: 0
    property int buttonHorizontalPadding: 12
    property int buttonVerticalPadding: 6
    property bool keyboardDown: false
    implicitHeight: Math.max(root.minHeight, rowLayout.implicitHeight + root.buttonVerticalPadding * 2)
    implicitWidth: rowLayout.implicitWidth + root.buttonHorizontalPadding * 2
    buttonRadius: 16
    // Selection is drawn by the list's sliding highlight; rows only get a faint hover
    colBackground: "transparent"
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.95)
    colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
    property string highlightPrefix: `<font color="${Appearance.colors.colPrimary}">`
    property string highlightSuffix: `</font>`
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content == query || fontType === "monospace")
            return StringUtils.escapeHtml(content);
        let contentLower = content.toLowerCase();
        let queryLower = query.toLowerCase();
        let result = "";
        let lastIndex = 0;
        let qIndex = 0;
        for (let i = 0; i < content.length && qIndex < query.length; i++) {
            if (contentLower[i] === queryLower[qIndex]) {
                // Add non-highlighted part (escaped)
                if (i > lastIndex)
                    result += StringUtils.escapeHtml(content.slice(lastIndex, i));
                // Add highlighted character (escaped)
                result += root.highlightPrefix + StringUtils.escapeHtml(content[i]) + root.highlightSuffix;
                lastIndex = i + 1;
                qIndex++;
            }
        }
        // Add the rest of the string (escaped)
        if (lastIndex < content.length)
            result += StringUtils.escapeHtml(content.slice(lastIndex));
        return result;
    }
    property string displayContent: highlightContent(root.itemName, root.query)
    readonly property var _urlRegex: /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi
    property list<string> urls: {
        if (!root.itemName) return [];
        root._urlRegex.lastIndex = 0;
        const matches = root.itemName?.match(root._urlRegex)
            ?.filter(url => !url.includes("…")) // Elided = invalid
        return matches ? matches : [];
    }
    PointingHandInteraction {}
    background {
        anchors.fill: root
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
    }
    onClicked: {
        GlobalStates.overviewOpen = false
        if (root.entry?.type === Translation.tr("App")) AppSearch.recordLaunch(root.entry); // Most used come first
        root.entry?.execute?.() // Call on entry so C++ methods (DesktopEntry.execute) keep their `this`
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
            const deleteAction = root.entry?.actions?.find(action => action.name == "Delete");
            if (deleteAction) {
                deleteAction.execute()
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = true
            root.clicked()
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false
            event.accepted = true;
        }
    }
    RowLayout {
        id: rowLayout
        spacing: iconLoader.sourceComponent === null ? 0 : 14
        anchors.fill: parent
        anchors.leftMargin: root.horizontalMargin + root.buttonHorizontalPadding
        anchors.rightMargin: root.horizontalMargin + root.buttonHorizontalPadding
        // Icon
        Loader {
            id: iconLoader
            active: true
            sourceComponent: root.materialSymbol !== "" ? materialSymbolComponent :
                root.bigText ? bigTextComponent :
                root.itemIcon !== "" ? iconImageComponent :
                null
        }
        Component {
            id: iconImageComponent
            IconImage {
                source: Quickshell.iconPath(root.itemIcon, "image-missing")
                implicitSize: 32
            }
        }
        Component {
            id: materialSymbolComponent
            MaterialSymbol {
                text: root.materialSymbol
                iconSize: 24
                color: Appearance.colors.colOnSurface
            }
        }
        Component {
            id: bigTextComponent
            StyledText {
                text: root.bigText
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurface
            }
        }
        // Main text
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                visible: root.itemType && root.itemType != Translation.tr("App")
                text: root.itemType
            }
            RowLayout {
                Loader { // Checkmark for copied clipboard entry
                    visible: itemName == Quickshell.clipboardText && root.cliphistRawString
                    active: itemName == Quickshell.clipboardText && root.cliphistRawString
                    sourceComponent: Rectangle {
                        implicitWidth: activeText.implicitHeight
                        implicitHeight: activeText.implicitHeight
                        radius: 6
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            id: activeText
                            anchors.centerIn: parent
                            text: "check"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
                Repeater { // Favicons for links
                    model: root.query == root.itemName ? [] : root.urls
                    Favicon {
                        required property var modelData
                        size: parent.height
                        url: modelData
                    }
                }
                StyledText { // Item name/content
                    Layout.fillWidth: true
                    id: nameText
                    textFormat: Text.StyledText // RichText also works, but StyledText ensures elide work
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family[root.fontType]
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    text: `${root.displayContent}`
                }
            }
            Loader { // Clipboard image preview
                active: root.cliphistRawString && Cliphist.entryIsImage(root.cliphistRawString)
                sourceComponent: CliphistImage {
                    Layout.fillWidth: true
                    entry: root.cliphistRawString
                    maxWidth: contentColumn.width
                    maxHeight: 140
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: root.buttonVerticalPadding
            Layout.bottomMargin: -root.buttonVerticalPadding // Why is this necessary? Good question.
            spacing: 4
            Repeater {
                model: (root.entry?.actions ?? []).slice(0, 4)
                delegate: RippleButton {
                    id: actionButton
                    required property var modelData
                    // An app's own desktop actions often reuse its logo, which reads as a stray second logo with
                    // no hint of what it does: those get a symbol for the action instead (name in the tooltip)
                    readonly property bool reusesAppIcon: (modelData.icon ?? "") !== "" && modelData.icon === root.itemIcon
                    readonly property string iconName: reusesAppIcon ? "" : (modelData.icon ?? "")
                    readonly property string materialIconName: modelData.materialIcon ?? (reusesAppIcon ? root.actionSymbol(modelData.name) : "")
                    // A symbol when there is one, or no image to show; otherwise the action's own image
                    readonly property bool useSymbol: materialIconName !== "" || iconName === ""
                    implicitHeight: 34
                    implicitWidth: 34
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    contentItem: Item {
                        id: actionContentItem
                        anchors.centerIn: parent
                        Loader {
                            anchors.centerIn: parent
                            active: actionButton.useSymbol
                            sourceComponent: MaterialSymbol {
                                text: actionButton.materialIconName || "video_settings"
                                iconSize: 20 // Same size as the image icons
                                color: Appearance.colors.colSubtext
                            }
                        }
                        Loader {
                            anchors.centerIn: parent
                            active: !actionButton.useSymbol
                            sourceComponent: IconImage {
                                source: Quickshell.iconPath(actionButton.iconName)
                                implicitSize: 20
                            }
                        }
                    }
                    onClicked: modelData.execute()
                    StyledToolTip {
                        text: modelData.name
                    }
                }
            }
        }
    }
}
