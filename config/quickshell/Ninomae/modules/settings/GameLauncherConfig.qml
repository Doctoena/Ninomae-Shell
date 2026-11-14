import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
// Settings → Games: the library. The launcher (with the Steam Web API key that fills the library in), its art
// (with the SteamGridDB key it's picked from) and GE-Proton. What happens while a game runs is in InGameConfig.qml
ContentPage {
    Component.onCompleted: KeyringStorage.fetchKeyringData() // This Settings window is its own process
    ContentSection {
        title: Translation.tr("Launcher")
        spacing: 10
        ConfigChoiceRow {
            text: Translation.tr("Sort by")
            description: Translation.tr("The order of the library grid")
            option: "gameLauncher.sortOrder"
            options: [
                { displayName: Translation.tr("Recent"), icon: "history", value: "recency" },
                { displayName: Translation.tr("Favourites"), icon: "star", value: "favorites" },
                { displayName: Translation.tr("Playtime"), icon: "schedule", value: "playtime" },
                { displayName: Translation.tr("Completed"), icon: "task_alt", value: "completed" }
            ]
        }
        ConfigSwitch {
            text: Translation.tr("Show launch progress")
            option: "gameLauncher.launchAnimation"
            tooltip: Translation.tr("A drawer under the bar while the game starts: what Steam is doing (updating, shaders…)\nwith progress, until the game's window opens. Says so if the game quits before then")
        }
        ConfigSwitch {
            text: Translation.tr("Start Steam at login")
            option: "gameLauncher.steamAtLogin"
            tooltip: Translation.tr("Hidden in the tray, without its window. Games start without waiting for Steam,\nand updates download before you play. Uses some memory while it runs")
        }
        ContentSubsection {
            title: Translation.tr("Steam library")
            StyledText { // While the keyring is locked (what each key does is in its field's tooltip)
                Layout.fillWidth: true
                visible: !KeyringStorage.loaded
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Your keyring is locked, so the keys can't be read or saved right now. Log out and back in (logging in unlocks it), then come back here.")
            }
            StyledSecretField { // Hidden until shown: they're personal credentials
                Layout.fillWidth: true
                enabled: KeyringStorage.loaded
                placeholderText: Translation.tr("Steam Web API key")
                text: KeyringStorage.get("gameLauncher", "steamApiKey") || Config.options.gameLauncher.steamApiKey
                onEditingFinished: if (text !== KeyringStorage.get("gameLauncher", "steamApiKey")) {
                    KeyringStorage.set("gameLauncher", "steamApiKey", text);
                    Config.options.gameLauncher.steamApiKey = "";
                }
                StyledToolTip { // Line breaks by hand: the tooltip doesn't wrap on its own
                    text: Translation.tr("Optional. Keeps your library to the games you own (and family-shared ones),\nand fills in playtime and when you last played\n\nStored in your system keyring")
                }
            }
        }
    }
    // Steam's own download settings, in its config.vdf (launch_options.py downloads-get/-set). Steam only
    // reads them when it starts, so a change closes it and starts it again in the tray, a moment after the
    // last change (picking both hours restarts it once)
    ContentSection {
        id: steamDownloads
        title: Translation.tr("Steam downloads")
        spacing: 10
        readonly property string helper: Quickshell.shellPath("scripts/game-launcher/launch_options.py")
        property var current: null // As Steam has them, null until read (or with no Steam)
        property var pending: ({})  // Changes waiting to be written
        property string error: ""
        readonly property var shown: Object.assign({}, current ?? {}, pending)
        // A switch flips itself when clicked: the change comes from Steam's value instead, and the switch
        // goes back to showing it (after its own handler), so a change that fails shows as undone
        function toggle(sw, key) {
            change(key, !(shown[key] ?? false));
            Qt.callLater(() => sw.checked = Qt.binding(() => steamDownloads.shown[key] ?? false));
        }
        function change(key, value) {
            pending = Object.assign({}, pending, { [key]: value });
            error = "";
            applyTimer.restart();
        }
        Component.onCompleted: readProc.running = true
        Process {
            id: readProc
            command: ["python3", "-I", steamDownloads.helper, "downloads-get"]
            stdout: StdioCollector { onStreamFinished: { try { steamDownloads.current = JSON.parse(text); } catch (e) {} } }
        }
        Timer {
            id: applyTimer
            interval: 1500
            onTriggered: if (!writeProc.running) {
                writeProc.command = ["python3", "-I", steamDownloads.helper, "downloads-set", JSON.stringify(steamDownloads.pending), "--restart"];
                writeProc.running = true;
            }
        }
        Process {
            id: writeProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = null; try { r = JSON.parse(text); } catch (e) {}
                    steamDownloads.error = r?.ok ? "" : ({
                        "game-running": Translation.tr("A game is running. Close it and change this again."),
                        "steam-wont-close": Translation.tr("Steam didn't close, so nothing was changed. Try again.")
                    })[r?.error] ?? Translation.tr("Couldn't change Steam's settings.");
                    steamDownloads.pending = ({});
                    readProc.running = true;
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: steamDownloads.current === null
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Steam's settings will show here once Steam has been opened.")
        }
        ConfigSwitch {
            id: duringGameplaySwitch
            visible: steamDownloads.current !== null
            enabled: !writeProc.running
            text: Translation.tr("Download while playing")
            checked: steamDownloads.shown.duringGameplay ?? false
            onClicked: steamDownloads.toggle(duringGameplaySwitch, "duringGameplay")
            tooltip: Translation.tr("Off, Steam holds downloads while a game runs, so they don't slow it down")
        }
        ConfigSwitch {
            id: windowSwitch
            visible: steamDownloads.current !== null
            enabled: !writeProc.running
            text: Translation.tr("Only update games at certain hours")
            checked: steamDownloads.shown.windowEnabled ?? false
            onClicked: steamDownloads.toggle(windowSwitch, "windowEnabled")
            tooltip: Translation.tr("Updates for games you don't open wait for these hours.\nPlaying a game still updates it first")
        }
        ConfigComboBox {
            visible: steamDownloads.current !== null && (steamDownloads.shown.windowEnabled ?? false)
            enabled: !writeProc.running
            text: Translation.tr("From")
            description: Translation.tr("When updates may start")
            options: [...Array(24).keys()].map(h => ({ displayName: Qt.formatTime(new Date(2000, 0, 1, h), Qt.locale().timeFormat(Locale.ShortFormat)), value: h }))
            currentValue: steamDownloads.shown.windowStart ?? 1
            onSelected: v => steamDownloads.change("windowStart", v)
        }
        ConfigComboBox {
            visible: steamDownloads.current !== null && (steamDownloads.shown.windowEnabled ?? false)
            enabled: !writeProc.running
            text: Translation.tr("Until")
            description: Translation.tr("When they stop for the day")
            options: [...Array(24).keys()].map(h => ({ displayName: Qt.formatTime(new Date(2000, 0, 1, h), Qt.locale().timeFormat(Locale.ShortFormat)), value: h }))
            currentValue: steamDownloads.shown.windowEnd ?? 7
            onSelected: v => steamDownloads.change("windowEnd", v)
        }
        // Pause and resume from the launcher go through the shell's Millennium plugin
        // (themes/steam/ninomae-plugin, scripts/game-launcher/steam_control.py): whether it's there
        SettingsCard {
            RowLayout {
                id: plugin
                property string status: "" // steam_control.py status: on, outdated, installed (Steam isn't running), unreachable or missing
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 10
                Component.onCompleted: pluginCheck.running = true
                Process {
                    id: pluginCheck
                    command: ["python3", "-I", Quickshell.shellPath("scripts/game-launcher/steam_control.py"), "status"]
                    stdout: StdioCollector { onStreamFinished: plugin.status = text.trim() }
                }
                MaterialSymbol {
                    text: plugin.status === "missing" || plugin.status === "unreachable" ? "extension_off" : "extension"
                    iconSize: Appearance.font.pixelSize.larger
                    color: plugin.status === "on" || plugin.status === "outdated" ? Appearance.colors.colPrimary
                        : plugin.status === "unreachable" ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: plugin.status === "on" ? Translation.tr("The launcher can pause, resume and order Steam's downloads, and save launch options without restarting Steam.")
                        : plugin.status === "outdated" ? Translation.tr("The Ninomae plugin was updated. Restart Steam to load it.")
                        : plugin.status === "unreachable" ? Translation.tr("Steam is running but the Ninomae plugin isn't answering, so the launcher restarts Steam to save. Restart Steam, and if that doesn't fix it, run ninomae update.")
                        : plugin.status === "installed" ? Translation.tr("Pause and resume in the launcher work while Steam is running.")
                        : plugin.status === "missing" ? Translation.tr("To pause and resume downloads from the launcher, Steam needs Millennium and the Ninomae plugin. Run ninomae update to set them up.")
                        : ""
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                visible: steamDownloads.current !== null
                wrapMode: Text.Wrap
                color: steamDownloads.error !== "" ? Appearance.colors.colError : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: steamDownloads.error !== "" ? steamDownloads.error
                    : writeProc.running || applyTimer.running ? Translation.tr("Restarting Steam in the tray…")
                    : Translation.tr("Changing these restarts Steam in the tray. Speed limits are in Steam's Downloads page.")
            }
        }
    }
    ContentSection {
        title: Translation.tr("Artwork")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Hide games without box art")
            option: "gameLauncher.hideWithoutBoxArt"
            tooltip: Translation.tr("Mostly dedicated servers and tools, which have no cover art")
        }
        ConfigSwitch {
            text: Translation.tr("Hide games with partial box art")
            option: "gameLauncher.hidePartialBoxArt"
            tooltip: Translation.tr("Games with only an auto-made cover")
        }
        ConfigSwitch {
            text: Translation.tr("Use the game's icon when there's no art")
            option: "gameLauncher.fallbackToIcons"
            tooltip: Translation.tr("Instead of hiding the game or showing a blank tile")
        }
        StyledSecretField { // Hidden until shown: they're personal credentials
            Layout.fillWidth: true
            enabled: KeyringStorage.loaded
            placeholderText: Translation.tr("SteamGridDB API key")
            text: KeyringStorage.get("gameLauncher", "steamGridDbApiKey") || Config.options.gameLauncher.steamGridDbApiKey
            onEditingFinished: if (text !== KeyringStorage.get("gameLauncher", "steamGridDbApiKey")) {
                KeyringStorage.set("gameLauncher", "steamGridDbApiKey", text);
                Config.options.gameLauncher.steamGridDbApiKey = "";
            }
            StyledToolTip {
                text: Translation.tr("Optional. Lets you pick a game's cover, banner and logo from SteamGridDB\n\nStored in your system keyring")
            }
        }
    }
    ProtonGeSection {}
}
