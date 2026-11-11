import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Widgets

/**
 * A Steam game's official news (patch notes, updates, events) in a panel growing up out of the
 * launcher (LauncherTopPanel), same look as the achievements. Posts on the left (each with its first
 * picture, or an icon), the selected one on the right, laid out from blocks
 * (scripts/game-launcher/steam_news.py). It opens on an art banner (ArtBanner) with its title, date and
 * author: the post's first picture, else the game's art. The post is a ListView, so its images load as
 * they scroll into view rather than all at once (some posts have dozens). Compact to suit the sheet's
 * short height: images that can span the article become banners like Steam's own headers (cropped from
 * the centre; click for the whole one).
 * Posts newer than the last visit are marked New (seen once the sheet closes, which also clears the
 * News button's count), and All / Updates over the list narrows it to patch notes. No header: the banner
 * names the game, and the post on Steam and close sit in the corner.
 * ↑/↓ change post, Esc closes.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1240 // As the Achievements: the article's lines stay a readable length
    panelHeight: 640
    clipContent: true

    readonly property var allPosts: GameLauncherService.newsFor === (game?.id ?? "") ? GameLauncherService.news : []
    // "Updates" narrows to patch notes; offered only when the feed has both kinds
    readonly property bool canFilter: allPosts.some(p => p.update) && allPosts.some(p => !p.update)
    readonly property bool updatesOnly: canFilter && (Config.options.gameLauncher.newsUpdatesOnly ?? false)
    readonly property var posts: updatesOnly ? allPosts.filter(p => p.update) : allPosts
    property int selected: 0
    readonly property var post: posts[selected] ?? null
    // The banner's picture: the post's first. When the post starts with it, it isn't shown again under it
    readonly property string postArt: firstImage(post)
    readonly property var postBlocks: !post ? [] : post.blocks[0]?.type === "image" ? post.blocks.slice(1) : post.blocks
    function firstImage(p) { return p?.blocks.find(b => b.type === "image")?.url ?? ""; }
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
    // "Nov 4", with the year only when it isn't this year's
    function formatDate(seconds) {
        if (seconds <= 0) return "";
        const d = new Date(seconds * 1000);
        return Qt.formatDate(d, d.getFullYear() === new Date().getFullYear() ? "MMM d" : "MMM d, yyyy");
    }

    // No header: the banner names the game. The post on Steam and close in its top corner; All / Updates (when the
    // feed has both) in its bottom one, there while the post's top is in view (they'd sit over its text after)
    Row {
        id: filterRow
        anchors { top: article.top; topMargin: 148 - 30 - 12; right: article.right; rightMargin: 12 } // The banner's bottom corner
        z: 1
        opacity: article.contentY < 40 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        visible: root.canFilter && opacity > 0
        spacing: 3
        SheetFilterChip { label: Translation.tr("All"); on: !root.updatesOnly; onPicked: Config.options.gameLauncher.newsUpdatesOnly = false }
        SheetFilterChip { label: Translation.tr("Updates"); symbol: "build"; on: root.updatesOnly; onPicked: Config.options.gameLauncher.newsUpdatesOnly = true }
    }
    Row {
        anchors { top: parent.top; topMargin: 20; right: article.right; rightMargin: 8 }
        z: 1 // Over the article as it scrolls
        spacing: 6
        SheetIconButton {
            grouped: false
            visible: (root.post?.url ?? "") !== ""
            iconName: "open_in_new"
            tip: Translation.tr("Open on Steam")
            onClicked: StringUtils.openWebLink(root.post.url)
        }
        SheetIconButton {
            grouped: false
            iconName: "close"
            tip: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
    }

    // ── Posts ──
    ListView {
        id: postList
        anchors { top: parent.top; topMargin: 12; bottom: parent.bottom; bottomMargin: 8; left: parent.left; leftMargin: 12 }
        width: 280
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.posts
        // The newest post a card with its picture (or the game's art), the rest compact rows
        delegate: Rectangle {
            id: postRow
            required property var modelData
            required property int index
            readonly property bool current: root.selected === index
            readonly property bool featured: index === 0
            readonly property string art: root.firstImage(modelData)
            width: postList.width
            height: (featured ? featuredBox.height + 6 + postInfo.implicitHeight + 2 : Math.max(postInfo.implicitHeight, thumb.height)) + 14
            radius: Appearance.rounding.normal
            color: current ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                : postHover.hovered ? Appearance.colors.colLayer1 : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: postHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.selected = postRow.index }
            ClippingRectangle { // Featured: the picture across the card
                id: featuredBox
                visible: postRow.featured
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                height: 72
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                Image {
                    anchors.fill: parent
                    source: postRow.featured ? (postRow.art || GameLauncherService.bannerArt(root.game)) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 512 // Fixed: posts link images up to 4K
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }
            ClippingRectangle { // A row: its first picture, else the game's own art (an icon for its kind without either)
                id: thumb
                readonly property string source: postRow.featured ? "" : (postRow.art || GameLauncherService.bannerArt(root.game))
                visible: !postRow.featured
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                width: 52; height: 34
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                Image {
                    anchors.fill: parent
                    source: thumb.source
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 104
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: thumb.source === ""
                    text: postRow.modelData.update ? "build" : "campaign"
                    iconSize: 16
                    color: postRow.current ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
            }
            Column { // Title, date, and whether it's new or an update
                id: postInfo
                anchors {
                    left: postRow.featured ? parent.left : thumb.right; right: parent.right
                    leftMargin: postRow.featured ? 12 : 10; rightMargin: 12
                }
                y: postRow.featured ? featuredBox.y + featuredBox.height + 6 : (parent.height - height) / 2
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
                Row { // Date, and whether it's an update (plain text: most are), then New
                    spacing: 6
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.formatDate(postRow.modelData.date)
                            + (postRow.modelData.update ? "  ·  " + Translation.tr("Update") : "")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    PostChip {
                        visible: postRow.modelData.date > root.seenAtOpen
                        text: Translation.tr("New")
                        tint: Appearance.colors.colPrimary
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
        anchors { top: parent.top; topMargin: 12; bottom: parent.bottom; bottomMargin: 8; left: postList.right; leftMargin: 24; right: parent.right; rightMargin: 20 }
        clip: true
        spacing: 12
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 600 // A little ahead, not the whole post
        visible: root.post !== null
        // The title is the first row rather than a ListView header, so "back to the top" always shows it
        // and it ends on a button to the post on Steam
        model: root.post ? [{ type: "title" }].concat(root.postBlocks, root.post.url ? [{ type: "end", url: root.post.url }] : []) : []
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
                : modelData.type === "end" ? endBlock
                : textBlock
            Component {
                id: titleBlock
                ArtBanner {
                    id: postBanner
                    game: root.game
                    art: root.postArt
                    showLogo: true
                    coverIcon: "newspaper"
                    implicitHeight: 148
                    Column {
                        // Clear of the corner's buttons
                        anchors { left: postBanner.coverItem.right; leftMargin: 18; right: parent.right; rightMargin: 96; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        StyledText {
                            width: parent.width
                            text: root.post?.title ?? ""
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Row {
                            spacing: 8
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: [root.formatDate(root.post?.date ?? 0), root.post?.author ?? ""].filter(s => s).join("  ·  ")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
                            }
                            PostChip {
                                visible: (root.post?.date ?? 0) > root.seenAtOpen
                                text: Translation.tr("New")
                                tint: Appearance.colors.colPrimary
                            }
                            PostChip {
                                visible: root.post?.update ?? false
                                text: Translation.tr("Update")
                                tint: Appearance.colors.colTertiary
                            }
                        }
                    }
                }
            }
            Component {
                id: textBlock
                PostText { text: block.modelData.html }
            }
            Component {
                id: headingBlock
                Item { // An accent bar at its first line
                    implicitHeight: headingText.implicitHeight
                    Rectangle {
                        y: headingText.topPadding + 2
                        width: 3; height: headingText.font.pixelSize
                        radius: 2
                        color: Appearance.colors.colPrimary
                    }
                    PostText {
                        id: headingText
                        x: 12; width: parent.width - 12
                        topPadding: 6
                        text: block.modelData.html
                        font.pixelSize: block.modelData.level === 1 ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
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
                    ClippingRectangle { // Rounded as the shell's tiles; the placeholder until it's loaded
                        width: parent.shownWidth; height: parent.height
                        radius: Appearance.rounding.normal
                        color: img.status === Image.Ready ? "transparent" : Appearance.colors.colLayer1
                        Image {
                            id: img
                            anchors.fill: parent
                            source: block.modelData.url
                            fillMode: imageItem.banner ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 1400 // About the sheet's width; posts often link 4K images
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            MouseArea { // The whole image, uncropped, in the browser
                                anchors.fill: parent
                                enabled: img.status === Image.Ready
                                cursorShape: Qt.PointingHandCursor
                                onClicked: StringUtils.openWebLink(block.modelData.url) // Written by the game's developers
                            }
                        }
                        MaterialSymbol {
                            visible: img.status !== Image.Ready
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
                            StyledText { // Same size and line height as the text: on its first line
                                width: 10
                                text: "•"; color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.small; lineHeight: 1.25
                            }
                            PostText { width: block.width - 20; text: modelData }
                        }
                    }
                }
            }
            Component {
                id: videoBlock
                Item {
                    implicitHeight: 40
                    PostButton { symbol: "play_circle"; label: Translation.tr("Watch video"); url: block.modelData.url }
                }
            }
            Component {
                id: endBlock
                Item {
                    implicitHeight: 64
                    Rectangle { width: parent.width; height: 1; color: Appearance.colors.colLayer1 }
                    PostButton {
                        anchors.bottom: parent.bottom
                        symbol: "open_in_new"; label: Translation.tr("Open on Steam"); url: block.modelData.url
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

    // A link as a button (a video, the post on Steam): written by the game's developers, so opened only if
    // it's a web link
    component PostButton: RippleButton {
        property string symbol
        property string label
        property string url
        height: 36
        width: buttonRow.implicitWidth + 28
        buttonRadius: Appearance.rounding.container
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        onClicked: StringUtils.openWebLink(url)
        contentItem: Item {
            Row {
                id: buttonRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: symbol; iconSize: 20; fill: 1; color: Appearance.colors.colPrimary }
                StyledText { anchors.verticalCenter: parent.verticalCenter; text: label; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium; color: Appearance.colors.colOnLayer1 }
            }
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
        onLinkActivated: link => StringUtils.openWebLink(link)
        HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
}
