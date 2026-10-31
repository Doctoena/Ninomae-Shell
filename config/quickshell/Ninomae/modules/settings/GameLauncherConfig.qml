import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    ContentSection {
        icon: "sports_esports"
        title: Translation.tr("Launcher")
        spacing: 10
        ConfigChoiceRow {
            icon: "sort"
            text: Translation.tr("Sort by")
            option: "gameLauncher.sortOrder"
            options: [
                { displayName: Translation.tr("Recent"), icon: "history", value: "recency" },
                { displayName: Translation.tr("Favourites"), icon: "star", value: "favorites" },
                { displayName: Translation.tr("Playtime"), icon: "schedule", value: "playtime" },
                { displayName: Translation.tr("Completed"), icon: "task_alt", value: "completed" }
            ]
        }
        ConfigSwitch {
            buttonIcon: "rocket_launch"
            text: Translation.tr("Show launch progress")
            option: "gameLauncher.launchAnimation"
            tooltip: Translation.tr("A drawer under the bar while the game starts: what Steam is doing (updating, shaders…)\nwith progress, until the game's window opens. Says so if the game quits before then")
        }
        ContentSubsection {
            title: Translation.tr("Artwork")
            ConfigSwitch {
                buttonIcon: "image_not_supported"
                text: Translation.tr("Hide games without box art")
                option: "gameLauncher.hideWithoutBoxArt"
                tooltip: Translation.tr("Mostly dedicated servers and tools, which have no cover art")
            }
            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Hide games with partial box art")
                option: "gameLauncher.hidePartialBoxArt"
                tooltip: Translation.tr("Games with only an auto-made cover")
            }
            ConfigSwitch {
                buttonIcon: "broken_image"
                text: Translation.tr("Use the game's icon when there's no art")
                option: "gameLauncher.fallbackToIcons"
                tooltip: Translation.tr("Instead of hiding the game or showing a blank tile")
            }
        }
    }
    ContentSection {
        icon: "movie"
        title: Translation.tr("Clips")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "fiber_smart_record"
            text: Translation.tr("Record clips while playing")
            option: "gameLauncher.clipsEnabled"
            tooltip: Translation.tr("While a game runs, the last moments are kept in memory. Press %1 to save them to %2. Nothing records outside games")
                .arg(Config.options.gameLauncher.clipKeyLabel || "`").arg(Config.options.gameLauncher.clipsFolder)
        }
        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Include my mic")
            visible: Config.options.gameLauncher.clipsEnabled
            option: "gameLauncher.clipMic"
            tooltip: Translation.tr("Your voice mixed in with the game and voice chat. Applies from the next game")
        }
        // The save key: click, then press the new key (or combo). Stored as Hyprland writes it; services/GameClips.qml
        // binds it (pass-through, so it still types). Key names where they exist, so it reads well in the
        // Keybinds list; a key code otherwise (Shift with a symbol key, keys without a name)
        SettingRow {
            id: clipKeyRow
            visible: Config.options.gameLauncher.clipsEnabled
            property bool recording: false
            readonly property bool isDefault: (Config.options.gameLauncher.clipKey || "grave") === "grave"
            icon: recording ? "radio_button_checked" : "keyboard"
            text: recording ? Translation.tr("Press the new key or combo. Esc cancels") : Translation.tr("Save key")
            tooltip: recording ? "" : Translation.tr("Saves the clip while a game runs. It still types normally everywhere")
            iconColor: recording ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            labelColor: recording ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            Repeater { // The key, as in the Keybinds list
                model: clipKeyRow.recording ? [] : (Config.options.gameLauncher.clipKeyLabel || "`").split("+")
                delegate: KeyChip {
                    required property string modelData
                    key: modelData
                }
            }
            RippleButtonWithIcon {
                id: clipKeyButton
                materialIcon: clipKeyRow.recording ? "close" : "edit"
                mainText: clipKeyRow.recording ? Translation.tr("Cancel") : Translation.tr("Change")
                // On release, and the button never takes the keyboard: otherwise the click's release moved focus
                // to it, the catcher lost focus, and recording only lasted while the button was held
                focusPolicy: Qt.NoFocus
                releaseAction: () => {
                    if (clipKeyRow.recording) { clipKeyRow.recording = false; return; }
                    clipKeyRow.recording = true;
                    keyCatcher.forceActiveFocus();
                }
            }
            RippleButtonWithIcon {
                visible: !clipKeyRow.isDefault && !clipKeyRow.recording
                focusPolicy: Qt.NoFocus
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset")
                downAction: () => {
                    Config.options.gameLauncher.clipKey = "grave";
                    Config.options.gameLauncher.clipKeyLabel = "`";
                }
            }
            Item {
                id: keyCatcher
                width: 0; height: 0
                onActiveFocusChanged: if (!activeFocus) clipKeyRow.recording = false
                readonly property var named: ({
                    [Qt.Key_Print]: ["Print", "Print"], [Qt.Key_Insert]: ["Insert", "Insert"], [Qt.Key_Delete]: ["Delete", "Delete"],
                    [Qt.Key_Home]: ["Home", "Home"], [Qt.Key_End]: ["End", "End"], [Qt.Key_PageUp]: ["Page_Up", "PgUp"],
                    [Qt.Key_PageDown]: ["Page_Down", "PgDn"], [Qt.Key_Pause]: ["Pause", "Pause"], [Qt.Key_ScrollLock]: ["Scroll_Lock", "ScrLk"],
                    [Qt.Key_Space]: ["space", "Space"], [Qt.Key_Tab]: ["Tab", "Tab"], [Qt.Key_Return]: ["Return", "Enter"],
                    [Qt.Key_Enter]: ["KP_Enter", "Num Enter"], [Qt.Key_Backspace]: ["BackSpace", "Backspace"], [Qt.Key_Menu]: ["Menu", "Menu"],
                    [Qt.Key_Left]: ["Left", "←"], [Qt.Key_Right]: ["Right", "→"], [Qt.Key_Up]: ["Up", "↑"], [Qt.Key_Down]: ["Down", "↓"],
                })
                readonly property var symbols: ({ "`": "grave", "-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright",
                    "\\": "backslash", ";": "semicolon", "'": "apostrophe", ",": "comma", ".": "period", "/": "slash" })
                readonly property var modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L,
                    Qt.Key_Super_R, Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Hyper_L, Qt.Key_Hyper_R]
                Keys.onPressed: event => {
                    event.accepted = true;
                    if (!clipKeyRow.recording || modifierKeys.includes(event.key)) return; // Wait for the key itself
                    const m = event.modifiers;
                    if (event.key === Qt.Key_Escape && m === Qt.NoModifier) { clipKeyRow.recording = false; return; }
                    const mods = [], modLabels = [];
                    if (m & Qt.MetaModifier) { mods.push("SUPER"); modLabels.push("Super"); }
                    if (m & Qt.ControlModifier) { mods.push("CTRL"); modLabels.push("Ctrl"); }
                    if (m & Qt.AltModifier) { mods.push("ALT"); modLabels.push("Alt"); }
                    if (m & Qt.ShiftModifier) { mods.push("SHIFT"); modLabels.push("Shift"); }
                    let name = "", label = "";
                    const k = event.key;
                    if (k >= Qt.Key_F1 && k <= Qt.Key_F35) { name = `F${k - Qt.Key_F1 + 1}`; label = name; }
                    else if (named[k]) { [name, label] = named[k]; }
                    else if (k >= 0x30 && k <= 0x39 || k >= 0x41 && k <= 0x5a) { // Digits, letters (the layout's)
                        label = String.fromCharCode(k); name = label.toLowerCase();
                    } else if (k > 0x20 && k < 0x7f && symbols[String.fromCharCode(k)]) {
                        label = String.fromCharCode(k); name = symbols[label];
                    } else if (event.nativeScanCode > 0) { // No name to use (Shift with a symbol key…): the physical key
                        name = `code:${event.nativeScanCode}`;
                        label = event.text && event.text.trim() !== "" ? event.text : Translation.tr("key %1").arg(event.nativeScanCode);
                    } else return;
                    Config.options.gameLauncher.clipKey = [...mods, name].join(" + ");
                    Config.options.gameLauncher.clipKeyLabel = [...modLabels, label].join("+");
                    clipKeyRow.recording = false;
                }
            }
        }
        // What else the save key does: another shortcut on the same keys (Hyprland's binds, read live), or a key
        // games use. It passes through, so in a game it would also save a clip every time it's pressed
        Item {
            id: clipKeyCheck
            Layout.fillWidth: true
            visible: Config.options.gameLauncher.clipsEnabled && message !== ""
            implicitHeight: visible ? warnRow.implicitHeight + 4 : 0
            readonly property string combo: Config.options.gameLauncher.clipKey || "grave"
            property var binds: []
            readonly property var parsed: { // { mask, key } as Hyprland reports binds
                const bits = { SUPER: 64, CTRL: 4, ALT: 8, SHIFT: 1 };
                const parts = combo.split("+").map(p => p.trim());
                const key = parts.pop();
                return { mask: parts.reduce((m, p) => m | (bits[p.toUpperCase()] ?? 0), 0), key: key.toLowerCase() };
            }
            readonly property var clashes: binds.filter(b => b.modmask === parsed.mask && (b.key ?? "").toLowerCase() === parsed.key
                && !(b.description ?? "").startsWith("Shell: Save gameplay clip"))
                // "Shell: Toggle overview" → "Toggle overview"; the same action bound twice (press and release) once
                .map(b => (b.description ?? "").replace(/^\[hidden\]\s*/, "").replace(/^[A-Za-z]+:\s*/, "") || b.dispatcher)
                .filter((d, i, all) => all.indexOf(d) === i)
            // Keys a game is likely to use on their own (no modifier)
            readonly property string gameKeyNote: {
                if (parsed.mask !== 0) return "";
                const k = parsed.key;
                if (k === "f12") return Translation.tr("F12 is Steam's screenshot key: pressing it would also save a clip");
                if (/^[a-z0-9]$/.test(k) || ["space", "tab", "return", "backspace", "left", "right", "up", "down", "shift_l", "control_l"].includes(k))
                    return Translation.tr("Games use this key: every press in a game would also save a clip. A key with Super, or an F key, is safer");
                return "";
            }
            readonly property string message: clashes.length > 0
                ? Translation.tr("Also does: %1").arg(clashes.join(", ")) : gameKeyNote
            Process {
                id: bindsReader
                command: ["hyprctl", "binds", "-j"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: { try { clipKeyCheck.binds = JSON.parse(text); } catch (e) { clipKeyCheck.binds = []; } }
                }
            }
            onComboChanged: { bindsReader.running = false; bindsReader.running = true; } // After a change, as Hyprland has it now
            RowLayout {
                id: warnRow
                anchors { left: parent.left; right: parent.right; leftMargin: 6 }
                spacing: 8
                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "warning"; iconSize: 18
                    color: Appearance.colors.colError
                }
                StyledText {
                    Layout.fillWidth: true
                    text: clipKeyCheck.message
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
        ConfigChoiceRow {
            visible: Config.options.gameLauncher.clipsEnabled
            icon: "timer"
            text: Translation.tr("Clip length")
            option: "gameLauncher.clipSeconds"
            options: [
                { displayName: Translation.tr("30 s"), value: 30 },
                { displayName: Translation.tr("1 min"), value: 60 },
                { displayName: Translation.tr("2 min"), value: 120 },
                { displayName: Translation.tr("5 min"), value: 300 }
            ]
        }
    }
    ContentSection {
        icon: "cloud_upload"
        title: Translation.tr("Immich backup")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "cloud_upload"
            text: Translation.tr("Back up to Immich")
            option: "gameLauncher.immichEnabled"
            tooltip: Translation.tr("A cloud button on a game's screenshots and clips uploads them to your own Immich server, in an album named after the game")
        }
        ContentSubsection {
            title: Translation.tr("Immich server")
            visible: Config.options.gameLauncher.immichEnabled
            StyledSecretField { // In the keyring too: it's your server's address, kept out of the dotfiles
                Layout.fillWidth: true
                secret: false
                enabled: KeyringStorage.loaded
                placeholderText: Translation.tr("Server URL (e.g. https://photos.example.com)")
                text: KeyringStorage.get("gameLauncher", "immichUrl") || Config.options.gameLauncher.immichUrl
                onEditingFinished: if (text.trim() !== KeyringStorage.get("gameLauncher", "immichUrl")) {
                    immichUrlSaved.pending = true;
                    KeyringStorage.set("gameLauncher", "immichUrl", text.trim());
                    Config.options.gameLauncher.immichUrl = "";
                }
            }
            Connections { // The Zen theme styles Immich on this server: once it's in the keyring, it puts the address in the profiles' copy
                id: immichUrlSaved
                property bool pending: false
                target: KeyringStorage
                function onSaved(ok) {
                    if (!immichUrlSaved.pending) return;
                    immichUrlSaved.pending = false;
                    if (ok) Quickshell.execDetached(["bash", "-c", 'bash "$(realpath "$0")/../../../themes/zen/apply-theme.sh"', Quickshell.shellDir]);
                }
            }
            StyledSecretField { // Hidden until shown: they're personal credentials
                Layout.fillWidth: true
                enabled: KeyringStorage.loaded
                placeholderText: Translation.tr("API key")
                text: KeyringStorage.get("gameLauncher", "immichApiKey")
                onEditingFinished: if (text.trim() !== KeyringStorage.get("gameLauncher", "immichApiKey"))
                    KeyringStorage.set("gameLauncher", "immichApiKey", text.trim())
                StyledToolTip { // Line breaks by hand: the tooltip doesn't wrap on its own
                    text: Translation.tr("Make the key in Immich → Account Settings → API Keys, with:\nasset.upload, asset.read, asset.view, asset.download,\nalbum.read, album.create and albumAsset.create\n\nEach game gets an album named after it.\nThe address and key are kept in your system keyring.")
                }
            }
        }
    }
    ContentSection {
        icon: "key"
        title: Translation.tr("API keys")
        spacing: 10
        StyledText { // Only while it can't be used: what each key does is in its field's tooltip
            Layout.fillWidth: true
            visible: !KeyringStorage.loaded
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Your keyring is locked, so the keys can't be read or saved right now. Log out and back in (logging in unlocks it), then come back here.")
        }
        Component.onCompleted: KeyringStorage.fetchKeyringData() // This Settings window is its own process
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
}
