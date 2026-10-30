import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * A Steam game's official news (patch notes, updates, events) in a panel growing up out of the
 * launcher (LauncherTopPanel), same look as the achievements. Posts on the left, the selected one on the
 * right, laid out from blocks (scripts/game-launcher/steam_news.py). The post is a ListView, so its
 * images load as they scroll into view rather than all at once (some posts have dozens). Wide and
 * compact to suit the sheet's short height: the list shows titles only, and images that can span the
 * article become banners like Steam's own headers (cropped from the centre; click for the whole one).
 * Posts newer than the last visit are marked New (seen once the sheet closes, which also clears the
 * News button's count), and "Updates" in the header narrows the list to patch notes.
 * ↑/↓ change post, Esc closes.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1400
    panelHeight: 640
    clipContent: true

    readonly property var allPosts: GameLauncherService.newsFor === (game?.id ?? "") ? GameLauncherService.news : []
    // "Updates" narrows to patch notes; offered only when the feed has both kinds
    readonly property bool canFilter: allPosts.some(p => p.update) && allPosts.some(p => !p.update)
    readonly property bool updatesOnly: canFilter && (Config.options.gameLauncher.newsUpdatesOnly ?? false)
    readonly property var posts: updatesOnly ? allPosts.filter(p => p.update) : allPosts
    property int selected: 0
    readonly property var post: posts[selected] ?? null
    property real seenAtOpen: 0 // Posts after this are New (newsSeenFor, as it was when the sheet opened)

    onShownChanged: {
        if (shown) {
            seenAtOpen = GameLauncherService.newsSeenFor(game?.id ?? "");
            selected = 0;
            GameLauncherService.loadNews(game);
        } else markSeen();
    }
    // Also when the launcher closes with the sheet still up (the page goes away without it closing)
    Component.onDestruction: if (shown) markSeen()
    function markSeen() {
        if (allPosts.length > 0) GameLauncherService.markNewsSeen(game.id, Math.max(...allPosts.map(p => p.date)));
        GameLauncherService.markBuildSeen(game); // Its patch notes read: the Updated badge goes
    }
    onUpdatesOnlyChanged: selected = 0
    // A newly shown post starts at its title (the first row of the article)
    onPostChanged: Qt.callLater(() => article.positionViewAtBeginning())
    function handleKey(key) {
        if (key === Qt.Key_Escape) { closeRequested(); return true; }
        if (key === Qt.Key_Down) { selected = Math.min(posts.length - 1, selected + 1); postList.positionViewAtIndex(selected, ListView.Contain); return true; }
        if (key === Qt.Key_Up) { selected = Math.max(0, selected - 1); postList.positionViewAtIndex(selected, ListView.Contain); return true; }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the sheet
    }
    function formatDate(seconds) {
        return seconds > 0 ? Qt.formatDate(new Date(seconds * 1000), "MMM d, yyyy") : "";
    }

    SheetHeader {
        id: header
        icon: "newspaper"
        title: Translation.tr("News")
        subtitle: root.game?.name ?? ""
        onCloseRequested: root.closeRequested()
        Rectangle { // "Updates": only patch notes
            visible: root.canFilter
            width: filterRow.implicitWidth + 24; height: 32; radius: Appearance.rounding.segment
            color: root.updatesOnly ? Appearance.colors.colPrimary
                : filterHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
                id: filterRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "build"; iconSize: 16
                    color: root.updatesOnly ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Updates")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: root.updatesOnly ? Font.DemiBold : Font.Medium
                    color: root.updatesOnly ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                }
            }
            HoverHandler { id: filterHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Config.options.gameLauncher.newsUpdatesOnly = !root.updatesOnly }
        }
        SheetIconButton {
            visible: (root.post?.url ?? "") !== ""
            iconName: "open_in_new"
            tip: Translation.tr("Open in browser")
            onClicked: Qt.openUrlExternally(root.post.url)
        }
    }

    // ── Posts ──
    ListView {
        id: postList
        anchors { top: header.bottom; topMargin: 14; bottom: parent.bottom; bottomMargin: 8; left: parent.left; leftMargin: 12 }
        width: 340
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.posts
        delegate: Rectangle {
            id: postRow
            required property var modelData
            required property int index
            readonly property bool current: root.selected === index
            width: postList.width
            height: postCol.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: current ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                : postHover.hovered ? Appearance.colors.colLayer1 : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: postHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.selected = postRow.index }
            Column {
                id: postCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                spacing: 3
                StyledText {
                    width: parent.width
                    text: postRow.modelData.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: postRow.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Row { // Date, and whether it's new or an update
                    spacing: 6
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.formatDate(postRow.modelData.date)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    PostChip {
                        visible: postRow.modelData.date > root.seenAtOpen
                        text: Translation.tr("New")
                        tint: Appearance.colors.colPrimary
                    }
                    PostChip {
                        visible: postRow.modelData.update ?? false
                        text: Translation.tr("Update")
                        tint: Appearance.colors.colTertiary
                    }
                }
            }
        }
    }
    Rectangle { // Divider
        anchors { top: postList.top; bottom: postList.bottom; left: postList.right; leftMargin: 10 }
        width: 1
        color: Appearance.colors.colLayer1
        visible: root.posts.length > 0
    }

    // ── The selected post ──
    ListView {
        id: article
        anchors { top: header.bottom; topMargin: 14; bottom: parent.bottom; bottomMargin: 8; left: postList.right; leftMargin: 24; right: parent.right; rightMargin: 20 }
        clip: true
        spacing: 12
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 600 // A little ahead, not the whole post
        visible: root.post !== null
        // The title is the first row rather than a ListView header, so "back to the top" always shows it
        model: root.post ? [{ type: "title" }].concat(root.post.blocks) : []
        delegate: Loader {
            id: block
            required property var modelData
            width: article.width
            sourceComponent: modelData.type === "title" ? titleBlock
                : modelData.type === "heading" ? headingBlock
                : modelData.type === "image" ? imageBlock
                : modelData.type === "list" ? listBlock
                : modelData.type === "video" ? videoBlock
                : modelData.type === "rule" ? ruleBlock
                : textBlock
            Component {
                id: titleBlock
                Column {
                    bottomPadding: 2
                    spacing: 4
                    StyledText {
                        width: block.width
                        text: root.post?.title ?? ""
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        text: [root.formatDate(root.post?.date ?? 0), root.post?.author ?? ""].filter(s => s).join("  ·  ")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            Component {
                id: textBlock
                PostText { text: block.modelData.html }
            }
            Component {
                id: headingBlock
                PostText {
                    topPadding: 6
                    text: block.modelData.html
                    font.pixelSize: block.modelData.level === 1 ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
            }
            Component {
                id: imageBlock
                Item {
                    id: imageItem
                    // Wide enough to span the article: a banner, full width and at most 3.3:1 (the shape of
                    // Steam's header banners), cropped from the centre; already-wide ones aren't cropped.
                    // Smaller ones (icons) stay at their own size
                    readonly property real bannerAspect: 3.3
                    readonly property bool ready: img.status === Image.Ready && img.implicitHeight > 0
                    readonly property real aspect: ready ? img.implicitWidth / img.implicitHeight : bannerAspect
                    readonly property bool banner: !ready || img.implicitWidth >= width * 0.75
                    readonly property real shownWidth: banner ? width : img.implicitWidth
                    implicitHeight: Math.round(shownWidth / Math.max(aspect, banner ? bannerAspect : 0))
                    Image {
                        id: img
                        width: parent.shownWidth
                        height: parent.height
                        source: block.modelData.url
                        fillMode: imageItem.banner ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                        clip: true // The crop
                        asynchronous: true
                        sourceSize.width: 1400 // The sheet's width; posts often link 4K images
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        MouseArea { // The whole image, uncropped, in the browser
                            anchors.fill: parent
                            enabled: img.status === Image.Ready
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(block.modelData.url)
                        }
                    }
                    Rectangle { // Placeholder while it loads
                        visible: img.status !== Image.Ready
                        width: img.width; height: parent.height
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: img.status === Image.Error ? "broken_image" : "image"
                            iconSize: 22
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            Component {
                id: listBlock
                Column {
                    spacing: 4
                    Repeater {
                        model: block.modelData.items
                        Row {
                            required property var modelData
                            width: block.width
                            spacing: 10
                            StyledText { text: "•"; color: Appearance.colors.colPrimary; font.pixelSize: Appearance.font.pixelSize.small }
                            PostText { width: block.width - 20; text: modelData }
                        }
                    }
                }
            }
            Component {
                id: videoBlock
                Item {
                    implicitHeight: 40
                    RippleButton {
                        height: 36
                        width: videoRow.implicitWidth + 28
                        buttonRadius: Appearance.rounding.container
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        onClicked: Qt.openUrlExternally(block.modelData.url)
                        contentItem: Item {
                            Row {
                                id: videoRow
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "play_circle"; iconSize: 20; fill: 1; color: Appearance.colors.colPrimary }
                                StyledText { anchors.verticalCenter: parent.verticalCenter; text: Translation.tr("Watch video"); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium; color: Appearance.colors.colOnLayer1 }
                            }
                        }
                    }
                }
            }
            Component {
                id: ruleBlock
                Item {
                    implicitHeight: 9
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Appearance.colors.colLayer1 }
                }
            }
        }
    }

    SheetEdgeFade {
        anchors { left: postList.left; right: postList.right; top: postList.top }
        height: 20
        sheetColor: root.backgroundColor
        active: !postList.atYBeginning
    }
    SheetEdgeFade {
        anchors { left: postList.left; right: postList.right; bottom: postList.bottom }
        height: 28; reversed: true
        sheetColor: root.backgroundColor
        active: !postList.atYEnd
    }
    SheetEdgeFade {
        anchors { left: article.left; right: article.right; top: article.top }
        height: 20
        sheetColor: root.backgroundColor
        visible: article.visible
        active: !article.atYBeginning
    }
    SheetEdgeFade {
        anchors { left: article.left; right: article.right; bottom: article.bottom }
        height: 28; reversed: true
        sheetColor: root.backgroundColor
        visible: article.visible
        active: !article.atYEnd
    }

    SheetEmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        visible: root.posts.length === 0
        icon: GameLauncherService.newsLoading ? "hourglass_empty" : GameLauncherService.newsError ? "wifi_off" : "newspaper"
        text: GameLauncherService.newsLoading ? Translation.tr("Loading news…")
            : GameLauncherService.newsError ? Translation.tr("Couldn't load the news") : Translation.tr("No news yet")
        hint: GameLauncherService.newsLoading ? ""
            : GameLauncherService.newsError ? Translation.tr("Check your connection and try again")
            : Translation.tr("The developer hasn't posted any announcements")
    }

    component PostChip: Rectangle {
        property alias text: chipText.text
        property color tint
        anchors.verticalCenter: parent.verticalCenter
        width: chipText.implicitWidth + 12; height: 16; radius: Appearance.rounding.unsharpenmore
        color: ColorUtils.transparentize(tint, 0.8)
        StyledText {
            id: chipText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: parent.tint
        }
    }

    // Body text: wraps, links open in the browser
    component PostText: StyledText {
        width: parent ? parent.width : 0
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer1
        linkColor: Appearance.colors.colPrimary
        lineHeight: 1.25
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
}
