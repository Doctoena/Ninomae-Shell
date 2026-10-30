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
 * unlocked newest first, then locked most common first (the easiest next). Two columns, to suit
 * the sheet's wide, short shape.
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
        subtitle: root.total > 0 ? Translation.tr("%1 · %2 of %3 · %4%").arg(root.game?.name ?? "").arg(root.unlockedCount).arg(root.total).arg(Math.round(progress.fraction * 100))
            : (root.game?.name ?? "")
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

    // ── Progress (the percentage is in the header's subtitle) ──
    Rectangle {
        id: progress
        anchors { top: header.bottom; topMargin: 14; left: parent.left; right: parent.right; leftMargin: 22; rightMargin: 22 }
        height: root.total > 0 ? 4 : 0
        radius: 2
        visible: root.total > 0
        color: Appearance.colors.colLayer1
        readonly property real fraction: root.total > 0 ? root.unlockedCount / root.total : 0
        Rectangle {
            width: parent.width * progress.fraction
            height: parent.height; radius: parent.radius
            color: Appearance.colors.colPrimary
            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        }
    }

    // ── List ──
    GridView {
        id: list
        anchors { top: progress.bottom; topMargin: 8; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
        cellWidth: Math.floor(width / 2)
        cellHeight: 66
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
            width: list.cellWidth - 4
            height: list.cellHeight - 2
            radius: Appearance.rounding.normal
            color: rowHover.hovered ? Appearance.colors.colLayer1 : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: rowHover }

            ClippingRectangle { // Icon (greyed while locked, a lock for hidden ones)
                id: icon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 46; height: 46
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
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
                StyledText {
                    anchors.right: parent.right
                    visible: row.percent >= 0
                    text: Translation.tr("%1% of players").arg(row.percent < 1 ? row.percent.toFixed(1) : Math.round(row.percent))
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
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
