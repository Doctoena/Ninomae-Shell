import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * A Steam game's launch options, in a panel growing up out of the launcher (LauncherTopPanel). Written into
 * Steam's own settings by scripts/game-launcher/launch_options.py, so Steam's Launch Options box shows the same.
 * On the left, the tools: GameMode, MangoHud and gamescope switch their word in front of %command% (MangoHud
 * with a layout, as MANGOHUD_CONFIG=preset=N, and gamescope with its own options, while on). On the right, the whole line as Steam holds it, and the Proton and Updates
 * menus (Updates once it's installed: the mode lives in the game's appmanifest).
 * Steam rewrites its settings when it quits, so saving while it's open closes and restarts it.
 * Keys: Enter in a box saves, Esc closes.
 */
LauncherTopPanel {
    id: root
    required property var game
    panelWidth: 1120
    panelHeight: 500
    readonly property string appid: game?.id?.startsWith("steam_") ? game.id.substring(6) : ""
    readonly property string helper: Quickshell.shellPath("scripts/game-launcher/launch_options.py")

    // What the helper reported, and the edited copy
    property var info: null
    property string options: ""
    property string proton: ""
    property int autoUpdate: -1 // -1: no manifest (not installed)
    property string status: "" // "", "loading", "saving", "saved", "error:<text>"
    readonly property bool loaded: info !== null
    readonly property bool steamRunning: info?.steamRunning ?? false
    readonly property bool changed: loaded && (options.trim() !== (info.launchOptions ?? "").trim() || proton !== (info.proton ?? "")
                                               || autoUpdate !== (info.autoUpdate ?? -1))
    readonly property bool busy: status === "saving"
    readonly property bool hasProton: (info?.protonVersions?.length ?? 0) > 0
    readonly property var protonOptions: [{ displayName: Translation.tr("Steam default"), value: "" },
        ...(info?.protonVersions ?? []).map(v => ({ displayName: v.label, value: v.name }))]
    readonly property var updateOptions: [
        { displayName: Translation.tr("Keep updated"), value: 0 },
        { displayName: Translation.tr("Only when I launch it"), value: 1 },
        { displayName: Translation.tr("High priority"), value: 2 }
    ]

    // ── The options string ↔ the tools ──
    // Words before %command% wrap the game; gamescope takes everything up to its "--"
    function parse(s) {
        s = (s ?? "").trim();
        const i = s.indexOf("%command%");
        if (i < 0) return { pre: [], gamescope: null, game: s };
        const tokens = s.substring(0, i).trim().split(/\s+/).filter(t => t);
        const pre = [];
        let gamescope = null;
        for (let k = 0; k < tokens.length; k++) {
            if (tokens[k] === "gamescope") {
                const end = tokens.indexOf("--", k);
                const stop = end < 0 ? tokens.length : end;
                gamescope = tokens.slice(k + 1, stop).join(" ");
                k = stop;
            } else pre.push(tokens[k]);
        }
        return { pre: pre, gamescope: gamescope, game: s.substring(i + 9).trim() };
    }
    function build(p) {
        const wrap = [...p.pre];
        if (p.gamescope !== null) wrap.push(`gamescope ${p.gamescope} --`.replace(/\s+/g, " "));
        return wrap.length ? `${wrap.join(" ")} %command% ${p.game}`.trim() : p.game;
    }
    readonly property var parsed: parse(options)
    readonly property var toolsOn: ({ gamemode: parsed.pre.includes("gamemoderun"), mangohud: parsed.pre.includes("mangohud"),
                                      gamescope: parsed.gamescope !== null })
    function toggle(tool) {
        const p = parse(options);
        if (tool === "gamescope") {
            // Back on: the options it had (this opening), else ones for this screen
            if (p.gamescope !== null) _gamescopeArgs = p.gamescope;
            p.gamescope = p.gamescope === null ? (_gamescopeArgs || (info?.defaultGamescopeArgs ?? "")) : null;
        } else {
            const word = tool === "gamemode" ? "gamemoderun" : "mangohud";
            // Off: its word, and MangoHud's layout with it
            if (p.pre.includes(word)) p.pre = p.pre.filter(t => t !== word && !(word === "mangohud" && /^MANGOHUD_CONFIG=preset=\d$/.test(t)));
            else {
                // Env vars stay first, then gamemoderun, then mangohud
                const envEnd = p.pre.filter(t => t.includes("=")).length;
                const at = word === "mangohud" ? Math.max(envEnd, p.pre.indexOf("gamemoderun") + 1) : envEnd;
                p.pre.splice(at, 0, word);
            }
        }
        options = build(p);
    }
    // MangoHud's layout: one of its presets (README: preset=), "" for its own config, "custom" for other settings
    readonly property string mangohudPreset: {
        const v = parsed.pre.find(t => t.startsWith("MANGOHUD_CONFIG="));
        if (!v) return "";
        const m = /^MANGOHUD_CONFIG=preset=(\d)$/.exec(v);
        return m ? m[1] : "custom";
    }
    function setMangohudPreset(preset) {
        const p = parse(options);
        p.pre = p.pre.filter(t => !t.startsWith("MANGOHUD_CONFIG="));
        if (preset !== "") p.pre.unshift(`MANGOHUD_CONFIG=preset=${preset}`); // Env vars first
        options = build(p);
    }
    property string _gamescopeArgs: ""
    function setGamescopeArgs(args) {
        const p = parse(options);
        if (p.gamescope === null) return;
        p.gamescope = args;
        options = build(p);
    }

    // ── Steam's settings, read and written by the helper ──
    onShownChanged: if (shown && appid) load()
    function load() {
        if (info?.appid !== appid) info = null; // Don't show the last game's options while this one loads
        status = "loading";
        getProc.command = ["python3", "-I", helper, "get", appid];
        getProc.running = true;
    }
    function revert() {
        options = info?.launchOptions ?? "";
        proton = info?.proton ?? "";
        autoUpdate = info?.autoUpdate ?? -1;
    }
    function save() {
        if (!changed || busy) return;
        status = "saving";
        const cmd = ["python3", "-I", helper, "set", appid, JSON.stringify({ launchOptions: options, proton: proton, autoUpdate: autoUpdate })];
        if (steamRunning) cmd.push("--restart");
        setProc.command = cmd;
        setProc.running = true;
    }
    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(text);
                    root.revert();
                    root.status = "";
                } catch (e) { root.status = "error:" + Translation.tr("Couldn't read Steam's settings"); }
            }
        }
    }
    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null; try { r = JSON.parse(text); } catch (e) {}
                if (r?.ok) { root.status = "saved"; root.load(); savedReset.restart(); }
                else root.status = "error:" + (r?.error === "steam-wont-close" ? Translation.tr("Steam didn't close. Try again")
                                                : Translation.tr("Couldn't save. See the shell log"));
            }
        }
    }
    Timer { id: savedReset; interval: 2500; onTriggered: if (root.status === "saved") root.status = "" }

    function handleKey(key) {
        if (key === Qt.Key_Escape) { closeRequested(); return true; }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && changed) { save(); return true; }
        return key === Qt.Key_Left || key === Qt.Key_Right; // Don't leave the page from under the panel
    }

    SheetHeader {
        id: header
        icon: "tune"
        title: Translation.tr("Launch options")
        subtitle: (root.game?.name ?? "") + (root.steamRunning ? "  ·  " + Translation.tr("Steam is open") : "")
        onCloseRequested: root.closeRequested()
    }

    SheetEmptyState { // Reading, or couldn't
        anchors.centerIn: parent
        visible: !root.loaded
        icon: root.status.startsWith("error:") ? "error" : "hourglass_empty"
        text: root.status.startsWith("error:") ? root.status.substring(6) : Translation.tr("Reading Steam's settings…")
    }

    // ── Left: the tools ──
    ColumnLayout {
        id: toolsColumn
        visible: root.loaded
        anchors { top: header.bottom; topMargin: 18; left: parent.left; leftMargin: 20 }
        width: 440
        spacing: 8
        SectionLabel { text: Translation.tr("Tools") }
        ToolCard {
            tool: "gamemode"; iconName: "speed"; title: "GameMode"; word: "gamemoderun"; pkg: "gamemode"
            description: Translation.tr("Tunes the CPU and GPU for games while it runs")
        }
        ToolCard {
            tool: "mangohud"; iconName: "monitoring"; title: "MangoHud"; word: "mangohud"; pkg: "mangohud"
            description: Translation.tr("FPS, frame times and temperatures over the game")
            // What it shows, while it's on
            extra: Segmented {
                value: root.mangohudPreset
                options: [
                    { value: "", label: Translation.tr("Default") },
                    { value: "1", label: Translation.tr("FPS only") },
                    { value: "2", label: Translation.tr("Horizontal") },
                    { value: "3", label: Translation.tr("Extended") },
                    { value: "4", label: Translation.tr("Detailed") }
                ]
                onPicked: v => root.setMangohudPreset(v)
            }
        }
        ToolCard {
            id: gamescopeCard
            tool: "gamescope"; iconName: "fit_screen"; title: "gamescope"; word: "gamescope"; pkg: "gamescope"
            description: Translation.tr("A set resolution and refresh rate, and upscaling")
            // Its options, while it's on
            extra: OptionBox {
                text: root.parsed.gamescope ?? ""
                placeholder: root.info?.defaultGamescopeArgs ?? "-f -W 1920 -H 1080 -r 60"
                onEdited: t => root.setGamescopeArgs(t)
            }
        }
    }

    // ── Right: the whole line, Proton and updates ──
    ColumnLayout {
        visible: root.loaded
        anchors { top: header.bottom; topMargin: 18; left: toolsColumn.right; leftMargin: 24; right: parent.right; rightMargin: 20 }
        spacing: 8
        SectionLabel { text: Translation.tr("Launch options") }
        OptionBox {
            Layout.fillWidth: true
            text: root.options
            placeholder: "gamemoderun %command% -novid"
            onEdited: t => root.options = t
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: Translation.tr("As Steam has it. <tt>%command%</tt> is the game: words before it run it, words after it go to the game.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RowLayout {
            // Not each menu's visible: a child of a hidden row reads as hidden, so the row would never show
            visible: root.hasProton || root.autoUpdate >= 0
            Layout.fillWidth: true
            Layout.topMargin: 14
            spacing: 12
            SettingMenu {
                visible: root.hasProton
                label: Translation.tr("Proton")
                options: root.protonOptions
                value: root.proton
                // A tool Steam has mapped that isn't installed any more: named, so it isn't shown as the default
                fallbackText: root.proton
                onSelected: v => root.proton = v
            }
            SettingMenu {
                visible: root.autoUpdate >= 0
                label: Translation.tr("Updates")
                options: root.updateOptions
                value: root.autoUpdate
                onSelected: v => root.autoUpdate = v
            }
        }
    }

    // ── Footer: what's going on, Revert, Save ──
    RowLayout {
        visible: root.loaded
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 20; rightMargin: 20; bottomMargin: 18 }
        spacing: 8
        MaterialSymbol {
            visible: statusText.text !== ""
            text: root.status.startsWith("error:") ? "error" : root.status === "saved" ? "check_circle"
                : root.busy ? "progress_activity" : root.changed ? "edit" : "info"
            iconSize: 18
            fill: 1
            color: statusText.color
            RotationAnimation on rotation { running: root.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        }
        StyledText {
            id: statusText
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.status.startsWith("error:") ? Appearance.colors.colError
                 : root.status === "saved" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            text: root.status.startsWith("error:") ? root.status.substring(6)
                : root.busy ? (root.steamRunning ? Translation.tr("Restarting Steam…") : Translation.tr("Saving…"))
                : root.status === "saved" ? Translation.tr("Saved to Steam")
                : root.changed ? (root.steamRunning ? Translation.tr("Not saved yet · Steam restarts to apply it") : Translation.tr("Not saved yet"))
                : ""
        }
        RippleButton {
            visible: root.changed && !root.busy
            implicitHeight: 40
            implicitWidth: revertRow.implicitWidth + 32
            buttonRadius: Appearance.rounding.container
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: root.revert()
            contentItem: Row {
                id: revertRow
                anchors.centerIn: parent; spacing: 6
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "undo"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                StyledText { anchors.verticalCenter: parent.verticalCenter; text: Translation.tr("Revert"); color: Appearance.colors.colOnLayer1; font.weight: Font.Medium }
            }
        }
        RippleButton {
            id: saveButton
            implicitHeight: 40
            implicitWidth: saveRow.implicitWidth + 36
            buttonRadius: Appearance.rounding.container
            enabled: root.changed && !root.busy
            colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.save()
            contentItem: Row {
                id: saveRow
                anchors.centerIn: parent; spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.steamRunning ? "restart_alt" : "save"; iconSize: 18
                    color: saveButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.steamRunning ? Translation.tr("Save & restart Steam") : Translation.tr("Save")
                    color: saveButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                    font.weight: Font.Medium
                }
            }
        }
    }

    // A column's small heading
    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    // A tool: what it does, and a switch for its word in front of %command%. Not installed: how to get it.
    // `extra` shows under it while it's on (gamescope's options)
    component ToolCard: Rectangle {
        id: card
        property string tool
        property string iconName
        property string title
        property string description
        property string word
        property string pkg
        property Component extra: null
        readonly property bool isOn: root.toolsOn[tool]
        readonly property bool available: root.info?.tools?.[tool] ?? false
        readonly property bool usable: available || isOn // Can always be switched off
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: cardMa.containsMouse && usable ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        border.width: isOn ? 1 : 0
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.5)
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        clip: true
        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: card.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (card.usable) root.toggle(card.tool)
        }
        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    implicitWidth: 36; implicitHeight: 36
                    radius: Appearance.rounding.container
                    color: card.isOn ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                    opacity: card.usable ? 1 : 0.5
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.iconName
                        iconSize: 20
                        fill: card.isOn ? 1 : 0
                        color: card.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: card.title
                        font.weight: Font.DemiBold
                        color: card.usable ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: card.available ? card.description : Translation.tr("Not installed: <tt>sudo dnf install %1</tt>").arg(card.pkg)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledSwitch {
                    checked: card.isOn
                    enabled: card.usable
                    onClicked: root.toggle(card.tool)
                }
            }
            Loader {
                Layout.fillWidth: true
                active: card.isOn && card.extra !== null
                visible: active
                sourceComponent: card.extra
            }
        }
    }

    // A row of choices, one picked (a value not among them, as "custom", picks none)
    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string value
        signal picked(string v)
        implicitHeight: 36
        radius: Appearance.rounding.segment
        color: Appearance.colors.colLayer2
        RowLayout {
            anchors { fill: parent; margins: 4 }
            spacing: 2
            Repeater {
                model: seg.options
                Rectangle {
                    id: segItem
                    required property var modelData
                    readonly property bool active: seg.value === modelData.value
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.segment - 2
                    color: active ? Appearance.colors.colPrimary : segMa.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    StyledText {
                        anchors.centerIn: parent
                        text: segItem.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: segItem.active ? Font.DemiBold : Font.Normal
                        color: segItem.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(segItem.modelData.value)
                    }
                }
            }
        }
    }

    // A one-line box for options, in monospace. Enter saves, Esc closes
    component OptionBox: Rectangle {
        id: box
        property string text
        property string placeholder
        signal edited(string text)
        implicitHeight: 42
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        border.width: field.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
        ToolbarTextField {
            id: field
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            colBackground: "transparent"
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            placeholderText: box.placeholder
            text: box.text
            onTextEdited: box.edited(text)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.save(); event.accepted = true; }
                else if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
            }
        }
    }

    // A labelled dropdown filling its share of the row
    component SettingMenu: ColumnLayout {
        id: settingMenu
        property string label
        property alias options: menu.options
        property alias value: menu.value
        property alias fallbackText: menu.fallbackText
        signal selected(var v)
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 6
        SectionLabel { text: settingMenu.label }
        StyledComboBox {
            id: menu
            Layout.fillWidth: true
            minimumWidth: 0
            onSelected: v => settingMenu.selected(v)
        }
    }
}
