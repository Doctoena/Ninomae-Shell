import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

/**
 * A Steam game's achievements in a panel growing up out of the launcher (LauncherTopPanel). Read from
 * the Steam client's own files, or for games it hasn't loaded on this PC from your Steam profile, with each
 * one's share of players (scripts/game-launcher/steam_achievements.py), which also orders them:
 * unlocked newest first, then locked most common first (the easiest next). On top, a banner of the
 * game's art with how far you are and three highlights (the latest, the rarest you have, and the
 * easiest still locked), each a click away in the list. Under it the achievements as cards, in two
 * columns to suit the sheet's wide, short shape.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1240
    panelHeight: 640
    clipContent: true

    readonly property var achievementData: GameLauncherService.achievementsFor === (game?.id ?? "") ? GameLauncherService.achievements : null
    readonly property int total: achievementData?.total ?? 0
    readonly property int unlockedCount: achievementData?.unlocked ?? 0
    property string filter: "all" // all | unlocked | locked
    readonly property var visibleAchievements: (achievementData?.achievements ?? [])
        .filter(a => filter === "all" || (filter === "unlocked") === a.unlocked)
    readonly property real fraction: total > 0 ? unlockedCount / total : 0
    function percentText(p) { return p < 1 ? p.toFixed(1) : String(Math.round(p)); }
    // The banner's highlights: the latest unlocked, the rarest unlocked, and the easiest still locked
    readonly property var highlights: {
        const all = achievementData?.achievements ?? [];
        const unlocked = all.filter(a => a.unlocked);
        const out = [];
        const latest = unlocked.reduce((best, a) => !best || a.time > best.time ? a : best, null);
        if (latest) out.push({ key: latest.id, image: latest.icon, label: Translation.tr("Latest"), value: latest.name,
                               detail: Qt.formatDate(new Date(latest.time * 1000), "MMM d, yyyy") });
        const rarest = unlocked.filter(a => a.percent >= 0).reduce((best, a) => !best || a.percent < best.percent ? a : best, null);
        if (rarest && rarest !== latest)
            out.push({ key: rarest.id, image: rarest.icon, label: Translation.tr("Rarest"), value: rarest.name,
                       detail: Translation.tr("%1% of players").arg(percentText(rarest.percent)), accent: Appearance.colors.colTertiary });
        const next = all.filter(a => !a.unlocked && !a.hidden)
            .reduce((best, a) => !best || a.percent > best.percent ? a : best, null);
        if (next) out.push({ key: next.id, image: next.iconGray || next.icon, label: Translation.tr("Next up"), value: next.name,
                             detail: next.percent >= 0 ? Translation.tr("%1% of players have it").arg(percentText(next.percent)) : "" });
        return out;
    }
    // A highlight's achievement, in the list: every one shown, scrolled to it, its card lit for a moment
    property string flashId: ""
    Timer { id: flashTimer; interval: 1600; onTriggered: root.flashId = "" }
    function showAchievement(id) {
        filter = "all";
        Qt.callLater(() => {
            const i = visibleAchievements.findIndex(a => a.id === id);
            if (i < 0) return;
            list.positionViewAtIndex(i, GridView.Contain);
            flashId = id;
            flashTimer.restart();
        });
    }

    onShownChanged: {
        if (!shown) return;
        filter = "all";
        GameLauncherService.loadAchievements(game);
    }
    function handleKey(key) {
        if (key === Qt.Key_Escape) { closeRequested(); return true; }
        if (key === Qt.Key_Up || key === Qt.Key_Down) { // A row at a time
            const maxY = Math.max(0, list.contentHeight - list.height);
            list.contentY = Math.max(0, Math.min(list.contentY + (key === Qt.Key_Up ? -1 : 1) * list.cellHeight, maxY));
            return true;
        }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the sheet
    }

    SheetHeader {
        id: header
        icon: "emoji_events"
        iconFilled: true
        title: Translation.tr("Achievements")
        subtitle: root.game?.name ?? ""
        onCloseRequested: root.closeRequested()
        Rectangle { // Filter: All / Unlocked / Locked
            width: tabs.width + 8; height: 36; radius: Appearance.rounding.segment
            color: Appearance.colors.colLayer1
            visible: root.total > 0
            Row {
                id: tabs
                anchors.centerIn: parent
                Repeater {
                    model: [
                        { key: "all", label: Translation.tr("All") },
                        { key: "unlocked", label: Translation.tr("Unlocked") },
                        { key: "locked", label: Translation.tr("Locked") }
                    ]
                    Rectangle {
                        id: tabPill
                        required property var modelData
                        readonly property bool active: root.filter === modelData.key
                        width: tabText.implicitWidth + 28; height: 28; radius: Appearance.rounding.segment
                        color: active ? Appearance.colors.colPrimary : tabMa.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        StyledText {
                            id: tabText
                            anchors.centerIn: parent
                            text: tabPill.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: tabPill.active ? Font.DemiBold : Font.Medium
                            color: tabPill.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.filter = tabPill.modelData.key
                        }
                    }
                }
            }
        }
    }

    // ── Banner: the game's art, how far you are, and the highlights ──
    ClippingRectangle {
        id: banner
        readonly property string hero: GameLauncherService.bannerArt(root.game) // Else the cover, blurred
        readonly property string cover: GameLauncherService.localArt(root.game, "boxArt")
        anchors { top: header.bottom; topMargin: 14; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        height: root.total > 0 ? 112 : 0
        visible: root.total > 0
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        Image {
            anchors.fill: parent
            source: banner.hero || banner.cover
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: banner.hero ? Math.ceil(banner.width * Screen.devicePixelRatio) : 240
            visible: status === Image.Ready
            layer.enabled: visible && !banner.hero
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32; saturation: 0.35 }
        }
        Rectangle { // Shade for the text on both sides (the background colour can be translucent: made solid)
            id: shade
            anchors.fill: parent
            readonly property color base: Appearance.m3colors.m3background
            function at(a) { return Qt.rgba(base.r, base.g, base.b, a); }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: shade.at(0.9) }
                GradientStop { position: 0.5; color: shade.at(0.72) }
                GradientStop { position: 1.0; color: shade.at(0.55) }
            }
        }

        ClippingRectangle { // The cover, as the Downloads banner's
            id: bannerCover
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            width: 60; height: 80
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            Image {
                anchors.fill: parent
                source: banner.cover
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(120, 160)
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: banner.cover === ""
                text: "emoji_events"
                iconSize: 24; fill: 1
                color: Appearance.colors.colPrimary
            }
        }

        Column { // How far: the percentage, the count, the bar
            anchors { left: bannerCover.right; leftMargin: 18; right: highlightRow.left; rightMargin: 36; verticalCenter: parent.verticalCenter }
            spacing: 4
            StyledText {
                text: root.unlockedCount === root.total ? Translation.tr("All unlocked")
                    : Translation.tr("%1% complete").arg(Math.floor(root.fraction * 100))
                font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: Translation.tr("%1 of %2 unlocked").arg(root.unlockedCount).arg(root.total)
                font.pixelSize: Appearance.font.pixelSize.small
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
            }
            Item { width: 1; height: 6 }
            Rectangle {
                width: Math.min(parent.width, 420)
                height: 6; radius: 3
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.84)
                Rectangle {
                    width: parent.width * root.fraction
                    height: parent.height; radius: parent.radius
                    color: Appearance.colors.colPrimary
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                }
            }
        }

        Rectangle { // The highlights, on a see-through card with a hairline edge, so the art shows through
            id: highlightRow
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            visible: root.highlights.length > 0
            width: highlightItems.implicitWidth + 8
            height: highlightItems.implicitHeight + 8
            radius: Appearance.rounding.normal
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
            Row {
                id: highlightItems
                anchors.centerIn: parent
                Repeater {
                    model: root.highlights
                    Row {
                        required property var modelData
                        required property int index
                        Rectangle { // Divider
                            visible: index > 0
                            width: 1; height: 26
                            anchors.verticalCenter: parent.verticalCenter
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
                        }
                        Highlight { item: modelData }
                    }
                }
            }
        }
    }

    // A banner highlight: the achievement's icon, what it is (Latest, Rarest…) and its name. Clicking it shows
    // it in the list
    component Highlight: Item {
        id: hl
        property var item: ({})
        readonly property bool clickable: (item.key ?? "") !== ""
        width: hlRow.implicitWidth + 20
        height: 54
        Rectangle {
            anchors { fill: parent; margins: 2 }
            radius: Appearance.rounding.small
            color: hlHover.hovered && hl.clickable ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Row {
            id: hlRow
            anchors.centerIn: parent
            spacing: 10
            ClippingRectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(hl.item.accent ?? Appearance.colors.colPrimary, 0.8)
                Image {
                    anchors.fill: parent
                    visible: !!hl.item.image
                    source: hl.item.image ?? ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !hl.item.image
                    text: hl.item.icon ?? ""
                    iconSize: 18; fill: 1
                    color: hl.item.accent ?? Appearance.colors.colPrimary
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                StyledText {
                    text: hl.item.label ?? ""
                    font.pixelSize: 10; font.weight: Font.Medium
                    color: hl.item.accent ?? Appearance.colors.colPrimary
                }
                StyledText {
                    width: Math.min(implicitWidth, 200)
                    text: hl.item.value ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    visible: (hl.item.detail ?? "") !== ""
                    text: hl.item.detail ?? ""
                    font.pixelSize: 10
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
                }
            }
        }
        HoverHandler { id: hlHover; cursorShape: hl.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: hl.clickable; onTapped: root.showAchievement(hl.item.key) }
    }

    // ── List ──
    GridView {
        id: list
        anchors { top: banner.bottom; topMargin: 12; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 12 }
        cellWidth: Math.floor(width / 2)
        cellHeight: 70
        bottomMargin: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.visibleAchievements
        visible: root.total > 0
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool locked: !modelData.unlocked
            readonly property bool secret: locked && modelData.hidden
            readonly property real percent: modelData.percent ?? -1
            readonly property bool flashing: root.flashId !== "" && root.flashId === modelData.id
            width: list.cellWidth - 8
            height: list.cellHeight - 8
            radius: Appearance.rounding.normal
            color: flashing ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.78)
                : rowHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: 220 } }
            HoverHandler { id: rowHover }

            ClippingRectangle { // Icon (greyed while locked, a lock for hidden ones)
                id: icon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 46; height: 46
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                Image {
                    anchors.fill: parent
                    source: row.secret ? "" : row.locked ? row.modelData.iconGray : row.modelData.icon // Hidden ones show a lock: no icon to fetch
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 92
                    opacity: row.locked ? 0.55 : 1
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: row.secret
                    text: "lock"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
            }
            Column {
                anchors { left: icon.right; leftMargin: 14; right: side.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 2
                StyledText {
                    width: parent.width
                    text: row.secret ? Translation.tr("Hidden achievement") : row.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: row.locked ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: row.secret ? Translation.tr("Keep playing to find out") : row.modelData.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            Column { // When you got it, and how many players have it
                id: side
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 4
                Row {
                    anchors.right: parent.right
                    spacing: 6
                    Rectangle { // Rare: under 10% of players
                        visible: row.percent >= 0 && row.percent < 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: rareText.implicitWidth + 14; height: 20; radius: Appearance.rounding.chip
                        color: ColorUtils.transparentize(Appearance.colors.colTertiary, 0.8)
                        StyledText {
                            id: rareText
                            anchors.centerIn: parent
                            text: Translation.tr("Rare")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colTertiary
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.locked ? Translation.tr("Locked") : Qt.formatDate(new Date(row.modelData.time * 1000), "MMM d, yyyy")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: row.locked ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                    }
                }
                Row { // How many players have it, as a short bar
                    anchors.right: parent.right
                    visible: row.percent >= 0
                    spacing: 6
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("%1% of players").arg(root.percentText(row.percent))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 4; radius: 2
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.86)
                        Rectangle {
                            width: Math.max(height, parent.width * Math.min(100, row.percent) / 100)
                            height: parent.height; radius: parent.radius
                            color: row.percent < 10 ? Appearance.colors.colTertiary
                                : ColorUtils.transparentize(Appearance.colors.colPrimary, row.locked ? 0.5 : 0)
                        }
                    }
                }
            }
        }
    }

    SheetEdgeFade {
        anchors { left: list.left; right: list.right; top: list.top }
        height: 20
        sheetColor: root.backgroundColor
        visible: list.visible
        active: !list.atYBeginning
    }
    SheetEdgeFade {
        anchors { left: list.left; right: list.right; bottom: list.bottom }
        height: 28; reversed: true
        sheetColor: root.backgroundColor
        visible: list.visible
        active: !list.atYEnd
    }

    SheetEmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        visible: root.total === 0
        icon: GameLauncherService.achievementsLoading ? "hourglass_empty" : "emoji_events"
        text: GameLauncherService.achievementsLoading ? Translation.tr("Loading achievements…") : Translation.tr("No achievements")
        // Games that aren't on this PC come from the Steam profile (scripts/game-launcher/steam_achievements.py)
        readonly property string error: root.achievementData?.error ?? ""
        hint: GameLauncherService.achievementsLoading ? ""
            : error === "private" ? Translation.tr("Set your Steam profile's game details to public to see these for games that aren't on this PC")
            : error === "offline" ? Translation.tr("Couldn't reach Steam: this game isn't on this PC, so they come from your profile")
            : Translation.tr("This game doesn't have any")
    }
}
