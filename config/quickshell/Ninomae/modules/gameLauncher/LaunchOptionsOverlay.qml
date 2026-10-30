import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Per-game launch options for a Steam game, written into Steam's own settings by
// scripts/game-launcher/launch_options.py. One box holds the options exactly as Steam's does;
// the GameMode / MangoHud / gamescope tiles just add or remove their word in front of %command%.
// The Proton and Updates menus pick its compatibility tool and Steam's auto-update mode (Updates only
// once it's installed, as the mode lives in the game's appmanifest).
// Steam rewrites its settings when it quits, so saving while it's open closes and restarts it.
// A compact BottomSheet that rises out of the details panel.
BottomSheet {
    id: root
    required property var game
    sheetHeight: content.implicitHeight + 48
    readonly property string appid: game?.id?.startsWith("steam_") ? game.id.substring(6) : ""
    readonly property string helper: Quickshell.shellPath("scripts/game-launcher/launch_options.py")

    // What the helper reported, and the edited copy
    property var info: null
    property string options: ""
    property string proton: ""
    property int autoUpdate: -1 // -1: no manifest (not installed)
    property string status: "" // "", "loading", "saving", "saved", "error:<text>"
    readonly property bool steamRunning: info?.steamRunning ?? false
    readonly property bool changed: info !== null && (options.trim() !== (info.launchOptions ?? "").trim() || proton !== (info.proton ?? "")
                                                       || autoUpdate !== (info.autoUpdate ?? -1))
    readonly property var missingTools: ["gamemode", "mangohud", "gamescope"].filter(t => root.info && !root.info.tools[t])
    // The two menus' choices, as StyledComboBox options
    readonly property bool hasProton: (info?.protonVersions?.length ?? 0) > 0
    readonly property var protonOptions: [{ displayName: Translation.tr("Steam default"), value: "" },
        ...(root.info?.protonVersions ?? []).map(v => ({ displayName: v.label, value: v.name }))]
    readonly property var updateOptions: [
        { displayName: Translation.tr("Keep updated"), value: 0 },
        { displayName: Translation.tr("Only when I launch it"), value: 1 },
        { displayName: Translation.tr("High priority"), value: 2 }
    ]

    // ── The options string ↔ the tiles ──
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
    readonly property var toolsOn: {
        const p = parse(options);
        return { gamemode: p.pre.includes("gamemoderun"), mangohud: p.pre.includes("mangohud"), gamescope: p.gamescope !== null };
    }
    function toggle(tool) {
        const p = parse(options);
        if (tool === "gamescope") {
            p.gamescope = p.gamescope === null ? (info?.defaultGamescopeArgs ?? "") : null;
        } else {
            const word = tool === "gamemode" ? "gamemoderun" : "mangohud";
            if (p.pre.includes(word)) p.pre = p.pre.filter(t => t !== word);
            else {
                // Env vars stay first, then gamemoderun, then mangohud
                const envEnd = p.pre.filter(t => t.includes("=")).length;
                const at = word === "mangohud" ? Math.max(envEnd, p.pre.indexOf("gamemoderun") + 1) : envEnd;
                p.pre.splice(at, 0, word);
            }
        }
        options = build(p);
    }

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

    ColumnLayout {
        id: content
        x: 24; y: 24
        width: parent.width - 48
        spacing: 16

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText {
                text: Translation.tr("Launch options")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.game?.name ?? ""
                color: Appearance.colors.colSubtext
            }
            RippleButton {
                implicitWidth: 32; implicitHeight: 32; buttonRadius: Appearance.rounding.segment; padding: 0
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                contentItem: Item { MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: Appearance.colors.colSubtext } }
                onClicked: root.closeRequested()
            }
        }

        StyledText { // Loading / failed to read
            visible: root.info === null
            Layout.fillWidth: true
            Layout.topMargin: 12; Layout.bottomMargin: 12
            horizontalAlignment: Text.AlignHCenter
            text: root.status.startsWith("error:") ? root.status.substring(6) : Translation.tr("Reading Steam's settings…")
            color: root.status.startsWith("error:") ? Appearance.colors.colError : Appearance.colors.colSubtext
        }

        // ── Tools ──
        RowLayout {
            visible: root.info !== null
            Layout.fillWidth: true
            spacing: 8
            ToolTile { iconName: "speed"; title: "GameMode"; tool: "gamemode" }
            ToolTile { iconName: "monitoring"; title: "MangoHud"; tool: "mangohud" }
            ToolTile { iconName: "fit_screen"; title: "gamescope"; tool: "gamescope" }
        }

        // ── The one box, like Steam's ──
        Rectangle {
            visible: root.info !== null
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: input.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary
            ToolbarTextField {
                id: input
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                colBackground: "transparent"
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                placeholderText: "gamemoderun %command% -novid"
                text: root.options
                onTextEdited: root.options = text
            }
        }

        // ── Proton and Updates: a menu each, side by side ──
        RowLayout {
            // Not protonMenu.visible || updatesMenu.visible: a child of a hidden row reads as hidden,
            // so the row would never show
            visible: root.info !== null && (root.hasProton || root.autoUpdate >= 0)
            Layout.fillWidth: true
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

        // ── Footer ──
        RowLayout {
            visible: root.info !== null
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.StyledText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.status.startsWith("error:") ? Appearance.colors.colError
                     : root.status === "saved" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                text: root.status.startsWith("error:") ? root.status.substring(6)
                    : root.status === "saving" ? (root.steamRunning ? Translation.tr("Restarting Steam…") : Translation.tr("Saving…"))
                    : root.status === "saved" ? Translation.tr("Saved to Steam")
                    : root.steamRunning && root.changed ? Translation.tr("Steam will restart to apply this")
                    : root.missingTools.length > 0 ? Translation.tr("Dimmed tools need <tt>sudo dnf install %1</tt>").arg(root.missingTools.join(" "))
                    : ""
            }
            RippleButton {
                visible: root.changed && root.status !== "saving"
                implicitHeight: 38
                implicitWidth: revertLabel.implicitWidth + 28
                buttonRadius: Appearance.rounding.container
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: root.revert()
                contentItem: Item {
                    StyledText { id: revertLabel; anchors.centerIn: parent; text: Translation.tr("Revert"); color: Appearance.colors.colPrimary; font.weight: Font.Medium }
                }
            }
            RippleButton {
                id: saveButton
                implicitHeight: 38
                implicitWidth: saveLabel.implicitWidth + 40
                buttonRadius: Appearance.rounding.container
                enabled: root.changed && root.status !== "saving"
                colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.save()
                contentItem: Item {
                    StyledText {
                        id: saveLabel
                        anchors.centerIn: parent
                        text: root.steamRunning ? Translation.tr("Save & restart Steam") : Translation.tr("Save")
                        color: saveButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    // A tool: icon and name, filled lavender when on. Flips its word in the options box; dimmed when not installed
    component ToolTile: RippleButton {
        id: tile
        property string iconName
        property string title
        property string tool
        readonly property bool isOn: root.toolsOn[tool]
        readonly property bool available: root.info?.tools?.[tool] ?? false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 50
        buttonRadius: Appearance.rounding.normal
        enabled: available || isOn // Can always be switched off
        opacity: enabled ? 1 : 0.4
        colBackground: isOn ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        colBackgroundHover: isOn ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
        colRipple: isOn ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
        onClicked: root.toggle(tool)
        contentItem: RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 12 }
            spacing: 10
            MaterialSymbol {
                text: tile.iconName
                iconSize: 20
                fill: tile.isOn ? 1 : 0
                color: tile.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: tile.title
                font.weight: Font.Medium
                color: tile.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            StyledText { // Only shown when it can't be used
                visible: !tile.available
                text: Translation.tr("Not installed")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
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
        StyledText {
            text: settingMenu.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
        }
        StyledComboBox {
            id: menu
            Layout.fillWidth: true
            minimumWidth: 0
            onSelected: v => settingMenu.selected(v)
        }
    }
}
