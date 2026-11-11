import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

/**
 * A Steam game's achievements in a panel growing up out of the launcher (LauncherTopPanel). Read from
 * the Steam client's own files, or for games it hasn't loaded on this PC from your Steam profile, with each
 * one's share of players (scripts/game-launcher/steam_achievements.py), which also orders them:
 * unlocked newest first, then locked most common first (the easiest next). On top, a banner of the
 * game's art: how far you are as a ring round the latest one's picture (a click away in the list), the
 * percentage and the count, close in its corner and All / Unlocked / Locked in the other. Under it the achievements as joined rows,
 * in two columns to suit the sheet's wide, short shape.
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
    // The latest one unlocked: the banner's picture, and named under the count
    readonly property var latest: (achievementData?.achievements ?? []).filter(a => a.unlocked)
        .reduce((best, a) => !best || a.time > best.time ? a : best, null)
    // An achievement (the banner's latest, tapped), in the list: every one shown, scrolled to it, its card lit for a moment
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

    // ── Banner: the game's art, the latest one in the cover's place, how far you are, the filters ──
    ArtBanner {
        id: banner
        game: root.game
        showCover: false // The ring is there instead
        shadeMid: 0.72; shadeEnd: 0.55
        anchors { top: parent.top; topMargin: 12; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
        height: root.total > 0 ? 112 : 0
        visible: root.total > 0

        Item { // How far, as a ring round the latest one (at its own size: Steam's are 64 px); a click shows it in the list
            id: ring
            readonly property real size: 76
            readonly property real stroke: 5
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            width: size; height: size
            property real shownFraction: root.fraction
            Behavior on shownFraction { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath { // The track
                    strokeColor: Appearance.colors.colLayer4; strokeWidth: ring.stroke; fillColor: "transparent"
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
                width: 50; height: 50; radius: 12
                color: Appearance.colors.colLayer4
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
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.showAchievement(root.latest.id)
            }
        }

        Column { // How far, in words: the percentage big, then the count and the latest as chips
            anchors { left: ring.right; leftMargin: 18; right: parent.right; rightMargin: 70; verticalCenter: parent.verticalCenter }
            spacing: 8
            Row {
                spacing: 8
                StyledText {
                    id: percentText
                    text: root.unlockedCount === root.total ? Translation.tr("All") : `${Math.floor(root.fraction * 100)}%`
                    font.pixelSize: 30
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.baseline: percentText.baseline
                    text: root.unlockedCount === root.total ? Translation.tr("unlocked") : Translation.tr("complete")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
                }
            }
            Row {
                spacing: 6
                BannerChip {
                    iconName: "emoji_events"
                    text: Translation.tr("%1 of %2 unlocked").arg(root.unlockedCount).arg(root.total)
                }
                BannerChip { // The latest: a click shows it in the list
                    visible: root.latest !== null
                    tinted: true
                    picture: root.latest?.icon ?? ""
                    text: root.latest ? Translation.tr("Latest · %1 · %2").arg(root.latest.name).arg(Qt.formatDate(new Date(root.latest.time * 1000), "MMM d")) : ""
                    onClicked: root.showAchievement(root.latest.id)
                }
            }
        }

        Row { // All / Unlocked / Locked, in the banner's bottom corner
            anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 10 }
            spacing: 3
            Repeater {
                model: [
                    { key: "all", label: Translation.tr("All") },
                    { key: "unlocked", label: Translation.tr("Unlocked") },
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
    }

    // A chip on the banner: an icon or a small picture, its text; tinted for the latest (which is a button)
    component BannerChip: RippleButton {
        id: bc
        property string iconName: ""
        property string picture: ""
        property bool tinted: false
        text: ""
        focusPolicy: Qt.NoFocus // (Kept enabled: a disabled button fades its own background out)
        pointingHandCursor: tinted // Only the latest does something
        rippleEnabled: tinted
        implicitWidth: bcRow.implicitWidth + 18
        implicitHeight: 28
        padding: 0
        buttonRadius: 9
        colBackground: tinted ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
        colBackgroundHover: tinted ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3
        colRipple: Appearance.colors.colLayer3AccentHover
        contentItem: Item {
            Row {
                id: bcRow
                anchors.centerIn: parent
                spacing: 6
                ClippingRectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bc.picture !== ""
                    width: 18; height: 18; radius: 5
                    color: Appearance.colors.colLayer4
                    Image { anchors.fill: parent; source: bc.picture; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(36, 36) }
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bc.iconName !== ""
                    text: bc.iconName; iconSize: 15
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bc.text
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: bc.tinted ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    // ── List ──
    GridView {
        id: list
        anchors { top: banner.bottom; topMargin: 12; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 12 }
        cellWidth: Math.floor(width / 2)
        cellHeight: 65 // 62 high, 3 apart
        bottomMargin: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.visibleAchievements
        visible: root.total > 0
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool locked: !modelData.unlocked
            readonly property bool secret: locked && modelData.hidden
            readonly property real percent: modelData.percent ?? -1
            readonly property bool flashing: root.flashId !== "" && root.flashId === modelData.id
            // Each column's rows join into one group (3 px apart, rounded at its top and bottom), as Settings'
            readonly property bool firstRow: index < 2
            readonly property bool lastRow: index + 2 >= list.count
            readonly property bool rare: percent >= 0 && percent < 5 // Under 5% of players: says so
            width: list.cellWidth - 10
            height: list.cellHeight - 3
            topLeftRadius: firstRow ? Appearance.rounding.normal : Appearance.rounding.joined
            topRightRadius: topLeftRadius
            bottomLeftRadius: lastRow ? Appearance.rounding.normal : Appearance.rounding.joined
            bottomRightRadius: bottomLeftRadius
            color: flashing ? Appearance.colors.colLayer3Accent
                : rowHover.hovered ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
            Behavior on color { ColorAnimation { duration: 220 } }
            HoverHandler { id: rowHover }

            ClippingRectangle { // Icon (greyed while locked, a lock for hidden ones)
                id: icon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 46; height: 46
                radius: 10
                color: Appearance.colors.colLayer4
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
                    color: row.locked ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer3
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
            Column { // When you got it, and how many players have it: said once, "Rare" only under 5%
                id: side
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 5
                StyledText {
                    anchors.right: parent.right
                    text: row.locked ? Translation.tr("Locked") : Qt.formatDate(new Date(row.modelData.time * 1000), "MMM d, yyyy")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning
                    color: Appearance.colors.colSubtext
                }
                Rectangle {
                    anchors.right: parent.right
                    visible: row.percent >= 0
                    width: rarityRow.implicitWidth + 14; height: 20; radius: 6
                    color: row.rare ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer4
                    Row {
                        id: rarityRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.rare
                            text: "diamond"; iconSize: 12; fill: 1
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.rare ? Translation.tr("%1% · Rare").arg(root.percentText(row.percent)) : `${root.percentText(row.percent)}%`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: row.rare ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                        }
                    }
                    HoverHandler { id: rarityHover }
                    StyledToolTip { extraVisibleCondition: rarityHover.hovered; text: Translation.tr("%1% of players have it").arg(root.percentText(row.percent)) }
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
