import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

/**
 * A Steam game's achievements in a panel growing up out of the launcher (LauncherTopPanel). Read from the Steam
 * client's own files, or for games it hasn't loaded on this PC from your Steam profile, with each one's share of
 * players and, for ones a game counts up, how far you are (scripts/game-launcher/steam_achievements.py, which also
 * orders them: unlocked newest first, then locked ones you're halfway through, then the rest most common first).
 *
 * On top, the game's art on a smooth edge (GlassEdge, as Captures' and News'): on its left how far you are, a ring
 * round the latest one's picture, the percentage and the count, and the latest and the rarest you have (each a
 * click away in the list); All / Unlocked / Locked with their counts in a glass piece in its bottom-right corner,
 * close in the top one. Under it, in a well (GlassWell), the achievements as rows in two columns: a locked one counted up shows its
 * progress, a hidden one a lock until it's pointed at, one under 5% of players says Rare.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1240
    panelHeight: 640
    clipContent: true

    readonly property var achievementData: GameLauncherService.achievementsFor === (game?.id ?? "") ? GameLauncherService.achievements : null
    readonly property var all: achievementData?.achievements ?? []
    readonly property int total: achievementData?.total ?? 0
    readonly property int unlockedCount: achievementData?.unlocked ?? 0
    property string filter: "all" // all | unlocked | locked
    readonly property var visibleAchievements: all.filter(a => filter === "all" || (filter === "unlocked") === a.unlocked)
    readonly property real fraction: total > 0 ? unlockedCount / total : 0
    function percentText(p) { return p < 1 ? p.toFixed(1) : String(Math.round(p)); }
    // The latest one unlocked (the ring's picture) and the rarest you have
    readonly property var latest: all.filter(a => a.unlocked).reduce((best, a) => !best || a.time > best.time ? a : best, null)
    readonly property var rarest: all.filter(a => a.unlocked && a.percent >= 0).reduce((best, a) => !best || a.percent < best.percent ? a : best, null)
    // "Jul 24", with the year only when it isn't this year's
    function shortDate(seconds) {
        const d = new Date(seconds * 1000);
        return Qt.formatDate(d, d.getFullYear() === new Date().getFullYear() ? "MMM d" : "MMM d, yyyy");
    }
    // An achievement (the latest or the rarest, clicked), in the list: every one shown, scrolled to it, lit a moment
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
            const maxY = list.originY + Math.max(0, list.contentHeight - list.height);
            list.contentY = Math.max(list.originY, Math.min(list.contentY + (key === Qt.Key_Up ? -1 : 1) * list.cellHeight, maxY));
            return true;
        }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the panel
    }

    // ── The art across the top: how far you are on its left, the filter and close in its corners ──
    ArtBanner {
        id: banner
        anchors { top: parent.top; topMargin: 12; left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12 }
        height: 120
        visible: root.total > 0
        game: root.game
        showCover: false // The ring is there instead
        shadeMid: 0.62; shadeEnd: 0.6

        Row {
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            spacing: 16
            Item { // How far, as a ring round the latest one (a click shows it in the list)
                id: ring
                readonly property real size: 68
                readonly property real stroke: 4
                anchors.verticalCenter: parent.verticalCenter
                width: size; height: size
                property real shownFraction: root.fraction
                Behavior on shownFraction { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath { // The track
                        strokeColor: ColorUtils.transparentize("white", 0.82); strokeWidth: ring.stroke; fillColor: "transparent"
                        PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: (ring.size - ring.stroke) / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath { // How far, from the top, clockwise
                        strokeColor: Appearance.colors.colPrimary; strokeWidth: ring.stroke; fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: (ring.size - ring.stroke) / 2; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * ring.shownFraction }
                    }
                }
                ClippingRectangle {
                    anchors.centerIn: parent
                    width: 46; height: 46
                    radius: Appearance.rounding.small
                    color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.4)
                    Image {
                        anchors.fill: parent
                        source: root.latest?.icon ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(64, 64)
                    }
                    MaterialSymbol { // None unlocked yet
                        anchors.centerIn: parent
                        visible: root.latest === null
                        text: "emoji_events"; iconSize: 24
                        color: Appearance.colors.colPrimary
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.latest !== null
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.showAchievement(root.latest.id)
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Row {
                    spacing: 10
                    StyledText {
                        id: percentText
                        text: root.unlockedCount === root.total ? Translation.tr("All") : `${Math.floor(root.fraction * 100)}%`
                        font.pixelSize: 32
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({}) // Not Roboto Flex's tuning
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        anchors.baseline: percentText.baseline
                        text: Translation.tr("%1 of %2 unlocked").arg(root.unlockedCount).arg(root.total)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.25)
                    }
                }
                Row { // The latest and the rarest you have, each a click away in the list
                    spacing: 8
                    visible: root.latest !== null
                    Highlight { label: Translation.tr("Latest"); achievement: root.latest; detail: root.latest ? root.shortDate(root.latest.time) : "" }
                    StyledText {
                        visible: root.rarest !== null && root.rarest.id !== root.latest?.id
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.5)
                    }
                    Highlight {
                        visible: root.rarest !== null && root.rarest.id !== root.latest?.id
                        label: Translation.tr("Rarest"); achievement: root.rarest
                        detail: root.rarest ? `${root.percentText(root.rarest.percent)}%` : ""
                    }
                }
            }
        }
        GlassPiece { // All / Unlocked / Locked with their counts, after a trophy squircle
            anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
            leadIcon: "emoji_events"
            Repeater {
                model: [
                    { key: "all", label: Translation.tr("All"), count: root.total },
                    { key: "unlocked", label: Translation.tr("Unlocked"), count: root.unlockedCount },
                    { key: "locked", label: Translation.tr("Locked"), count: root.total - root.unlockedCount }
                ]
                GlassSegment {
                    required property var modelData
                    label: modelData.label
                    count: modelData.count
                    on: root.filter === modelData.key
                    onPicked: root.filter = modelData.key
                }
            }
        }
        SheetIconButton {
            anchors { top: parent.top; topMargin: 12; right: parent.right; rightMargin: 12 }
            grouped: false
            iconName: "close"
            tip: Translation.tr("Close")
            colBackground: root.glassOverArt
            colBackgroundHover: root.glassOverArtHover
            onClicked: root.closeRequested()
        }
    }
    GlassEdge { anchors.fill: banner; radius: banner.radius; visible: banner.visible }

    // ── The achievements, in a well: two columns of rows ──
    GlassWell {
        id: well
        anchors { top: banner.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 12; left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12 }
        visible: root.total > 0
    }
    GridView {
        id: list
        anchors { fill: well; margins: 6 }
        visible: well.visible
        cellWidth: Math.floor(width / 2)
        cellHeight: 58 // 56 high, 2 apart
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Its edges fade into the well while there's more to scroll to (only then: no layer otherwise)
        layer.enabled: !(atYBeginning && atYEnd)
        layer.effect: ScrollFadeMask { topActive: !list.atYBeginning; bottomActive: !list.atYEnd }
        model: root.visibleAchievements
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: list.cellWidth; height: list.cellHeight
            Rectangle {
                id: row
                readonly property bool locked: !cell.modelData.unlocked
                readonly property bool hidden: locked && cell.modelData.hidden && !rowHover.hovered // Shown while pointed at
                readonly property bool revealed: locked && cell.modelData.hidden && rowHover.hovered
                readonly property real percent: cell.modelData.percent ?? -1
                readonly property bool rare: percent >= 0 && percent < 5 // Under 5% of players: says so
                readonly property bool counted: locked && (cell.modelData.max ?? 0) > 0
                readonly property bool flashing: root.flashId !== "" && root.flashId === cell.modelData.id
                // 6 px between the columns
                x: cell.index % 2 === 1 ? 6 : 0
                width: cell.width - 6; height: cell.height - 2
                radius: Appearance.rounding.small
                color: flashing ? Appearance.colors.colLayer3Accent
                    : rowHover.hovered ? ColorUtils.transparentize("white", 0.95) : ColorUtils.transparentize("white", 1)
                Behavior on color { ColorAnimation { duration: 220 } }
                HoverHandler { id: rowHover }

                ClippingRectangle { // Its picture (greyed while locked, a lock while hidden)
                    id: icon
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40
                    radius: Appearance.rounding.segment
                    color: ColorUtils.transparentize("white", 0.94)
                    Image {
                        anchors.fill: parent
                        visible: !row.hidden
                        source: row.hidden ? "" : row.locked ? cell.modelData.iconGray : cell.modelData.icon
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 80
                        opacity: row.locked ? 0.55 : 1
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: row.hidden
                        text: "lock"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
                Column {
                    id: rowText
                    anchors { left: icon.right; leftMargin: 12; right: side.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Row {
                        width: parent.width
                        spacing: 6
                        StyledText {
                            id: rowName
                            width: Math.min(implicitWidth, parent.width - (row.revealed ? 22 : 0))
                            text: row.hidden ? Translation.tr("Hidden achievement") : cell.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smallie + 1
                            font.weight: Font.DemiBold
                            color: row.locked && !rowHover.hovered ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3) : Appearance.colors.colOnLayer0
                            elide: Text.ElideRight
                        }
                        MaterialSymbol { // Hidden, shown while pointed at
                            anchors.verticalCenter: rowName.verticalCenter
                            visible: row.revealed
                            text: "visibility"; iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledText {
                        width: parent.width
                        text: row.hidden ? Translation.tr("Point at it to see it (a spoiler)") : cell.modelData.description
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
                Item { // The hover line, under the name
                    x: rowText.x
                    y: rowText.y + rowName.height + 1
                    width: rowName.width
                    height: 2
                    HoverLine { inset: 0; anchors.bottomMargin: 0; shown: rowHover.hovered && !row.flashing }
                }
                Column { // When you got it and how many have it; how far a counted one is; else how many have it
                    id: side
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: row.counted ? 110 : implicitWidth
                    spacing: 5
                    StyledText {
                        anchors.right: parent.right
                        visible: !row.locked
                        text: Qt.formatDate(new Date(cell.modelData.time * 1000), "MMM d, yyyy")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({})
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        anchors.right: parent.right
                        visible: row.counted
                        text: `${cell.modelData.current ?? 0} / ${cell.modelData.max ?? 0}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({})
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                    Rectangle { // How far a counted one is
                        anchors.right: parent.right
                        visible: row.counted
                        width: 110; height: 4
                        radius: 2
                        color: ColorUtils.transparentize("white", 0.9)
                        Rectangle {
                            width: parent.width * Math.min(1, (cell.modelData.current ?? 0) / Math.max(1, cell.modelData.max ?? 1))
                            height: parent.height
                            radius: 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                    Row { // How many players have it, "Rare" under 5%
                        anchors.right: parent.right
                        visible: !row.counted && row.percent >= 0
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.rare
                            text: "diamond"; iconSize: 12; fill: 1
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: row.rare ? Translation.tr("%1% · Rare").arg(root.percentText(row.percent)) : `${root.percentText(row.percent)}%`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: row.rare ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.2)
                        }
                        HoverHandler { id: shareHover }
                        StyledToolTip { extraVisibleCondition: shareHover.hovered; text: Translation.tr("%1% of players have it").arg(root.percentText(row.percent)) }
                    }
                }
            }
        }
    }

    StyledText { // A filter with none under it (a game you have them all of, or none yet)
        anchors.centerIn: well
        visible: well.visible && root.visibleAchievements.length === 0
        text: root.filter === "locked" ? Translation.tr("You have every one") : Translation.tr("None unlocked yet")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
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

    // The latest or the rarest on the art: what it is (quiet), its name, a detail; a click shows it in the list
    component Highlight: Row {
        id: hl
        property string label
        property var achievement: null
        property string detail
        spacing: 5
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: hl.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
        }
        StyledText {
            id: hlName
            anchors.verticalCenter: parent.verticalCenter
            text: hl.achievement ? `${hl.achievement.name}, ${hl.detail}` : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
            HoverHandler { id: hlHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (hl.achievement) root.showAchievement(hl.achievement.id) }
            HoverLine { inset: 0; anchors.bottomMargin: -3; shown: hlHover.hovered }
        }
    }
}
