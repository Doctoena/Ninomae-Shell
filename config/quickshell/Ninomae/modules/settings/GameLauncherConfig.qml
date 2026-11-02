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
    ContentSection {
        icon: "image"
        title: Translation.tr("Artwork")
        spacing: 10
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
