import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Widgets

/**
 * A Steam game's official news (patch notes, updates, events) in a panel growing up out of the launcher
 * (LauncherTopPanel). Across the top, the selected post's picture (the game's art without one) with its title, date
 * and author on it, on a smooth edge (GlassEdge, as Captures'); click it for the whole picture. In its corners, one
 * glass piece with a newspaper squircle and All / Updates (the feed narrowed to patch notes, offered when it has
 * both), and the post on Steam and close. A post without a picture shows its video's thumbnail instead (▶ Watch video
 * on the banner). Under it, each in a well (GlassWell, as Captures'), the posts as rows (a squircle of each one's
 * first picture or video, an icon for its kind without either, the title on up to two lines, the chosen one an accent
 * card, a dot for New) and the post itself, laid out from blocks (scripts/game-launcher/steam_news.py). A long post's
 * sections fold out under it, joined to its card: a timeline filled down to the one being read, each a click away (8
 * rows at most, the rest scrolling to follow). The post is a ListView, so its images load as they scroll into view
 * rather than all at once (some posts have dozens); images that can span the article become banners like Steam's own
 * headers (cropped from the centre; click for the whole one).
 * Posts newer than the last visit are marked New (seen once the panel closes, which also clears the News button's
 * count). ↑/↓ change post, Page Up/Down and Space scroll it, [ / ] the previous / next section, Esc closes.
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
    property real seenAtOpen: 0 // Posts after this are New (newsSeenFor, as it was when the panel opened)
    // Where a picture will be: faint in its well (a solid box showed as a dark patch)
    readonly property color placeholderColor: ColorUtils.transparentize("white", 0.95)
    // The banner's picture: the post's first. Near its start (often after a line of text) it isn't shown again
    // under it; further down it stays where it is
    readonly property string postArt: firstImage(post)
    // Without one, its first video's thumbnail stands in (the video is then on the banner, not repeated near the start)
    readonly property string postVideo: postArt === "" ? firstVideo(post) : ""
    readonly property var postBlocks: {
        if (!post) return [];
        const i = post.blocks.findIndex(b => b.type === (root.postArt !== "" ? "image" : "video"));
        return i >= 0 && i <= 2 ? post.blocks.filter((b, k) => k !== i) : post.blocks;
    }
    function firstImage(p) { return p?.blocks.find(b => b.type === "image")?.url ?? ""; }
    function firstVideo(p) { return p?.blocks.find(b => b.type === "video")?.url ?? ""; }
    // A YouTube video's thumbnail: maxresdefault (not every video has one: hqdefault then), mqdefault (small, 16:9)
    function videoThumb(url, size) {
        const m = /[?&]v=([\w-]+)/.exec(url ?? "");
        return m ? `https://i.ytimg.com/vi/${m[1]}/${size}.jpg` : "";
    }

    // The article: the post's blocks, then a button to it on Steam
    readonly property var articleModel: post ? postBlocks.concat(post.url ? [{ type: "end", url: post.url }] : []) : []
    // Its sections, for a long post (3+): each heading's text, where it is in the article and how many changes are
    // under it (list points, and lines starting "- ", "• " or "* ": some write their notes as text). Only the top
    // level of headings, and the one under it while the top has fewer than three: many posts nest two or three
    // levels, 18-27 headings in all, so sub-headings stay inside their section (their changes in its count)
    readonly property var sections: {
        const heads = articleModel.filter(b => b.type === "heading");
        if (heads.length < 3) return [];
        const top = Math.min(...heads.map(b => b.level));
        const depth = heads.filter(b => b.level === top).length >= 3 ? top : top + 1;
        const out = [];
        articleModel.forEach((b, i) => {
            if (b.type === "heading" && b.level <= depth) out.push({ name: b.html.replace(/<[^>]+>/g, ""), index: i, count: 0 });
            else if (out.length > 0) out[out.length - 1].count += changesIn(b);
        });
        return out.length >= 3 ? out : [];
    }
    function changesIn(block) {
        if (block.type === "list") return block.items.length;
        if (block.type !== "text") return 0;
        return block.html.split(/<br\s*\/?>/).filter(line => /^\s*(?:-|•|\*|–)\s/.test(line.replace(/<[^>]+>/g, ""))).length;
    }
    // The one being read: the last heading at or above the article's top (the last one once it's scrolled to the end)
    property int currentSection: -1
    // A section jumped to: current, and kept at the top while the article glides there and the pictures above it
    // load and change height (they'd push it down a section or so), until it's scrolled by hand or a moment passes
    property int heldSection: -1
    function updateCurrentSection() {
        if (heldSection >= 0) return;
        if (sections.length === 0) { currentSection = -1; return; }
        if (article.atYEnd && !article.atYBeginning) { currentSection = sections.length - 1; return; }
        const top = article.indexAt(article.width / 2, article.contentY + 8);
        if (top < 0) return; // Between two blocks: stays as it was
        let found = -1;
        for (let k = 0; k < sections.length && sections[k].index <= top; k++) found = k;
        currentSection = found;
    }
    // A section, or a screen further, scrolled to smoothly. Where a section starts is found by placing the article
    // there; it then goes back and glides
    function showSection(k) {
        if (k < 0 || k >= sections.length) return;
        articleScroll.stop();
        heldSection = k;
        currentSection = k;
        const from = article.contentY;
        article.positionViewAtIndex(sections[k].index, ListView.Beginning);
        glideArticle(from, article.contentY);
    }
    function scrollArticleBy(dy) {
        releaseSection();
        const maxY = article.originY + Math.max(0, article.contentHeight - article.height);
        glideArticle(article.contentY, Math.max(article.originY, Math.min(article.contentY + dy, maxY)));
    }
    function glideArticle(from, to) {
        article.contentY = from;
        articleScroll.from = from;
        articleScroll.to = to;
        articleScroll.start();
    }
    function holdSection() {
        if (heldSection < 0 || heldSection >= sections.length || articleScroll.running) return;
        article.positionViewAtIndex(sections[heldSection].index, ListView.Beginning);
    }
    function releaseSection() {
        articleScroll.stop();
        heldSection = -1;
    }
    NumberAnimation {
        id: articleScroll
        target: article
        property: "contentY"
        duration: 260
        easing.type: Easing.OutCubic
        onFinished: if (root.heldSection >= 0) { // Placed exactly (heights above may have settled), then held a moment
            root.holdSection();
            holdTimer.restart();
        }
    }
    Timer { id: holdTimer; interval: 1500; onTriggered: root.heldSection = -1 }
    // The chosen post in view with its sections, once they've folded out
    onSelectedChanged: listFollow.restart()
    onSectionsChanged: { // Also once its news has loaded
        updateCurrentSection();
        listFollow.restart();
    }
    Timer {
        id: listFollow
        interval: 30
        onTriggered: { // Contained, and clear of the list's faded edges
            postList.positionViewAtIndex(root.selected, ListView.Contain);
            const item = postList.itemAtIndex(root.selected);
            if (!item) return;
            const fade = 20;
            const maxY = postList.originY + Math.max(0, postList.contentHeight - postList.height);
            const below = item.y + item.height - (postList.contentY + postList.height - fade);
            if (below > 0) postList.contentY = Math.min(postList.contentY + below, maxY);
            else if (item.y < postList.contentY + fade) postList.contentY = Math.max(postList.originY, item.y - fade);
        }
    }
    onShownChanged: {
        if (shown) {
            seenAtOpen = GameLauncherService.newsSeenFor(game?.id ?? "");
            selected = 0;
            GameLauncherService.loadNews(game);
        } else markSeen();
    }
    // Also when the launcher closes with the panel still up (the page goes away without it closing)
    Component.onDestruction: if (shown) markSeen()
    function markSeen() {
        if (allPosts.length > 0) GameLauncherService.markNewsSeen(game.id, Math.max(...allPosts.map(p => p.date)));
        GameLauncherService.markBuildSeen(game); // Its patch notes read: the Updated badge goes
    }
    onUpdatesOnlyChanged: selected = 0
    // A newly shown post starts at its title (the first row of the article)
    onPostChanged: {
        postBanner.thumbFallback = false;
        releaseSection();
        Qt.callLater(() => article.positionViewAtBeginning());
    }
    function handleKey(key) {
        if (key === Qt.Key_Escape) { closeRequested(); return true; }
        if (key === Qt.Key_Down) { selected = Math.min(posts.length - 1, selected + 1); return true; }
        if (key === Qt.Key_Up) { selected = Math.max(0, selected - 1); return true; }
        if (key === Qt.Key_PageDown || key === Qt.Key_PageUp || key === Qt.Key_Space) { // The post, most of a screen at a time
            scrollArticleBy((key === Qt.Key_PageUp ? -1 : 1) * article.height * 0.85);
            return true;
        }
        if ((key === Qt.Key_BracketRight || key === Qt.Key_BracketLeft) && sections.length > 0) {
            showSection(key === Qt.Key_BracketRight ? currentSection + 1 : Math.max(0, currentSection - 1));
            return true;
        }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the panel
    }
    // "Nov 4", with the year only when it isn't this year's
    function formatDate(seconds) {
        if (seconds <= 0) return "";
        const d = new Date(seconds * 1000);
        return Qt.formatDate(d, d.getFullYear() === new Date().getFullYear() ? "MMM d" : "MMM d, yyyy");
    }

    // ── The post's picture across the top, its title on it ──
    ClippingRectangle {
        id: postBanner
        property bool thumbFallback: false // The video has no maxresdefault thumbnail
        readonly property string picture: root.postArt
            || (root.postVideo !== "" ? root.videoThumb(root.postVideo, thumbFallback ? "hqdefault" : "maxresdefault") : "")
            || GameLauncherService.bannerArt(root.game)
        anchors { top: parent.top; topMargin: 12; left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12 }
        height: 140
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer3
        visible: root.post !== null
        Image {
            anchors.fill: parent
            source: postBanner.picture
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 1600 // A fixed size: posts often link 4K images
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            onStatusChanged: if (status === Image.Error && root.postArt === "" && root.postVideo !== "") postBanner.thumbFallback = true
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: postBanner.picture === ""
            text: "newspaper"
            iconSize: 40
            color: Appearance.colors.colSubtext
        }
        Rectangle { // Shade for the title, from a fifth of the way down
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.2; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 1) }
                GradientStop { position: 1; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.08) }
            }
        }
        MouseArea { // The whole picture, uncropped, in the browser (or the video it's from)
            anchors.fill: parent
            enabled: root.postArt !== "" || root.postVideo !== ""
            cursorShape: Qt.PointingHandCursor
            onClicked: StringUtils.openWebLink(root.postArt || root.postVideo) // Written by the game's developers
        }
        Column {
            anchors { left: parent.left; leftMargin: 22; right: parent.right; rightMargin: watchVideo.visible ? watchVideo.width + 34 : 22; bottom: parent.bottom; bottomMargin: 14 }
            spacing: 2
            Row {
                spacing: 8
                NewDot { visible: (root.post?.date ?? 0) > root.seenAtOpen }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: [root.formatDate(root.post?.date ?? 0), root.post?.author ?? "", root.post?.update ? Translation.tr("Update") : ""]
                        .filter(s => s).join("  ·  ")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.2)
                }
            }
            StyledText {
                width: parent.width
                text: root.post?.title ?? ""
                font.family: Appearance.font.family.title
                font.pixelSize: 26
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
        }
        RippleButton { // The video whose thumbnail this is, in its bottom-right corner
            id: watchVideo
            anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
            visible: root.postVideo !== ""
            focusPolicy: Qt.NoFocus // The page keeps the keys
            height: 36
            width: watchRow.implicitWidth + 26
            buttonRadius: Appearance.rounding.segment + 4
            colBackground: root.glassOverArt
            colBackgroundHover: root.glassOverArtHover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: StringUtils.openWebLink(root.postVideo)
            contentItem: Item {
                Row {
                    id: watchRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "play_arrow"; iconSize: 20; fill: 1; color: Appearance.colors.colOnLayer0 }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Watch video")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }
    GlassEdge { anchors.fill: postBanner; radius: postBanner.radius; visible: postBanner.visible }
    // Over its top-left corner: a newspaper squircle, then All / Updates when the feed has both
    GlassPiece {
        anchors { top: postBanner.top; topMargin: 10; left: postBanner.left; leftMargin: 10 }
        visible: postBanner.visible
        leadIcon: "newspaper"
        GlassSegment { visible: root.canFilter; label: Translation.tr("All"); on: !root.updatesOnly; onPicked: Config.options.gameLauncher.newsUpdatesOnly = false }
        GlassSegment { visible: root.canFilter; label: Translation.tr("Updates"); on: root.updatesOnly; onPicked: Config.options.gameLauncher.newsUpdatesOnly = true }
    }
    // Over its top-right corner: the post on Steam and close
    Row {
        anchors { top: postBanner.top; topMargin: 10; right: postBanner.right; rightMargin: 10 }
        spacing: 6
        SheetIconButton {
            grouped: false
            visible: (root.post?.url ?? "") !== ""
            iconName: "open_in_new"
            tip: Translation.tr("Open on Steam")
            colBackground: root.glassOverArt
            colBackgroundHover: root.glassOverArtHover
            onClicked: StringUtils.openWebLink(root.post.url)
        }
        SheetIconButton {
            grouped: false
            iconName: "close"
            tip: Translation.tr("Close")
            colBackground: root.glassOverArt
            colBackgroundHover: root.glassOverArtHover
            onClicked: root.closeRequested()
        }
    }
    // ── The wells: the posts on the left, the post on the right ──
    GlassWell {
        id: listWell
        anchors { top: postBanner.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 12; left: parent.left; leftMargin: 12 }
        width: 280 + 12
        visible: root.post !== null
    }
    GlassWell {
        id: articleWell
        anchors { top: listWell.top; bottom: listWell.bottom; left: listWell.right; leftMargin: 12; right: parent.right; rightMargin: 12 }
        visible: root.post !== null
    }

    // ── Posts: rows in their well, the chosen one an accent card ──
    ListView {
        id: postList
        anchors { fill: listWell; margins: 6 }
        clip: true
        // Its edges fade into the well while there's more to scroll to (a coloured fade showed as a dark band).
        // Only while it can scroll: a list that fits needs no layer
        layer.enabled: !(atYBeginning && atYEnd)
        layer.effect: ScrollFadeMask { topActive: !postList.atYBeginning; bottomActive: !postList.atYEnd }
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.posts
        delegate: Column {
            id: postItem
            required property var modelData
            required property int index
            width: postList.width
            spacing: 2
            Rectangle {
                id: postRow
                readonly property var modelData: postItem.modelData
                readonly property int index: postItem.index
                readonly property bool current: root.selected === index
                readonly property bool joined: current && root.sections.length > 0 // Its sections joined under it
                readonly property string art: root.firstImage(modelData)
                readonly property string video: art === "" ? root.videoThumb(root.firstVideo(modelData), "mqdefault") : ""
                width: postList.width
                height: Math.max(48, rowText.implicitHeight + 14)
                topLeftRadius: Appearance.rounding.small
                topRightRadius: topLeftRadius
                bottomLeftRadius: joined ? Appearance.rounding.joined : Appearance.rounding.small
                bottomRightRadius: bottomLeftRadius
                color: current ? Appearance.colors.colLayer3Accent : ColorUtils.transparentize(Appearance.colors.colLayer3Accent, 1)
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: postHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selected = postRow.index }
                ClippingRectangle { // Its first picture, else its video's (a ▶ in the corner), else an icon for its kind
                    id: thumb
                    readonly property string source: postRow.art || postRow.video
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 36; height: 36
                    radius: Appearance.rounding.segment
                    color: source !== "" ? Appearance.colors.colLayer3
                        : postRow.current ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                        : ColorUtils.transparentize("white", 0.93)
                    Image {
                        anchors.fill: parent
                        source: thumb.source
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 80 // Fixed: posts link images up to 4K
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: thumb.source === ""
                        text: postRow.modelData.update ? "build" : "campaign"
                        iconSize: 18
                        fill: 1
                        color: postRow.current ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
                    }
                    Rectangle { // A video's
                        visible: postRow.video !== ""
                        anchors { right: parent.right; bottom: parent.bottom; margins: 2 }
                        width: 14; height: 14
                        radius: 5
                        color: ColorUtils.transparentize("black", 0.4)
                        MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; iconSize: 12; fill: 1; color: "white" }
                    }
                }
                Column { // Title (up to two lines), then a dot if it's new, the date, and whether it's an update
                    id: rowText
                    anchors { left: thumb.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    StyledText {
                        id: rowTitle
                        width: parent.width
                        text: postRow.modelData.title
                        font.pixelSize: Appearance.font.pixelSize.smallie + 1
                        font.weight: Font.DemiBold
                        color: postRow.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }
                    Row {
                        spacing: 6
                        NewDot { visible: postRow.modelData.date > root.seenAtOpen; size: 5 }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.formatDate(postRow.modelData.date)
                                + (postRow.modelData.update ? "  ·  " + Translation.tr("Update") : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest + 1
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                Item { // The hover line, under the title's last line (as long as it)
                    x: rowText.x
                    y: rowText.y + rowTitle.height + 1
                    width: Math.min(rowTitle.contentWidth, rowTitle.width)
                    height: 2
                    HoverLine { inset: 0; anchors.bottomMargin: 0; shown: postHover.hovered && !postRow.current }
                }
            }
            Item { // A long post's sections, joined under it while it's shown: a timeline filled down to the one being read
                id: nest
                readonly property real rowStep: 30 // A row and the gap under it
                readonly property real lineX: 23
                readonly property int maxRows: 8 // More scroll, following the one being read
                visible: postRow.joined
                width: postList.width
                height: visible ? sectionList.height + 8 : 0
                Rectangle { // The card, joined to the post's
                    anchors.fill: parent
                    topLeftRadius: Appearance.rounding.joined
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: Appearance.rounding.small
                    bottomRightRadius: bottomLeftRadius
                    color: ColorUtils.transparentize(Appearance.colors.colLayer3Accent, 0.45)
                }
                ListView {
                    id: sectionList
                    y: 4
                    width: parent.width
                    height: Math.min(count, nest.maxRows) * nest.rowStep - spacing
                    spacing: nest.rowStep - 28
                    clip: true
                    interactive: count > nest.maxRows
                    boundsBehavior: Flickable.StopAtBounds
                    model: nest.visible ? root.sections : []
                    // Its edges fade while there's more (only while it can scroll: no layer otherwise)
                    layer.enabled: interactive
                    layer.effect: ScrollFadeMask { topActive: !sectionList.atYBeginning; bottomActive: !sectionList.atYEnd }
                    Connections { // The one being read kept in the middle: read above, ahead below (clear of the fades)
                        target: root
                        function onCurrentSectionChanged() {
                            if (sectionList.interactive && root.currentSection >= 0 && root.currentSection < sectionList.count)
                                sectionList.positionViewAtIndex(root.currentSection, ListView.Center);
                        }
                    }
                    delegate: Item {
                        id: sectionRow
                        required property var modelData
                        required property int index
                        readonly property bool reading: root.currentSection === index
                        readonly property bool read: index < root.currentSection
                        width: sectionList.width
                        height: 28
                        Rectangle { // The line on to the next one, filled once this one's read
                            visible: sectionRow.index < sectionList.count - 1
                            x: nest.lineX; y: 14
                            width: 2; height: nest.rowStep
                            color: sectionRow.read ? Appearance.colors.colPrimary : ColorUtils.transparentize("white", 0.9)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Rectangle { // Its dot: filled once read, ringed while it's read, hollow ahead
                            x: nest.lineX + 1 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: sectionRow.reading ? 12 : 8
                            height: width
                            radius: width / 2
                            color: sectionRow.reading ? Appearance.colors.colPrimary
                                : sectionRow.read ? Appearance.colors.colSubtext : Appearance.colors.colLayer3Accent
                            border.width: sectionRow.reading ? 3 : sectionRow.read ? 0 : 1.5
                            border.color: sectionRow.reading ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65) : ColorUtils.transparentize("white", 0.7)
                        }
                        Rectangle {
                            x: 34
                            width: parent.width - 40
                            height: parent.height
                            radius: Appearance.rounding.segment - 1
                            color: sectionRow.reading ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84) : ColorUtils.transparentize(Appearance.colors.colPrimary, 1)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: sectionHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.showSection(sectionRow.index) }
                            StyledText {
                                id: sectionName
                                anchors { left: parent.left; leftMargin: 10; right: sectionCount.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: sectionRow.modelData.name
                                textFormat: Text.StyledText // Entities (&amp;) as their characters
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.weight: sectionRow.reading ? Font.DemiBold : Font.Medium
                                color: sectionRow.reading ? Appearance.colors.colPrimary
                                    : sectionRow.read ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                            }
                            StyledText {
                                id: sectionCount
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                visible: sectionRow.modelData.count > 0
                                text: String(sectionRow.modelData.count)
                                font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({}) // Not Roboto Flex's tuning
                                color: sectionRow.reading ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            Item { // The hover line, under the name
                                x: sectionName.x
                                width: Math.min(sectionName.implicitWidth, sectionName.width)
                                height: parent.height
                                HoverLine { inset: 0; anchors.bottomMargin: 3; shown: sectionHover.hovered && !sectionRow.reading }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── The selected post ──
    ListView {
        id: article
        anchors { fill: articleWell; topMargin: 14; bottomMargin: 8; leftMargin: 20; rightMargin: 20 }
        clip: true
        layer.enabled: !(atYBeginning && atYEnd) // As the list's
        layer.effect: ScrollFadeMask { topActive: !article.atYBeginning; bottomActive: !article.atYEnd }
        spacing: 12
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 600 // A little ahead, not the whole post
        visible: root.post !== null
        model: root.articleModel // It ends on a button to the post on Steam
        onContentYChanged: root.updateCurrentSection()
        onContentHeightChanged: root.holdSection()
        onOriginYChanged: root.holdSection()
        onMovingChanged: if (moving) root.releaseSection() // Scrolled by hand: no gliding or holding against it
        delegate: Loader {
            id: block
            required property var modelData
            width: article.width
            sourceComponent: modelData.type === "heading" ? headingBlock
                : modelData.type === "image" ? imageBlock
                : modelData.type === "list" ? listBlock
                : modelData.type === "video" ? videoBlock
                : modelData.type === "rule" ? ruleBlock
                : modelData.type === "end" ? endBlock
                : textBlock
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
                        color: img.status === Image.Ready ? "transparent" : root.placeholderColor
                        Image {
                            id: img
                            anchors.fill: parent
                            source: block.modelData.url
                            fillMode: imageItem.banner ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 1400 // About the panel's width; posts often link 4K images
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
                Item { // The video's own thumbnail, a glass ▶ on it: a click opens it
                    implicitHeight: 248
                    ClippingRectangle {
                        id: videoPicture
                        property bool fallback: false // No maxresdefault thumbnail
                        width: Math.min(440, parent.width)
                        height: parent.height
                        radius: Appearance.rounding.normal
                        color: videoImage.status === Image.Ready ? "transparent" : root.placeholderColor
                        Image {
                            id: videoImage
                            anchors.fill: parent
                            source: root.videoThumb(block.modelData.url, videoPicture.fallback ? "hqdefault" : "maxresdefault")
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 880
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            onStatusChanged: if (status === Image.Error) videoPicture.fallback = true
                        }
                        Rectangle { anchors.fill: parent; color: ColorUtils.transparentize("black", 0.82) }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 64; height: 64
                            radius: 22
                            color: videoHover.hovered ? root.glassOverArtHover : root.glassOverArt
                            border { width: 1; color: ColorUtils.transparentize("white", 0.88) }
                            MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; iconSize: 34; fill: 1; color: Appearance.colors.colOnLayer0 }
                        }
                        Rectangle { // Where it plays
                            anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
                            width: siteLabel.implicitWidth + 20; height: 28
                            radius: Appearance.rounding.segment
                            color: root.glassOverArt
                            StyledText {
                                id: siteLabel
                                anchors.centerIn: parent
                                text: "YouTube"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                        Rim { radius: videoPicture.radius }
                        HoverHandler { id: videoHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: StringUtils.openWebLink(block.modelData.url) } // Written by the game's developers
                    }
                }
            }
            Component {
                id: endBlock
                Item {
                    implicitHeight: 52
                    PostButton {
                        anchors.bottom: parent.bottom
                        symbol: "open_in_new"; label: Translation.tr("Open on Steam"); url: block.modelData.url
                    }
                }
            }
            Component {
                id: ruleBlock
                Item {
                    implicitHeight: 4 // A break, without a line (the glass has none)
                }
            }
        }
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

    // A fine rim round a picture, as the glass's edges
    component Rim: Rectangle {
        anchors.fill: parent
        color: "transparent"
        border { width: 1; color: ColorUtils.transparentize("white", 0.88) }
    }

    // New: a small accent dot
    component NewDot: Rectangle {
        property real size: 6
        anchors.verticalCenter: parent.verticalCenter
        width: size; height: size; radius: size / 2
        color: Appearance.colors.colPrimary
    }

    // The post on Steam, at its end: a part in the well, its icon on an accent squircle, the name beside it
    component PostButton: RippleButton {
        property string symbol
        property string label
        property string url
        height: 36
        width: buttonRow.implicitWidth + 18
        buttonRadius: Appearance.rounding.small
        colBackground: ColorUtils.transparentize(Appearance.colors.colWindowGlassCard, 1)
        colBackgroundHover: Appearance.colors.colWindowGlassCard
        colRipple: Appearance.colors.colWindowGlassCardHover
        onClicked: StringUtils.openWebLink(url)
        contentItem: Item {
            Row {
                id: buttonRow
                x: 3; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    width: 30; height: 30
                    radius: Appearance.rounding.segment
                    color: Appearance.colors.colLayer3Accent
                    MaterialSymbol { anchors.centerIn: parent; text: symbol; iconSize: 18; fill: 1; color: Appearance.colors.colPrimary }
                }
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
