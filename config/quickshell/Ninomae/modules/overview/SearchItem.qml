// pragma NativeMethodBehavior: AcceptThisObject
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets

/**
 * One search result, a piece of the drawer's joined group. A plain line (icon, name, description); the chosen
 * one grows into a card tinted by its icon's colour, with a halo, a big name, its main button and "⋯", which
 * lists the result's own actions (Alt+1–9 runs them, Tab goes into the list). The card is only built while
 * it's shown: every other row is just the line.
 */
RippleButton {
    id: root
    property var entry
    property string query
    property bool grown: false // The chosen result
    property bool lastInGroup: false // Rounds the drawer's bottom corners
    property IconGlow glow // Remembers each icon's colour
    // Its own icon's colour (the accent for symbols, emoji and the shell's entries), asked for as the row is built
    readonly property string glowIcon: shellSymbol === "" && materialSymbol === "" && bigText === "" ? itemIcon : ""
    onGlowIconChanged: glow?.request(glowIcon)
    Component.onCompleted: glow?.request(glowIcon)
    property color tint: glow ? glow.colourFor(glowIcon) : Appearance.colors.colPrimary
    Behavior on tint { ColorAnimation { duration: 300 } } // Only if it arrives late: then it fades in
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property string itemIcon: entry?.icon ?? ""
    property string fontType: entry?.fontType ?? "main"
    property string itemClickActionName: entry?.clickActionName ?? "Open"
    property string bigText: entry?.bigText ?? ""
    property string materialSymbol: entry?.materialSymbol ?? ""
    property string shellSymbol: entry?.shellSymbol ?? "" // The shell's own entries (ShellAppIcon)
    property string cliphistRawString: entry?.cliphistRawString ?? ""
    readonly property bool isClipboard: cliphistRawString !== "" && bigText === "" // Emoji also carry the raw line
    readonly property bool isClipboardImage: isClipboard && Cliphist.entryIsImage(cliphistRawString)
    // Apps and the shell's entries have a description; other kinds say what they are
    readonly property string itemSubtitle: entry?.comment || entry?.genericName || (itemType !== Translation.tr("App") ? itemType : "")
    readonly property var itemActions: entry?.actions ?? []
    property bool showAllActions: false // "⋯" pressed: the actions are listed
    onGrownChanged: if (!grown) showAllActions = false
    signal backRequested() // Leaving the action buttons: focus goes back to the search field

    readonly property real rowHeight: 50
    implicitHeight: grown ? (card.item?.bodyHeight ?? 0) + 28 : rowHeight
    Behavior on implicitHeight { // A soft spring as it grows
        enabled: GlobalStates.overviewOpen
        NumberAnimation { duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
    }
    clip: true // Its grown contents stay inside while it grows and shrinks
    // Arriving: the drawer's opening cascade
    property real enter: 1
    opacity: enter
    transform: Translate { y: (1 - root.enter) * 14 }
    // The grown contents rise and fade in after the card starts growing, and leave quickly
    property real reveal: grown ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.grown ? 300 : 90
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.grown ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
        }
    }
    buttonRadius: Appearance.rounding.joined
    buttonRadiusTop: Appearance.rounding.joined
    buttonRadiusBottom: lastInGroup ? Appearance.rounding.normal : Appearance.rounding.joined
    colBackground: grown ? ColorUtils.mix(Appearance.colors.colLayer3, tint, 0.8) : Appearance.colors.colLayer3
    colBackgroundHover: grown ? colBackground : Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    PointingHandInteraction {}

    // The name with the matched letters in the accent
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content == query || fontType === "monospace")
            return StringUtils.escapeHtml(content);
        const contentLower = content.toLowerCase();
        const queryLower = query.toLowerCase();
        let result = "", lastIndex = 0, qIndex = 0;
        for (let i = 0; i < content.length && qIndex < query.length; i++) {
            if (contentLower[i] === queryLower[qIndex]) {
                if (i > lastIndex) result += StringUtils.escapeHtml(content.slice(lastIndex, i));
                result += `<font color="${Appearance.colors.colPrimary}"><b>${StringUtils.escapeHtml(content[i])}</b></font>`;
                lastIndex = i + 1;
                qIndex++;
            }
        }
        if (lastIndex < content.length) result += StringUtils.escapeHtml(content.slice(lastIndex));
        return result;
    }
    readonly property string displayContent: highlightContent(root.itemName, root.query)
    readonly property var _urlRegex: /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi
    readonly property list<string> urls: {
        if (!root.itemName) return [];
        root._urlRegex.lastIndex = 0;
        const matches = root.itemName.match(root._urlRegex)?.filter(url => !url.includes("…")); // Elided = invalid
        return matches ? matches : [];
    }

    onClicked: {
        GlobalStates.overviewOpen = false;
        if (root.entry?.type === Translation.tr("App")) AppSearch.recordLaunch(root.entry); // Most used come first
        root.entry?.execute?.(); // Called on entry so C++ methods (DesktopEntry.execute) keep their `this`
    }
    function runAction(i) {
        const action = root.itemActions[i];
        if (!action) return false;
        GlobalStates.overviewOpen = false;
        action.execute(); // On the action, for the same reason
        return true;
    }
    function focusActions() { // Tab: opens the list and goes to its first row
        if (!root.grown || root.itemActions.length === 0) return false;
        root.showAllActions = true;
        Qt.callLater(() => card.item?.listRepeater.itemAt(0)?.forceActiveFocus());
        return true;
    }
    // The action buttons in keyboard order: "⋯", then the listed ones
    function focusOrder() {
        const c = card.item;
        if (!c) return [];
        const order = [c.moreButton];
        for (let i = 0; i < c.listRepeater.count; i++) order.push(c.listRepeater.itemAt(i));
        return order.filter(Boolean);
    }
    // Arrows walk them, Enter runs one, Tab/Esc (or going past the first) back to the search
    function actionKey(button, event) {
        const order = focusOrder();
        const i = order.indexOf(button);
        const forward = event.key === Qt.Key_Right || event.key === Qt.Key_Down;
        const backward = event.key === Qt.Key_Left || event.key === Qt.Key_Up;
        if (forward && order[i + 1]) order[i + 1].forceActiveFocus();
        else if (backward && i > 0) order[i - 1].forceActiveFocus();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) button.clicked();
        else if (forward || backward || [Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Up, Qt.Key_Down, Qt.Key_Escape].includes(event.key)) root.backRequested();
        else return;
        event.accepted = true;
    }

    // A symbol for an action, from its name (apps often reuse their own logo for every action)
    function actionSymbol(name) {
        const n = (name ?? "").toLowerCase();
        if (n.includes("private") || n.includes("incognito")) return "visibility_off";
        if (n.includes("window")) return "open_in_new";
        if (n.includes("new")) return "add";
        if (n.includes("setting") || n.includes("preference")) return "settings";
        if (n.includes("quit") || n.includes("exit")) return "close";
        if (n.includes("play") || n.includes("pause")) return "play_pause";
        if (n.includes("store")) return "storefront";
        if (n.includes("library")) return "sports_esports";
        if (n.includes("community") || n.includes("friends")) return "groups";
        if (n.includes("screenshot")) return "photo_library";
        if (n.includes("profile")) return "manage_accounts";
        return "bolt";
    }

    // One of the chosen result's actions: a row in the "⋯" list
    component ActionButton: RippleButton {
        id: actionButton
        property int actionIndex: 0
        property var act: root.itemActions[actionIndex]
        property int delay: 0
        // An app's actions often reuse its logo, which says nothing about what they do: a symbol then
        readonly property bool reusesAppIcon: (act?.icon ?? "") !== "" && act.icon === root.itemIcon
        readonly property string imageName: reusesAppIcon ? "" : (act?.icon ?? "")
        readonly property string symbolName: act?.materialIcon ?? (imageName === "" ? root.actionSymbol(act?.name) : "")
        implicitHeight: 34
        buttonRadius: 4
        colBackground: activeFocus ? ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.78)
            : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.91)
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.84)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.76)
        onClicked: root.runAction(actionIndex)
        Keys.onPressed: event => root.actionKey(actionButton, event)
        // One after another as the list opens
        opacity: 0
        transform: Translate { id: actionShift; y: -6 }
        SequentialAnimation {
            running: true
            PauseAnimation { duration: actionButton.delay }
            ParallelAnimation {
                NumberAnimation { target: actionButton; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: actionShift; property: "y"; to: 0; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
            }
        }
        contentItem: Item {
            RowLayout {
                id: actionRow
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                width: parent.width - 24
                spacing: 10
                MaterialSymbol {
                    visible: actionButton.symbolName !== ""
                    text: actionButton.symbolName
                    iconSize: 17
                    color: Appearance.colors.colOnLayer3
                }
                IconImage {
                    visible: actionButton.symbolName === ""
                    source: actionButton.imageName !== "" ? Quickshell.iconPath(actionButton.imageName) : ""
                    implicitSize: 17
                }
                StyledText {
                    Layout.fillWidth: true
                    text: actionButton.act?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colOnLayer3
                }
                StyledText { // Its Alt+ key
                    visible: actionButton.actionIndex < 9
                    text: `Alt+${actionButton.actionIndex + 1}`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // The result's icon at any size: the shell's tile, a symbol, an emoji or the app's own
    component ResultIcon: Item {
        id: resultIcon
        property real size: 30
        implicitWidth: size
        implicitHeight: size
        ShellAppIcon {
            visible: root.shellSymbol !== ""
            anchors.centerIn: parent
            size: resultIcon.size
            symbol: root.shellSymbol || "settings"
        }
        MaterialSymbol {
            visible: root.shellSymbol === "" && root.materialSymbol !== ""
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            text: root.materialSymbol
            iconSize: Math.round(resultIcon.size * 0.75)
            color: root.grown ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
        }
        StyledText {
            visible: root.shellSymbol === "" && root.materialSymbol === "" && root.bigText !== ""
            anchors.centerIn: parent
            text: root.bigText
            font.pixelSize: Math.round(resultIcon.size * 0.8)
        }
        IconImage {
            visible: root.shellSymbol === "" && root.materialSymbol === "" && root.bigText === "" && root.itemIcon !== ""
            anchors.fill: parent
            implicitSize: resultIcon.size
            source: visible ? Quickshell.iconPath(root.itemIcon, "image-missing") : ""
        }
    }

    // ── A plain line ──
    RowLayout {
        id: line
        visible: opacity > 0
        opacity: 1 - Math.min(1, root.reveal * 2.5) // Gone before the card's contents arrive
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 14 }
        spacing: 12
        ResultIcon {
            visible: root.shellSymbol !== "" || root.materialSymbol !== "" || root.bigText !== "" || root.itemIcon !== ""
            size: 30
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                spacing: 6
                Rectangle { // Checkmark for the clipboard entry that's copied now
                    visible: root.isClipboard && root.itemName == Quickshell.clipboardText
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: 6
                    color: Appearance.colors.colPrimary
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 14
                        color: Appearance.colors.colOnPrimary
                    }
                }
                Repeater { // Favicons for links
                    model: root.query == root.itemName ? [] : root.urls
                    Favicon {
                        required property var modelData
                        size: 18
                        url: modelData
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText // Elides, unlike RichText
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family[root.fontType]
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                    text: root.displayContent
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.itemSubtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ── Grown: halo, big name, actions (built only for the chosen row, and while it shrinks back) ──
    Loader {
        id: card
        anchors.fill: parent
        active: root.grown || root.reveal > 0
        sourceComponent: Item {
            readonly property real bodyHeight: grownBody.implicitHeight
            property alias moreButton: moreButton
            property alias listRepeater: listRepeater
            Shape { // A soft halo in the icon's colour behind it, kept inside the card (no clipping layer)
                id: halo
                visible: grownBody.visible
                opacity: grownBody.opacity
                readonly property real r: Math.min(grownIcon.x + grownIcon.width / 2, grownIcon.y + grownIcon.height / 2) + 14
                x: grownBody.x + grownIcon.x + grownIcon.width / 2 - r
                y: grownBody.y + grownIcon.y + grownIcon.height / 2 - r
                scale: 0.5 + 0.5 * root.reveal // Blooms out from the icon
                width: r * 2
                height: r * 2
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: halo.r; centerY: halo.r
                        focalX: centerX; focalY: centerY
                        centerRadius: halo.r
                        GradientStop { position: 0.0; color: ColorUtils.transparentize(root.tint, 0.55) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    PathRectangle { width: halo.width; height: halo.height }
                }
            }
            Rectangle { // A thin rim in the icon's colour
                anchors.fill: parent
                visible: grownBody.visible
                opacity: grownBody.opacity
                color: "transparent"
                border.width: 1.5
                border.color: ColorUtils.transparentize(root.tint, 0.6)
                topLeftRadius: root.buttonRadiusTop; topRightRadius: root.buttonRadiusTop
                bottomLeftRadius: root.buttonRadiusBottom; bottomRightRadius: root.buttonRadiusBottom
            }
            RowLayout {
                id: grownBody
                visible: opacity > 0
                opacity: root.reveal
                transform: Translate { y: (1 - root.reveal) * 10 }
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 16 }
                spacing: 16
                ResultIcon {
                    id: grownIcon
                    Layout.alignment: Qt.AlignTop
                    size: 60
                    scale: 0.8 + 0.2 * root.reveal
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText { // Name (a sum or a command in monospace, clipboard text wrapped)
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        text: root.displayContent
                        elide: Text.ElideRight
                        wrapMode: root.isClipboard ? Text.WrapAnywhere : Text.NoWrap
                        maximumLineCount: root.isClipboard ? 4 : 1
                        color: Appearance.colors.colOnLayer3
                        font.family: root.isClipboard ? Appearance.font.family.main
                            : root.fontType === "monospace" ? Appearance.font.family.monospace : Appearance.font.family.title
                        font.weight: root.isClipboard ? Font.Normal : root.fontType === "monospace" ? Font.DemiBold : Font.Black
                        font.pixelSize: root.isClipboard ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.huge
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== "" && !root.isClipboard
                        text: root.itemSubtitle
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ColorUtils.mix(Appearance.colors.colOnLayer3, root.tint, 0.6)
                    }
                    Loader { // Clipboard image
                        active: root.isClipboardImage && root.grown
                        visible: active
                        Layout.topMargin: 4
                        sourceComponent: CliphistImage {
                            entry: root.cliphistRawString
                            maxWidth: grownBody.width - 80
                            maxHeight: 140
                        }
                    }
                    ColumnLayout { // Actions: the main one, and "⋯" listing the result's own actions under it
                        id: actionsBox
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 4
                        readonly property bool hasActions: root.itemActions.length > 0
                        Row {
                            spacing: 3
                            RippleButton {
                                id: mainButton
                                implicitHeight: 36
                                implicitWidth: mainRow.implicitWidth + 28
                                buttonRadius: Appearance.rounding.small
                                buttonRadiusRight: root.itemActions.length > 0 ? 4 : Appearance.rounding.small
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                colRipple: Appearance.colors.colPrimaryActive
                                onClicked: root.clicked()
                                contentItem: Item {
                                    RowLayout {
                                        id: mainRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        StyledText {
                                            // Clipboard and emoji results have no action name: they copy
                                            text: root.itemClickActionName !== "" ? root.itemClickActionName
                                                : (root.isClipboard || root.bigText !== "") ? Translation.tr("Copy") : Translation.tr("Open")
                                            color: Appearance.colors.colOnPrimary
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                            font.weight: Font.Medium
                                        }
                                        StyledText {
                                            text: "↵"
                                            opacity: 0.7
                                            color: Appearance.colors.colOnPrimary
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                        }
                                    }
                                }
                            }
                            RippleButton { // "⋯": the actions, listed below
                                id: moreButton
                                visible: root.grown && actionsBox.hasActions
                                implicitHeight: 36
                                implicitWidth: 40
                                buttonRadius: 4
                                buttonRadiusRight: Appearance.rounding.small
                                colBackground: activeFocus || root.showAllActions ? ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.78)
                                    : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.91)
                                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.84)
                                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.76)
                                onClicked: root.showAllActions = !root.showAllActions
                                Keys.onPressed: event => root.actionKey(moreButton, event)
                                StyledToolTip { text: root.showAllActions ? Translation.tr("Fewer actions") : Translation.tr("More actions") }
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.showAllActions ? "expand_less" : "more_horiz"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer3
                                }
                            }
                        }
                        ColumnLayout { // The actions, as joined rows
                            Layout.fillWidth: true
                            Layout.maximumWidth: 320
                            visible: root.showAllActions && actionsBox.hasActions
                            spacing: 3
                            Repeater {
                                id: listRepeater
                                model: root.grown && root.showAllActions ? root.itemActions.length : 0
                                delegate: ActionButton {
                                    required property int index
                                    Layout.fillWidth: true
                                    actionIndex: index
                                    buttonRadiusTop: index === 0 ? Appearance.rounding.small : 4
                                    buttonRadiusBottom: index === listRepeater.count - 1 ? Appearance.rounding.small : 4
                                    delay: index * 30
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
