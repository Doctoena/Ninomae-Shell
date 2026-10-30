pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings → Display. Your screens drawn to scale: drag them to match your desk (they snap edge to
// edge), click one to change its resolution, refresh rate, scale, rotation, VRR, turn it off or make it
// mirror another. Saved by monitor description in displays.json (Directories.displaysPath), so a monitor
// keeps its settings on any machine, and applied live by services/DeviceSettings.qml over
// hypr/hyprland/monitors.lua (one rule for every screen). Changes that could leave a screen unusable
// ask to be kept and go back on their own after 15 seconds, like GNOME and KDE.
ContentPage {
    id: page
    // Saved settings: { "<monitor description>": { mode, scale, transform, vrr, position, disabled, mirror } }
    property var saved: ({})
    FileView {
        id: displaysFile
        path: Qt.resolvedUrl(Directories.displaysPath)
        onLoaded: {
            try { page.saved = JSON.parse(displaysFile.text()) ?? {}; } catch (e) { page.saved = {}; }
        }
    }

    // Live monitor state ("all": the ones that are off too), re-read after changes and when Hyprland's monitors change
    property var monitors: []
    function refresh() { monitorsProc.running = true; }
    Process {
        id: monitorsProc
        running: true
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.monitors = JSON.parse(text); } catch (e) { return; }
                page.placed = ({}); // Hyprland has the new layout now: draw that
            }
        }
    }
    Timer { id: refreshLater; interval: 1200; onTriggered: page.refresh() }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name.startsWith("monitor") || event.name === "configreloaded") refreshLater.restart();
        }
    }

    function isMirror(m) { return !!m.mirrorOf && m.mirrorOf !== "none"; }
    function label(m) { return m.name.startsWith("eDP") ? Translation.tr("Built-in display") : (m.model || m.description || m.name); }
    function byName(name) { return page.monitors.find(o => o.name === name); }
    // The screens in the layout: on, and not showing another's picture
    readonly property var arranged: monitors.filter(m => !m.disabled && !isMirror(m))
    readonly property int onCount: monitors.filter(m => !m.disabled).length
    property string selectedDescription: ""
    readonly property var selected: monitors.find(m => m.description === selectedDescription)
        ?? monitors.find(m => m.focused) ?? monitors[0]

    // ── Layout ──
    // Positions just dropped, until Hyprland reports them: { "<description>": { x, y } }
    property var placed: ({})
    // Each arranged screen as Hyprland lays it out: logical pixels (scaled, rotated)
    readonly property var layoutRects: arranged.map(m => {
        const turned = m.transform % 2 === 1;
        const p = placed[m.description];
        return {
            desc: m.description, monitor: m,
            x: p ? p.x : m.x, y: p ? p.y : m.y,
            w: Math.round((turned ? m.height : m.width) / m.scale),
            h: Math.round((turned ? m.width : m.height) / m.scale),
        };
    })
    // A screen dropped at (x, y): put it against the nearest edge of another (overlapping none),
    // lined up with that one's side or middle when close, then save every screen's position
    function placeMonitor(desc, x, y, snap) {
        const rects = page.layoutRects;
        const d = rects.find(r => r.desc === desc);
        const others = rects.filter(r => r.desc !== desc);
        if (!d || others.length === 0) return;
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const lineUp = (v, targets) => { // The closest target within `snap`, or v as it is
            let best = v, bestDistance = snap;
            for (const t of targets) if (Math.abs(v - t) < bestDistance) { best = t; bestDistance = Math.abs(v - t); }
            return best;
        };
        const overlaps = c => others.some(o => c.x < o.x + o.w && o.x < c.x + d.w && c.y < o.y + o.h && o.y < c.y + d.h);
        let best = null;
        for (const o of others) {
            const alongY = () => lineUp(clamp(y, o.y - d.h + 1, o.y + o.h - 1), [o.y, o.y + o.h - d.h, o.y + (o.h - d.h) / 2]);
            const alongX = () => lineUp(clamp(x, o.x - d.w + 1, o.x + o.w - 1), [o.x, o.x + o.w - d.w, o.x + (o.w - d.w) / 2]);
            const candidates = [
                { x: o.x + o.w, y: alongY() }, // Right of it
                { x: o.x - d.w, y: alongY() }, // Left
                { x: alongX(), y: o.y + o.h }, // Below
                { x: alongX(), y: o.y - d.h }, // Above
            ];
            for (const c of candidates) {
                if (overlaps(c)) continue;
                const distance = Math.hypot(c.x - x, c.y - y);
                if (!best || distance < best.distance) best = { x: c.x, y: c.y, distance };
            }
        }
        if (!best) return;
        // Everyone's new place, moved so the layout starts at 0,0
        const next = rects.map(r => r.desc === desc ? { desc: r.desc, x: best.x, y: best.y } : { desc: r.desc, x: r.x, y: r.y });
        const minX = Math.min(...next.map(r => r.x)), minY = Math.min(...next.map(r => r.y));
        const changes = {}, placedNow = {};
        let moved = false;
        for (const r of next) {
            const px = Math.round(r.x - minX), py = Math.round(r.y - minY);
            const old = rects.find(o => o.desc === r.desc);
            if (px !== old.x || py !== old.y) moved = true;
            placedNow[r.desc] = { x: px, y: py };
            changes[r.desc] = { position: `${px}x${py}` };
        }
        page.placed = placedNow;
        if (moved) page.changeMany(changes, true);
    }

    // ── Changing, confirming, reverting ──
    property bool pending: false // A change waiting for "Keep"
    property var previousSaved: ({}) // Everything saved before it
    property int countdown: 0
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: if (--page.countdown <= 0) page.revert()
    }
    // fields: { field: value }, undefined to forget one. Forgetting needs a Hyprland reload, so the
    // field returns to monitors.lua's value (the shell re-applies the saved ones after it)
    function change(description, fields, needsConfirm) { page.changeMany({ [description]: fields }, needsConfirm); }
    function changeMany(byDescription, needsConfirm) {
        if (needsConfirm) {
            if (!page.pending) {
                page.previousSaved = JSON.parse(JSON.stringify(page.saved));
                page.pending = true;
            }
            page.countdown = 15;
            countdownTimer.restart();
        }
        const all = JSON.parse(JSON.stringify(page.saved));
        let forgot = false;
        for (const [description, fields] of Object.entries(byDescription)) {
            const entry = Object.assign({}, all[description] ?? {});
            for (const [field, value] of Object.entries(fields)) {
                if (value === undefined) { if (field in entry) forgot = true; delete entry[field]; }
                else entry[field] = value;
            }
            if (Object.keys(entry).length > 0) all[description] = entry;
            else delete all[description];
        }
        page.writeSaved(all, forgot);
    }
    // Written (and reloaded) by a detached shell, so it still completes when Settings is closing
    function writeSaved(all, reload) {
        page.saved = all;
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2.tmp" && mv -f "$2.tmp" "$2"' + (reload ? " && sleep 0.3 && hyprctl reload" : ""),
            "save-displays", JSON.stringify(all, null, 2), Directories.displaysPath]);
        refreshLater.restart();
    }
    function keep() {
        countdownTimer.stop();
        page.pending = false;
    }
    function revert() {
        countdownTimer.stop();
        page.pending = false;
        page.placed = ({});
        page.writeSaved(page.previousSaved, true);
    }
    function forget(description) {
        page.keep(); // What else was waiting counts as kept
        const all = JSON.parse(JSON.stringify(page.saved));
        delete all[description];
        page.writeSaved(all, true);
    }
    // Closing Settings (or leaving the page) while a change waits counts as "Revert", as in GNOME and KDE:
    // the screen may be unreadable, which is why it asked
    Component.onDestruction: if (page.pending) page.revert()

    // ── Confirmation bar ──
    Rectangle {
        visible: page.pending
        Layout.fillWidth: true
        implicitHeight: confirmRow.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        RowLayout {
            id: confirmRow
            anchors { fill: parent; margins: 12 }
            spacing: 10
            QuickDialogIcon {
                icon: "timer"
                active: true
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("Keep these display settings? Going back in %1 s").arg(page.countdown)
                color: Appearance.colors.colOnLayer2
            }
            RippleButtonWithIcon {
                materialIcon: "undo"
                mainText: Translation.tr("Revert")
                onClicked: page.revert()
            }
            RippleButtonWithIcon {
                materialIcon: "check"
                mainText: Translation.tr("Keep")
                onClicked: page.keep()
            }
        }
    }

    // ── The screens, to scale ──
    ContentSection {
        icon: "dashboard"
        title: page.monitors.length > 1 ? Translation.tr("Arrangement") : Translation.tr("Your screen")
        spacing: 10

        Rectangle {
            id: arrangement
            Layout.fillWidth: true
            implicitHeight: 240
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            readonly property bool canDrag: page.layoutRects.length > 1
            readonly property real minX: Math.min(...page.layoutRects.map(r => r.x))
            readonly property real minY: Math.min(...page.layoutRects.map(r => r.y))
            readonly property real spanX: Math.max(1, Math.max(...page.layoutRects.map(r => r.x + r.w)) - minX)
            readonly property real spanY: Math.max(1, Math.max(...page.layoutRects.map(r => r.y + r.h)) - minY)
            // Room around the layout to drag a screen to any side of the others
            readonly property real margin: canDrag ? 40 : 24
            readonly property real factor: Math.min((width - margin * 2) / spanX, (height - margin * 2) / spanY)
            readonly property real offsetX: (width - spanX * factor) / 2
            readonly property real offsetY: (height - spanY * factor) / 2
            readonly property string picture: /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.wallpaperPath) ? Config.thumbnailPath : Config.wallpaperPath

            Repeater {
                model: page.layoutRects
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property var r: modelData
                    readonly property bool chosen: page.selected !== undefined && page.selected.description === r.desc
                    readonly property bool dragging: tileMouse.drag.active
                    function homeX() { return arrangement.offsetX + (r.x - arrangement.minX) * arrangement.factor; }
                    function homeY() { return arrangement.offsetY + (r.y - arrangement.minY) * arrangement.factor; }
                    x: homeX()
                    y: homeY()
                    width: r.w * arrangement.factor
                    height: r.h * arrangement.factor
                    z: dragging ? 10 : chosen ? 2 : 1
                    Behavior on x { enabled: !tile.dragging; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: !tile.dragging; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Rectangle {
                        id: tileFrame
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer3
                        border.width: tile.chosen ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        scale: tileMouse.pressed ? 0.98 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        ClippingRectangle {
                            anchors { fill: parent; margins: 3 }
                            radius: Math.max(2, tileFrame.radius - 3)
                            color: Appearance.colors.colLayer1
                            StyledImage {
                                anchors.fill: parent
                                source: arrangement.picture
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 400
                                asynchronous: true
                                opacity: tile.chosen ? 1 : 0.5
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                            }
                        }
                        Rectangle { // Its name
                            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                            width: Math.min(tileLabel.implicitWidth + 16, parent.width - 16)
                            height: tileLabel.implicitHeight + 8
                            radius: Appearance.rounding.segment
                            color: tile.chosen ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                            visible: tile.height > 40
                            RowLayout {
                                id: tileLabel
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - 16)
                                spacing: 4
                                MaterialSymbol {
                                    text: tile.r.monitor.name.startsWith("eDP") ? "laptop" : "monitor"
                                    iconSize: 14
                                    color: tile.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: page.label(tile.r.monitor)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: tile.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        cursorShape: arrangement.canDrag ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                        drag.target: arrangement.canDrag ? tile : null
                        drag.threshold: 4
                        drag.minimumX: 0
                        drag.minimumY: 0
                        drag.maximumX: arrangement.width - tile.width
                        drag.maximumY: arrangement.height - tile.height
                        property bool moved: false
                        onPressed: { moved = false; page.selectedDescription = tile.r.desc; }
                        onPositionChanged: if (drag.active) moved = true
                        onReleased: {
                            if (!moved) return;
                            const f = arrangement.factor;
                            page.placeMonitor(tile.r.desc,
                                arrangement.minX + (tile.x - arrangement.offsetX) / f,
                                arrangement.minY + (tile.y - arrangement.offsetY) / f,
                                24 / f); // Lines up within 24 px on screen
                            // Back to following the layout: it glides to where it snapped
                            tile.x = Qt.binding(() => tile.homeX());
                            tile.y = Qt.binding(() => tile.homeY());
                        }
                    }
                }
            }
        }

        // Screens that aren't in the layout: off, or mirroring another
        Flow {
            visible: page.monitors.length > page.layoutRects.length
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: page.monitors.filter(m => m.disabled || page.isMirror(m))
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    materialIcon: modelData.disabled ? "desktop_access_disabled" : "screen_share"
                    mainText: modelData.disabled ? Translation.tr("%1 (off)").arg(page.label(modelData))
                        : Translation.tr("%1 (mirroring %2)").arg(page.label(modelData)).arg(page.label(page.byName(modelData.mirrorOf) ?? modelData))
                    toggled: page.selected !== undefined && page.selected.description === modelData.description
                    onClicked: page.selectedDescription = modelData.description
                }
            }
        }

        StyledText {
            visible: arrangement.canDrag
            Layout.fillWidth: true
            Layout.leftMargin: 2
            wrapMode: Text.Wrap
            text: Translation.tr("Drag the screens to match your desk. Click one to change it.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // ── The chosen screen's settings ──
    Repeater {
        model: page.selected ? [page.selected] : []
        delegate: ContentSection {
            id: section
            required property var modelData
            readonly property var m: modelData
            readonly property string description: m.description
            readonly property var entry: page.saved[description] ?? {}
            readonly property bool isOn: !m.disabled
            readonly property bool mirroring: page.isMirror(m)
            // "1920x1080@240.00Hz" → { res: "1920x1080", rate: "240.00" }
            readonly property var modes: (m.availableModes ?? []).map(s => {
                const match = s.match(/^(\d+x\d+)@([\d.]+)Hz$/);
                return match ? { res: match[1], rate: match[2] } : null;
            }).filter(x => x)
            readonly property string currentRes: `${m.width}x${m.height}`
            readonly property string currentRate: m.refreshRate.toFixed(2)
            readonly property var resolutions: [...new Set(modes.map(x => x.res))]
                .sort((a, b) => b.split("x").reduce((p, v) => p * v, 1) - a.split("x").reduce((p, v) => p * v, 1))
            readonly property var rates: [...new Set(modes.filter(x => x.res === currentRes).map(x => x.rate))]
                .sort((a, b) => parseFloat(b) - parseFloat(a))
            // Whole numbers (143.99 → 144 Hz); two rates that round alike (59.94 and 60) keep their decimals
            function rateLabel(rate) {
                const rounded = Math.round(parseFloat(rate));
                const clash = rates.filter(r => Math.round(parseFloat(r)) === rounded).length > 1;
                return clash ? `${parseFloat(rate).toFixed(2)} Hz` : `${rounded} Hz`;
            }
            // Other screens it can show: on, and not mirroring something themselves
            readonly property var mirrorSources: page.monitors.filter(o => o.description !== description && !o.disabled && !page.isMirror(o))

            icon: m.name.startsWith("eDP") ? "laptop" : "monitor"
            title: page.label(m)
            spacing: 10

            Flow { // What it is and what it runs at
                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 6
                InfoChip { icon: "cable"; text: section.m.name }
                InfoChip { visible: section.isOn; icon: "aspect_ratio"; text: `${section.m.width} × ${section.m.height}` }
                InfoChip { visible: section.isOn; icon: "speed"; text: section.rateLabel(section.currentRate) }
                InfoChip { visible: section.isOn; icon: "zoom_in"; text: `${Math.round(section.m.scale * 100)}%` }
                InfoChip { visible: !section.isOn; icon: "desktop_access_disabled"; text: Translation.tr("Off") }
            }
            StyledText {
                visible: !section.m.name.startsWith("eDP") && section.description !== section.m.model
                Layout.fillWidth: true
                Layout.leftMargin: 10
                elide: Text.ElideRight
                text: section.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            ConfigSwitch {
                visible: page.monitors.length > 1
                buttonIcon: "desktop_windows"
                text: Translation.tr("Use this screen")
                tooltip: section.isOn && page.onCount <= 1 ? Translation.tr("It's the only screen that's on") : ""
                enabled: !(section.isOn && page.onCount <= 1)
                checked: section.isOn
                onClicked: {
                    page.change(section.description, { disabled: section.isOn ? true : undefined }, true);
                    checked = Qt.binding(() => section.isOn);
                }
            }
            ConfigComboBox {
                visible: section.isOn && section.mirrorSources.length > 0
                icon: "screen_share"
                text: Translation.tr("Mirror")
                tooltip: Translation.tr("Show the same picture as another screen")
                currentValue: section.entry.mirror ?? (section.mirroring ? (page.byName(section.m.mirrorOf)?.description ?? "") : "")
                options: [{ displayName: Translation.tr("Off"), value: "" }]
                    .concat(section.mirrorSources.map(o => ({ displayName: page.label(o), value: o.description })))
                onSelected: v => page.change(section.description, { mirror: v === "" ? undefined : v }, true)
            }
            ColumnLayout { // Its own picture: not while off or mirroring
                visible: section.isOn && !section.mirroring
                Layout.fillWidth: true
                spacing: 10
                ConfigComboBox {
                    icon: "aspect_ratio"
                    text: Translation.tr("Resolution")
                    currentValue: section.currentRes
                    fallbackText: section.currentRes.replace("x", " × ")
                    options: section.resolutions.map(r => ({ displayName: r.replace("x", " × "), value: r }))
                    // The new resolution at its highest refresh rate
                    onSelected: res => page.change(section.description, { mode:
                        `${res}@${section.modes.filter(x => x.res === res).map(x => x.rate).sort((a, b) => parseFloat(b) - parseFloat(a))[0]}` }, true)
                }
                ConfigComboBox {
                    visible: section.rates.length > 1
                    icon: "speed"
                    text: Translation.tr("Refresh rate")
                    currentValue: section.currentRate
                    fallbackText: section.rateLabel(section.currentRate)
                    options: section.rates.map(r => ({ displayName: section.rateLabel(r), value: r }))
                    onSelected: rate => page.change(section.description, { mode: `${section.currentRes}@${rate}` }, true)
                }
                ConfigComboBox {
                    icon: "zoom_in"
                    text: Translation.tr("Scale")
                    tooltip: Translation.tr("Hyprland only accepts scales that divide the resolution evenly, so it picks the nearest one that does")
                    currentValue: section.m.scale
                    fallbackText: `${Math.round(section.m.scale * 100)}%`
                    options: [1, 1.25, 1.5, 1.75, 2].map(s => ({ displayName: `${Math.round(s * 100)}%`, value: s }))
                    onSelected: s => page.change(section.description, { scale: s }, true)
                }
                ConfigComboBox {
                    icon: "rotate_right"
                    text: Translation.tr("Rotation")
                    currentValue: section.m.transform
                    options: [
                        { displayName: Translation.tr("Normal"), value: 0 },
                        { displayName: "90°", value: 1 },
                        { displayName: "180°", value: 2 },
                        { displayName: "270°", value: 3 }
                    ]
                    onSelected: t => page.change(section.description, { transform: t }, true)
                }
                ConfigComboBox {
                    icon: "sync"
                    text: Translation.tr("Variable refresh rate")
                    tooltip: Translation.tr("Matches the refresh rate to what's drawn, for smoother games and video. Fullscreen only avoids flicker some screens show on the desktop")
                    currentValue: section.entry.vrr ?? (section.m.vrr ? 1 : 0)
                    options: [
                        { displayName: Translation.tr("Off"), value: 0 },
                        { displayName: Translation.tr("On"), value: 1 },
                        { displayName: Translation.tr("Fullscreen only"), value: 2 }
                    ]
                    onSelected: v => page.change(section.description, { vrr: v }, false)
                }
            }
            RippleButtonWithIcon {
                visible: page.saved[section.description] !== undefined
                Layout.alignment: Qt.AlignRight
                Layout.rightMargin: 8
                Layout.topMargin: 4
                materialIcon: "restart_alt"
                mainText: Translation.tr("Back to defaults")
                onClicked: page.forget(section.description)
                StyledToolTip {
                    text: Translation.tr("Forget the settings made here: its best resolution, next to the others, at 100%")
                }
            }
        }
    }
    // A schedule time ("19:00"): `key` in light.night. Typed as hours:minutes, saved when you're done
    component TimeRow: SettingRow {
        id: timeRow
        required property string key
        TextField {
            id: timeField
            implicitWidth: 84
            implicitHeight: 35
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: Config.options.light.night[timeRow.key]
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            selectionColor: Appearance.colors.colSecondaryContainer
            validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: timeField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
            // "7:30" → "07:30"; anything that isn't a time goes back to the saved one
            onEditingFinished: {
                if (!acceptableInput) { text = Config.options.light.night[timeRow.key]; return; }
                const [h, m] = text.split(":");
                const value = `${h.padStart(2, "0")}:${m}`;
                text = value;
                Config.options.light.night[timeRow.key] = value;
            }
        }
    }
    ContentSection {
        icon: "light_mode"
        title: Translation.tr("Night light")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "schedule"
            text: Translation.tr("Turn on automatically")
            option: "light.night.automatic"
            tooltip: Translation.tr("Between the times below. You can still switch it from the sidebar")
        }
        TimeRow {
            visible: Config.options.light.night.automatic
            key: "from"
            icon: "bedtime"
            text: Translation.tr("From")
        }
        TimeRow {
            visible: Config.options.light.night.automatic
            key: "to"
            icon: "wb_sunny"
            text: Translation.tr("To")
        }
        // Colour temperature: a slider over the colours it goes through, as the sidebar's (cooler on the left)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            spacing: 6
            SettingRow {
                Layout.leftMargin: 0 // The column has the margins
                Layout.rightMargin: 0
                icon: "device_thermostat"
                text: Translation.tr("Colour temperature")
                StyledText {
                    text: `${Math.round(temperatureSlider.value / 100) * 100} K`
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
            StyledSlider {
                id: temperatureSlider
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.S
                from: 6500
                to: 1200
                stepSize: 100
                stopIndicatorValues: [5000, to]
                value: Config.options.light.night.colorTemperature
                onMoved: Config.options.light.night.colorTemperature = Math.round(value / 100) * 100
                tooltipContent: `${Math.round(value / 100) * 100} K`
            }
            Rectangle { // Roughly how the screen tints at each point (daylight on the left, candle on the right)
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#fff6ef" }   // 6500 K
                    GradientStop { position: 0.28; color: "#ffe2c6" } // 5000 K
                    GradientStop { position: 0.57; color: "#ffbb7f" } // 3500 K
                    GradientStop { position: 0.85; color: "#ff8b27" } // 2000 K
                    GradientStop { position: 1; color: "#ff6a00" }    // 1200 K
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Cooler")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: Translation.tr("Warmer")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "flash_off"
            text: Translation.tr("Dim bright windows in dark mode")
            option: "light.antiFlashbang.enable"
            tooltip: Translation.tr("Lowers the brightness while a bright window, like a white web page, is on screen")
        }
    }
}
