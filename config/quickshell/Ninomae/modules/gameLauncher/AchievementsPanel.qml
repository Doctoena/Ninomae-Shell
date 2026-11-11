import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell.Widgets

/**
 * A Steam game's achievements in a panel growing up out of the launcher (LauncherTopPanel). Read from
 * the Steam client's own files, or for games it hasn't loaded on this PC from your Steam profile, with each
 * one's share of players (scripts/game-launcher/steam_achievements.py), which also orders them:
 * unlocked newest first, then locked most common first (the easiest next). On top, a banner of the
 * game's art with how far you are and three highlights (the latest, the rarest you have, and the
 * easiest still locked), each a click away in the list, and close in its corner. Under it Unlocked / All /
 * Locked, then the achievements as cards, in two columns to suit the sheet's wide, short shape.
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
                               detail: Qt.formatDate(new Date(latest.time * 1000), "MMM d") });
        const rarest = unlocked.filter(a => a.percent >= 0).reduce((best, a) => !best || a.percent < best.percent ? a : best, null);
        if (rarest && rarest !== latest)
            out.push({ key: rarest.id, image: rarest.icon, label: Translation.tr("Rarest"), value: rarest.name,
                       detail: `${percentText(rarest.percent)}%` });
        const next = all.filter(a => !a.unlocked && !a.hidden)
            .reduce((best, a) => !best || a.percent > best.percent ? a : best, null);
        if (next) out.push({ key: next.id, image: next.iconGray || next.icon, label: Translation.tr("Next up"), value: next.name,
                             detail: next.percent >= 0 ? `${percentText(next.percent)}%` : "" });
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

    // No header: the banner names the game (its cover), close sits in its corner, and Unlocked / All / Locked
    // over the list, as the News panel's filters
    SheetIconButton {
        anchors { top: parent.top; topMargin: 20; right: parent.right; rightMargin: 28 }
        z: 1
        grouped: false
        iconName: "close"
        tip: Translation.tr("Close")
        onClicked: root.closeRequested()
    }

    // ── Banner: the game's art, how far you are, and the highlights ──
    ArtBanner {
        id: banner
        game: root.game
        coverIcon: "emoji_events"
        shadeMid: 0.72; shadeEnd: 0.55 // Lighter on the right: the highlights are solid chips
        anchors { top: parent.top; topMargin: 12; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        height: root.total > 0 ? 112 : 0
        visible: root.total > 0

        Column { // How far: the percentage, the count, the bar
            anchors { left: banner.coverItem.right; leftMargin: 18; right: highlightRow.left; rightMargin: 36; verticalCenter: parent.verticalCenter }
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

        Row { // The highlights, as joined chips (as the game page's facts)
            id: highlightRow
            anchors { right: parent.right; rightMargin: 14 + 36 + 12; verticalCenter: parent.verticalCenter } // Clear of close
            visible: root.highlights.length > 0
            spacing: 3
            Repeater {
                model: root.highlights
                Highlight {
                    required property var modelData
                    required property int index
                    item: modelData
                    first: index === 0
                    last: index === root.highlights.length - 1
                }
            }
        }
    }

    // A banner highlight, a chip of the joined row: the achievement's picture, what it is (Latest, Rarest…) over its
    // name, and when or how rare beside it. Clicking it shows it in the list
    component Highlight: RippleButton {
        id: hl
        property var item: ({})
        property bool first: false
        property bool last: false
        readonly property bool clickable: (item.key ?? "") !== ""
        focusPolicy: Qt.NoFocus // The details page keeps the keys
        implicitWidth: hlRow.implicitWidth + 22
        implicitHeight: 50
        padding: 0
        enabled: clickable
        buttonRadiusLeft: first ? Appearance.rounding.small : Appearance.rounding.joined
        buttonRadiusRight: last ? Appearance.rounding.small : Appearance.rounding.joined
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        onClicked: root.showAchievement(hl.item.key)
        contentItem: Item {
            Row {
                id: hlRow
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                ClippingRectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34
                    radius: 9
                    color: Appearance.colors.colLayer3Accent
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
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    StyledText {
                        text: hl.item.label ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Row {
                        spacing: 6
                        StyledText {
                            width: Math.min(implicitWidth, 200)
                            text: hl.item.value ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            visible: (hl.item.detail ?? "") !== ""
                            text: hl.item.detail ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // ── List ──
    Row {
        id: filterRow
        visible: root.total > 0
        anchors { top: banner.bottom; topMargin: 12; horizontalCenter: banner.horizontalCenter }
        spacing: 4
        Repeater {
            model: [
                // All in the middle, between the two halves of it
                { key: "unlocked", label: Translation.tr("Unlocked") },
                { key: "all", label: Translation.tr("All") },
                { key: "locked", label: Translation.tr("Locked") }
            ]
            SheetFilterChip {
                required property var modelData
                label: modelData.label
                on: root.filter === modelData.key
                onPicked: root.filter = modelData.key
            }
        }
    }
    GridView {
        id: list
        anchors { top: filterRow.bottom; topMargin: 10; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 12 }
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
