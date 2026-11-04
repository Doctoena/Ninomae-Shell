import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

/**
 * Steam's downloads, without Steam's window: a panel growing up out of the launcher (LauncherTopPanel),
 * from the toolbar's download button or a game's Play button while it downloads.
 *  - On top, the download that's going (or the one Steam stopped or holds): a banner of its art, with how
 *    far it is, its live speed and a graph of the last minute's, the time left, and pause or resume.
 *  - Under it, Up next (queued, scheduled, and updates that wait for the game to be played) and Stopped,
 *    each with "Download now" (Steam's "Move to top", which starts it and puts the rest after it).
 *  - The ✕ beside an update takes it off the queue, as Steam's: it updates later, or when it's played.
 *  - Then what finished in the last day, with Play. Its ✕ (or the heading's Clear all) takes it off the panel
 *    (GameLauncherService.clearFinishedDownloads), until it finishes again. A row opens its game's page.
 * The buttons go through the shell's Millennium plugin in Steam (GameLauncherService.controlDownload), else
 * they open Steam's Downloads page, and a notice says how to get it. From GameLauncherService.steamDownloads
 * (scripts/game-launcher/steam_downloads.py --watch). Esc closes.
 */
LauncherTopPanel {
    id: root
    panelWidth: 1100 // As wide as the Tags panel
    panelHeight: 440
    signal openGame(var game)

    onShownChanged: if (shown) keys.forceActiveFocus()
    function handleKey(key, modifiers) { // From the details page, which keeps the keys while it's open
        if (key !== Qt.Key_Escape) return false;
        root.closeRequested();
        return true;
    }

    readonly property var data: GameLauncherService.steamDownloads
    readonly property var items: GameLauncherService.downloadItems // The feed's, with what was removed here as waiting
    // The banner's: the one downloading, else the first Steam stopped or holds
    readonly property var featured: items.find(i => i.state === "downloading")
        ?? items.find(i => ["error", "suspended", "paused"].includes(i.state)) ?? null
    // The sections' rows. Set only when what they show changes: the feed sends a new speed every second while
    // something downloads, and a new list each time would rebuild every row (and reload its cover) with it
    property var upNext: []
    property var stopped: []
    property var finished: []
    function _sections() {
        const set = (key, rows) => { if (JSON.stringify(rows) !== JSON.stringify(root[key])) root[key] = rows; };
        const featuredId = root.featured?.appid;
        // Waiting for a game to be played means nothing for Steam's runtimes and redistributables: those wait out of sight
        set("upNext", items.filter(i => i.appid !== featuredId && ["queued", "scheduled", "waiting"].includes(i.state)
            && (i.state !== "waiting" || root.gameFor(i.appid))));
        set("stopped", items.filter(i => i.appid !== featuredId && ["paused", "error", "suspended", "stopped"].includes(i.state)));
        set("finished", GameLauncherService.finishedDownloads.filter(f => root.gameFor(f.appid))); // Not Steam's runtimes
    }
    onItemsChanged: _sections()
    Connections {
        target: GameLauncherService
        function onFinishedDownloadsChanged() { root._sections(); }
    }
    Component.onCompleted: _sections()
    readonly property bool canControl: GameLauncherService.canControlDownloads
    // Nothing to show: no banner and no rows (Steam's runtimes waiting to be played are left out of Up next)
    readonly property bool empty: featured === null && upNext.length + stopped.length + finished.length === 0
    // The time, a minute at a time while it's open: "starts in 5 min" and "2 min ago" count on without a change
    // from the feed
    property real now: Date.now() / 1000
    Timer {
        interval: 60000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now() / 1000
    }

    function gameFor(appid) { return GameLauncherService._installedGamesMap["steam_" + appid] ?? null; }
    function busy(appid) { // A button pressed for it, or for the whole queue, that Steam hasn't answered yet
        const pending = GameLauncherService.downloadControlPending;
        return !!pending[appid] || !!pending["all"];
    }
    function size(bytes) {
        return bytes >= 1e9 ? (bytes / 1e9).toFixed(1) + " GB"
            : bytes >= 1e6 ? Math.round(bytes / 1e6) + " MB" : Math.max(0, Math.round(bytes / 1e3)) + " KB";
    }
    function duration(secs) {
        if (secs < 60) return Translation.tr("less than a minute");
        const m = Math.round(secs / 60);
        if (m < 60) return Translation.tr("%1 min").arg(m);
        const h = Math.floor(m / 60);
        if (h < 48) return m % 60 > 0 && h < 10 ? Translation.tr("%1 h %2 min").arg(h).arg(m % 60) : Translation.tr("%1 h").arg(h);
        return Translation.tr("%1 days").arg(Math.round(h / 24));
    }
    function amount(row) { // "4.2 GB of 15.2 GB", or just the size
        if (!(row.toDownload > 0)) return "";
        return row.progress >= 0 ? Translation.tr("%1 of %2").arg(size(row.toDownload * row.progress)).arg(size(row.toDownload)) : size(row.toDownload);
    }
    function statusText(row) {
        const verb = row.installing ? Translation.tr("Installing") : Translation.tr("Updating");
        const join = parts => parts.filter(s => s).join(" · ");
        switch (row.state) {
        case "downloading": return join([verb, amount(row), row.eta >= 0 ? Translation.tr("%1 left").arg(duration(row.eta)) : ""]);
        case "queued": return join([Translation.tr("Queued"), amount(row)]);
        case "paused": return join([Translation.tr("Paused"), amount(row)]);
        case "error": return Translation.tr("Steam stopped it: %1").arg((row.error || Translation.tr("an error")).toLowerCase());
        case "suspended": return join([data.gameRunning ? Translation.tr("Held while you play") : Translation.tr("Paused"), amount(row)]);
        case "scheduled": return Translation.tr("Steam starts it in %1").arg(duration(Math.max(0, row.delayUntil - root.now)));
        case "waiting": return Translation.tr("Updates when you play it");
        case "stopped": return join([Translation.tr("Waiting for Steam to start"), amount(row)]);
        }
        return "";
    }
    function ago(at) {
        const secs = root.now - at;
        return secs < 60 ? Translation.tr("just now") : Translation.tr("%1 ago").arg(duration(secs));
    }
    // A row's button, as Steam's Downloads page: the one downloading pauses the queue (and resumes it once
    // it's paused); any other moves to the top and starts, which is also the retry after an error
    function actionFor(row) {
        switch (row?.state) {
        case "downloading": return { verb: "pause-all", icon: "pause", tip: Translation.tr("Pause downloads"), primary: false };
        case "suspended":
            return data.gameRunning ? { verb: "resume", icon: "download", tip: Translation.tr("Download now, while you play"), primary: true }
                : { verb: "resume-all", icon: "play_arrow", tip: Translation.tr("Resume downloads"), primary: true };
        case "error": return { verb: "resume", icon: "refresh", tip: Translation.tr("Try again"), primary: true };
        case "paused": return { verb: "resume", icon: "play_arrow", tip: Translation.tr("Resume"), primary: true };
        case "queued": case "scheduled": case "waiting":
            return { verb: "resume", icon: "download", tip: Translation.tr("Download now"), primary: false };
        }
        return null;
    }

    Item { // Takes the keys while it's open from the grid (the search bar has them otherwise)
        id: keys
        focus: true
        Keys.onPressed: event => { if (root.handleKey(event.key, event.modifiers)) event.accepted = true; }
    }

    SheetHeader {
        id: header
        icon: "download"
        title: Translation.tr("Downloads")
        subtitle: {
            const active = GameLauncherService.activeDownloads.length;
            if (!root.data.steamRunning && root.items.length > 0) return Translation.tr("Steam isn't running");
            if (root.data.queuePaused) return Translation.tr("Paused");
            if (root.data.rate > 0) return Translation.tr("Downloading at %1/s").arg(root.size(root.data.rate));
            if (root.data.gameRunning && root.items.some(i => i.state === "suspended")) return Translation.tr("Held while you play");
            if (active > 0) return active === 1 ? Translation.tr("1 download") : Translation.tr("%1 downloads").arg(active);
            return Translation.tr("Nothing downloading");
        }
        onCloseRequested: root.closeRequested()
        SheetIconButton {
            iconName: "open_in_new"
            tip: Translation.tr("Open Steam's Downloads page")
            onClicked: GameLauncherService.openDownloads()
        }
    }

    Flickable {
        id: scroller
        anchors { top: header.bottom; topMargin: 14; bottom: parent.bottom; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16 }
        contentHeight: column.height + 14
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: column
            width: scroller.width
            spacing: 8

            Rectangle { // Without the plugin, the buttons can't reach Steam: say so, and how to get it
                width: parent.width
                height: 44
                visible: !root.canControl && !root.empty && (root.data.steamRunning ?? false)
                radius: Appearance.rounding.normal
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                MaterialSymbol {
                    id: offIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "info"; iconSize: 18; color: Appearance.colors.colPrimary
                }
                StyledText {
                    anchors { left: offIcon.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: Translation.tr("To pause, resume or pick what downloads first from here, Steam needs Millennium and the Ninomae plugin. Run ninomae update to set them up.")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }

            // ── The banner: the download that's going, or the one stopped ──
            ClippingRectangle {
                id: banner
                readonly property var row: root.featured
                readonly property var game: root.gameFor(row?.appid)
                readonly property bool live: row?.state === "downloading"
                readonly property bool failed: row?.state === "error"
                readonly property string hero: GameLauncherService.bannerArt(game) // Else the cover, blurred
                readonly property string cover: GameLauncherService.localArt(game, "boxArt")
                width: parent.width
                height: 118
                visible: row !== null
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                Image { // The art: sharp hero art, else the cover blurred
                    anchors.fill: parent
                    source: banner.hero || banner.cover
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: banner.hero ? Math.ceil(banner.width * Screen.devicePixelRatio) : 240
                    visible: status === Image.Ready
                    layer.enabled: visible && !banner.hero
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32; saturation: 0.35 }
                }
                Rectangle { // Shade for the text, darkest behind it (the background colour can be translucent: made solid)
                    id: shade
                    anchors.fill: parent
                    readonly property color base: Appearance.m3colors.m3background
                    function at(a) { return Qt.rgba(base.r, base.g, base.b, a); }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: shade.at(0.9) }
                        GradientStop { position: 0.55; color: shade.at(0.8) }
                        GradientStop { position: 1.0; color: shade.at(0.62) }
                    }
                }
                TapHandler { enabled: !!banner.game; onTapped: root.openGame(banner.game) }
                HoverHandler { cursorShape: banner.game ? Qt.PointingHandCursor : Qt.ArrowCursor }

                ClippingRectangle {
                    id: bannerCover
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    width: 63; height: 84
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    Image {
                        anchors.fill: parent
                        source: banner.cover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(126, 168)
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: banner.cover === ""
                        text: banner.game ? "sports_esports" : "build"
                        iconSize: 24
                        color: Appearance.colors.colPrimary
                    }
                }

                Column {
                    anchors { left: bannerCover.right; leftMargin: 16; right: bannerSide.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    StyledText {
                        width: parent.width
                        text: banner.game?.name ?? banner.row?.name ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        width: parent.width
                        text: banner.row ? root.statusText(banner.row) : ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: banner.failed ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.2)
                    }
                    Item { // Progress, with the percentage at its end
                        width: parent.width
                        height: 16
                        visible: (banner.row?.progress ?? -1) >= 0
                        Rectangle {
                            id: bannerTrack
                            anchors { left: parent.left; right: percent.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            height: 6; radius: 3
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.84)
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, banner.row?.progress ?? 0))
                                height: parent.height; radius: parent.radius
                                color: banner.failed ? Appearance.colors.colError
                                    : banner.live ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
                                Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                            }
                        }
                        StyledText {
                            id: percent
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: `${Math.floor((banner.row?.progress ?? 0) * 100)}%`
                            font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                Row { // The speed and its graph while it downloads, then its button
                    id: bannerSide
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 16
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: banner.live && root.data.rate > 0
                        spacing: 4
                        StyledText {
                            anchors.right: parent.right
                            text: root.size(root.data.rate) + "/s"
                            font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: Appearance.colors.colOnLayer0
                        }
                        SpeedGraph {
                            width: 160; height: 30
                            samples: root.data.history ?? []
                        }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        RemoveButton { row: banner.row; headOfQueue: true; large: true }
                        ActionButton { row: banner.row; large: true }
                    }
                }
            }

            // ── Up next, then stopped, then finished ──
            Section { title: Translation.tr("Up next"); rows: root.upNext }
            Section { title: Translation.tr("Stopped"); rows: root.stopped }
            Section {
                title: Translation.tr("Finished today")
                rows: root.finished
                finishedRows: true
                clearable: true
            }
        }
    }

    SheetEmptyState {
        anchors { centerIn: parent; verticalCenterOffset: 20 }
        visible: root.empty
        icon: "download_done"
        text: Translation.tr("Nothing downloading")
        hint: Translation.tr("Installs and updates show here while Steam downloads them")
    }

    // A heading and its rows, hidden when there are none
    component Section: Column {
        id: section
        property string title
        property var rows: []
        property bool finishedRows: false
        property bool clearable: false // A "Clear all" by the heading (finished rows)
        width: parent.width
        spacing: 6
        visible: rows.length > 0
        topPadding: 4
        Item {
            width: section.width
            height: 22
            StyledText {
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                text: section.title
                font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
            RippleButton {
                id: clearAll
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: section.clearable && section.rows.length > 1
                height: 22; implicitWidth: clearLabel.implicitWidth + 16; padding: 0
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: GameLauncherService.clearFinishedDownloads(section.rows)
                contentItem: StyledText {
                    id: clearLabel
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Clear all")
                    font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                    color: clearAll.hovered ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
            }
        }
        Repeater {
            model: section.rows
            delegate: DownloadRow {
                required property var modelData
                width: section.width
                row: modelData
                finishedRow: section.finishedRows
            }
        }
    }

    component DownloadRow: Rectangle {
        id: rowItem
        property var row: ({})
        property bool finishedRow: false
        readonly property var game: root.gameFor(row.appid)
        readonly property string cover: GameLauncherService.localArt(game, "boxArt")
        height: 54
        radius: Appearance.rounding.normal
        color: rowHover.hovered && game ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: rowHover; cursorShape: rowItem.game ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: !!rowItem.game; onTapped: root.openGame(rowItem.game) }

        ClippingRectangle { // The cover, else a tile with an icon (Steam's runtimes and Proton have no art)
            id: rowCover
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width: 30; height: 40
            radius: Appearance.rounding.small - 2
            color: Appearance.colors.colLayer2
            Image {
                anchors.fill: parent
                source: rowItem.cover
                sourceSize: Qt.size(60, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: rowItem.cover === ""
                text: rowItem.game ? "sports_esports" : "build"
                iconSize: 16
                color: Appearance.colors.colPrimary
            }
        }
        Column {
            anchors { left: rowCover.right; leftMargin: 12; right: rowSide.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            StyledText {
                width: parent.width
                text: rowItem.game?.name ?? rowItem.row.name ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                width: parent.width
                text: rowItem.finishedRow ? Translation.tr("Ready to play · %1").arg(root.ago(rowItem.row.at)) : root.statusText(rowItem.row)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: rowItem.row.state === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }
        Row {
            id: rowSide
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            RemoveButton { visible: !rowItem.finishedRow && removable; row: rowItem.row }
            SquircleButton { // Off the panel (not Steam's: only the launcher's list)
                visible: rowItem.finishedRow
                symbol: "close"
                danger: true
                tip: Translation.tr("Clear from the list")
                onClicked: GameLauncherService.clearFinishedDownloads([rowItem.row])
            }
            ActionButton { visible: !rowItem.finishedRow && act !== null; row: rowItem.row }
            DialogButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: rowItem.finishedRow && !!rowItem.game?.launchCommand
                buttonText: Translation.tr("Play")
                primary: true
                onClicked: {
                    GameLauncherService.launchGame(rowItem.game, GameLauncherService.lastLaunchOption[rowItem.game.id] ?? -1);
                    GlobalStates.gameLauncherOpen = false;
                }
            }
        }
    }

    // Pause, resume, download now or try again (root.actionFor): the accent squircle when it starts something
    component ActionButton: SquircleButton {
        property var row: null
        readonly property var act: root.actionFor(row)
        visible: act !== null
        enabled: !root.busy(row?.appid)
        primary: act?.primary ?? false
        symbol: enabled ? act?.icon ?? "" : "more_horiz"
        tip: (act?.tip ?? "") + (root.canControl ? "" : Translation.tr(" (opens Steam)"))
        onClicked: GameLauncherService.controlDownload(act.verb, act.verb === "resume" ? row.appid : undefined)
    }

    // A row's button: a neutral squircle (the accent one when primary), red on hover when it removes
    component SquircleButton: RippleButton {
        id: squircle
        property string symbol
        property string tip
        property bool large: false
        property bool primary: false
        property bool danger: false
        anchors.verticalCenter: parent?.verticalCenter
        width: large ? 40 : 34; height: width; padding: 0
        buttonRadius: Appearance.rounding.small
        colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover
            : danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.8) : Appearance.colors.colLayer2Hover
        colRipple: primary ? Appearance.colors.colPrimaryActive
            : danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.7) : Appearance.colors.colLayer2Active
        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: squircle.symbol
                iconSize: squircle.large ? 22 : 20
                fill: 1
                color: squircle.primary ? Appearance.colors.colOnPrimary
                    : squircle.danger && squircle.hovered ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
        StyledToolTip { text: squircle.tip }
    }

    // Off the queue, as Steam's ✕: updates only (not ones that already wait for the game to be played). An
    // install that isn't finished can't leave: Steam puts it straight back, paused. For the download at the
    // queue's head while the queue is paused, the rest then go again (as Steam does)
    component RemoveButton: SquircleButton {
        property var row: null
        property bool headOfQueue: false
        readonly property bool removable: !(row?.installing ?? true)
            && ["downloading", "queued", "scheduled", "paused", "error", "suspended"].includes(row?.state ?? "")
        visible: removable
        enabled: !root.busy(row?.appid)
        symbol: "close"
        danger: true
        tip: Translation.tr("Remove from the queue") + (root.canControl ? "" : Translation.tr(" (opens Steam)"))
        onClicked: GameLauncherService.controlDownload(headOfQueue && root.data.queuePaused ? "remove-and-resume" : "remove", row.appid)
    }

    // The last minute's speed, as a filled line: redrawn only when a new sample comes in
    component SpeedGraph: Canvas {
        id: graph
        property var samples: []
        onSamplesChanged: requestPaint()
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = samples.length;
            if (n < 2) return;
            const max = Math.max(...samples) || 1;
            const step = width / (n - 1);
            const y = v => height - 2 - (v / max) * (height - 4);
            ctx.beginPath();
            ctx.moveTo(0, y(samples[0]));
            for (let i = 1; i < n; i++) ctx.lineTo(i * step, y(samples[i]));
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = Appearance.colors.colPrimary;
            ctx.stroke();
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fillStyle = ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8);
            ctx.fill();
        }
    }
}
