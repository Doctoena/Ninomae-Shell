//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings

// First-run setup, opened once after install (services/FirstRunExperience.qml). Built as Settings is: you and the
// steps on the left (done ones checked), the step's big title on top and its options as Settings' rows, with the
// same pieces Settings uses (wallpaper carousel, tiling and bar shape tiles, weather). Welcome → look → layout →
// weather → gaming → shortcuts → done. Every choice applies straight away and can be changed later in Settings.
ApplicationWindow {
    id: root
    readonly property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    readonly property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    readonly property string group: Translation.tr("Setup")
    readonly property var steps: [
        { name: Translation.tr("Welcome"), icon: "waving_hand" },
        { name: Translation.tr("Look"), icon: "palette", title: Translation.tr("Make it yours"),
            description: Translation.tr("Pick a wallpaper. The shell, your apps, the browser and the login screen take their colours from it") },
        { name: Translation.tr("Layout"), icon: "dashboard", title: Translation.tr("Arrange your windows"),
            description: Translation.tr("How windows tile, and the bar's shape and place. Changes apply straight away") },
        { name: Translation.tr("Weather"), icon: "partly_cloudy_day", title: Translation.tr("Your weather"),
            description: Translation.tr("The clock drawer shows the weather and the next hours. Pick a city or let it find you") },
        { name: Translation.tr("Gaming"), icon: "sports_esports", title: Translation.tr("Built for games"),
            description: Translation.tr("Your Steam, Lutris and other games in one launcher, with clips and a crosshair when you play") },
        { name: Translation.tr("Shortcuts"), icon: "keyboard", title: Translation.tr("The essentials"),
            description: Translation.tr("A few shortcuts to get around. The full list is one shortcut away") },
        { name: Translation.tr("Done"), icon: "check_circle", title: Translation.tr("You're all set"),
            description: Translation.tr("Everything here, and much more, is in Settings") }
    ]
    readonly property int pageCount: steps.length
    // The page list: done steps get a check
    readonly property var navPages: steps.map((s, i) => ({ name: s.name, icon: i < current ? "check" : s.icon }))
    property int current: 0
    visible: true
    title: Translation.tr("Ninomae Welcome")
    minimumWidth: 900
    minimumHeight: 620
    width: 1477 // As Settings, and as the window rule "welcome" floats it
    height: 859
    color: Appearance.colors.colLayer0
    // Snapshots (below) can't be clicked: a stray click on the carousel would change the wallpaper
    flags: snapshotDir !== "" ? Qt.Window | Qt.WindowTransparentForInput : Qt.Window
    onClosing: Qt.quit()
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0; // Each choice sets one option at a time, no need to batch
    }

    function go(i) { root.current = Math.max(0, Math.min(root.pageCount - 1, i)); }
    function next() { if (root.current < root.pageCount - 1) go(root.current + 1); else root.close(); }
    function back() { go(root.current - 1); }
    function stepPage(i) { // A step as SettingsHeader shows a page
        const s = root.steps[i];
        return { name: s.title, group: Translation.tr("%1 · step %2 of %3").arg(root.group).arg(i + 1).arg(root.pageCount),
            icon: s.icon, description: s.description };
    }
    function setShowNextTime(show) {
        if (show) Quickshell.execDetached(["rm", "-f", root.firstRunFilePath]);
        else Quickshell.execDetached(["bash", "-c", 'printf "%s\\n" "$1" > "$2"', "welcome", root.firstRunFileContent, root.firstRunFilePath]);
    }
    // The live shortcut for a bind, by its description in keybinds.lua ("Category: Comment"), so the
    // rows show the right keys for the keyboard layout (Dvorak or QWERTY)
    function bindFor(category, comment) {
        for (const column of HyprlandKeybinds.keybinds.children ?? [])
            for (const section of column.children ?? [])
                if (section.name === category)
                    for (const kb of section.keybinds)
                        if (kb.comment === comment) return [...kb.mods, root.keyLabel(kb.key)];
        return [];
    }
    function keyLabel(key) {
        const names = { "Return": "Enter", "Slash": "/", "Delete": "Del", "Semicolon": ";", "Apostrophe": "'",
                        "Period": ".", "Comma": ",", "Space": "Space", "Escape": "Esc", "grave": "`" };
        return names[key] ?? key;
    }

    Shortcut { sequences: ["Escape"]; onActivated: root.close() }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: root.next() }
    Shortcut { sequence: "Ctrl+PgDown"; onActivated: root.go(root.current + 1) }
    Shortcut { sequence: "Ctrl+PgUp"; onActivated: root.back() }

    // For checking the design: NINOMAE_WELCOME_SNAPSHOT=/dir renders every step to /dir/page-N.png and quits
    readonly property string snapshotDir: Quickshell.env("NINOMAE_WELCOME_SNAPSHOT") ?? ""
    property int snapshotPage: 0
    Timer {
        running: root.snapshotDir !== ""
        interval: 1800
        repeat: true
        onTriggered: { // Show step N, give it a moment to settle, then capture it
            const n = root.snapshotPage;
            if (n >= root.pageCount) { stop(); quitTimer.start(); return; }
            root.current = n;
            grabLater.page = n;
            grabLater.start();
            root.snapshotPage = n + 1;
        }
    }
    Timer {
        id: grabLater
        property int page: 0
        interval: 900
        onTriggered: frame.grabToImage(result => result.saveToFile(`${root.snapshotDir}/page-${page + 1}.png`))
    }
    Timer { id: quitTimer; interval: 800; onTriggered: Qt.quit() }

    Item { // Everything visible (one item, so it can also be rendered to an image)
        id: frame
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }

        RowLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 8

            SettingsNav { // You, and the steps
                id: nav
                pages: root.navPages
                currentPage: root.current
                stateFile: `${FileUtils.trimFileProtocol(Directories.state)}/user/welcome.json`
                collapsible: false
                narrow: root.width <= 960
                subtitle: Translation.tr("Getting set up")
                onPageChosen: index => root.go(index)
                NavRow {
                    Layout.fillWidth: true
                    expanded: nav.expanded
                    symbol: "skip_next"
                    text: Translation.tr("Skip setup")
                    onClicked: root.close()
                }
            }

            Item { // The step, then Back / Next under it, lined up with the step's column
                id: content
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                readonly property real columnWidth: Math.min(width - 40, 1260) // ContentPage's: 20 px margin, 1260 at most

                StackLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; bottomMargin: 12 }
                    currentIndex: root.current

                    // 1 · Welcome: the wallpaper, and a greeting in its corner (as the lock screen)
                    ClippingRectangle {
                        radius: Appearance.rounding.windowRounding
                        color: Appearance.colors.colLayer1
                        Image {
                            anchors.fill: parent
                            source: Config.wallpaperPath ? "file://" + Config.wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 1600
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.85) }
                                GradientStop { position: 0.55; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45) }
                                GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.05) }
                            }
                        }
                        ColumnLayout {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 44 }
                            width: Math.min(parent.width - 88, 620)
                            spacing: 8
                            StyledText {
                                text: "NINOMAE"
                                color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                font.letterSpacing: 6
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Translation.tr("Welcome, %1").arg(SystemInfo.username)
                                color: Appearance.colors.colOnLayer0
                                font.family: Appearance.font.family.title
                                font.pixelSize: 56
                                font.weight: Font.Black
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Translation.tr("A desktop that takes its colours from your wallpaper. A few quick choices and you're set, in about a minute.")
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.8
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                        }
                    }

                    // 2 · Look: the wallpaper carousel and light or dark, as in Settings → Appearance
                    Step {
                        index: 1
                        ContentSection {
                            title: Translation.tr("Wallpaper")
                            SettingsCard {
                                WallpaperSelector { Layout.fillWidth: true }
                            }
                            SettingRow {
                                text: Translation.tr("Light or dark")
                                description: Translation.tr("Makes the colours again from the same wallpaper")
                                ConfigSelectionArray {
                                    Layout.fillWidth: false
                                    currentValue: Appearance.m3colors.darkmode
                                    onSelected: dark => Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--mode", dark ? "dark" : "light", "--noswitch"])
                                    options: [
                                        { displayName: Translation.tr("Light"), icon: "light_mode", value: false },
                                        { displayName: Translation.tr("Dark"), icon: "dark_mode", value: true }
                                    ]
                                }
                            }
                        }
                    }

                    // 3 · Layout: tiling, and the bar's shape and position
                    Step {
                        index: 2
                        ContentSection {
                            title: Translation.tr("Tiling layout")
                            TilingLayoutPicker {}
                        }
                        ContentSection {
                            title: Translation.tr("Bar")
                            SettingsCard {
                                RowLayout { // The three shapes share the card's width
                                    Layout.fillWidth: true
                                    spacing: 20
                                    uniformCellSizes: true
                                    BarShapeTile { shape: 0; name: Translation.tr("Hug") }
                                    BarShapeTile { shape: 1; name: Translation.tr("Float") }
                                    BarShapeTile { shape: 2; name: Translation.tr("Square") }
                                }
                            }
                            ConfigChoiceRow {
                                text: Translation.tr("Position")
                                description: Translation.tr("Along the top or the bottom of the screen. Its drawers open from there")
                                option: "bar.bottom"
                                options: [
                                    { displayName: Translation.tr("Top"), icon: "arrow_upward", value: false },
                                    { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: true }
                                ]
                            }
                        }
                    }

                    // 4 · Weather: Settings' weather rows, and the weather for the place as a check
                    Step {
                        index: 3
                        WeatherSection { title: Translation.tr("Options") }
                        ContentSection {
                            title: Translation.tr("Right now")
                            visible: Config.options.bar.weather.enable
                            SettingsCard { WeatherCheck { Layout.fillWidth: true } }
                        }
                    }

                    // 5 · Gaming
                    Step {
                        index: 4
                        ContentSection {
                            title: Translation.tr("Your games")
                            ShortcutRow {
                                text: Translation.tr("Game launcher")
                                description: Translation.tr("Every game in one place: covers, playtime, news, achievements and screenshots")
                                keys: root.bindFor("Shell", "Toggle game launcher")
                            }
                        }
                        ContentSection {
                            title: Translation.tr("While you play")
                            ConfigSwitch {
                                text: Translation.tr("Gameplay clips")
                                description: Translation.tr("While a game runs, one key saves the last minute. Clips land in ~/Videos/Clips")
                                option: "gameLauncher.clipsEnabled"
                            }
                            ShortcutRow {
                                visible: Config.options.gameLauncher.clipsEnabled
                                text: Translation.tr("Save a clip")
                                description: Translation.tr("You can change the key in Settings → In game")
                                // The backtick alone is too small to read on a keycap: shown as the key's ~ ` legend
                                keys: [((l) => l === "`" ? "~ `" : l)(Config.options.gameLauncher.clipKeyLabel || "`")]
                            }
                            ShortcutRow {
                                text: Translation.tr("Crosshair")
                                description: Translation.tr("An on-screen crosshair, turned on per game from its page. Design it in Settings")
                                keys: root.bindFor("Shell", "Show/hide crosshair")
                            }
                        }
                    }

                    // 6 · Shortcuts
                    Step {
                        index: 5
                        ContentSection {
                            title: Translation.tr("Getting around")
                            ShortcutRow { text: Translation.tr("Launcher, apps and search"); keys: root.bindFor("Shell", "Toggle overview/launcher") }
                            ShortcutRow { text: Translation.tr("Sidebar: toggles and notifications"); keys: root.bindFor("Shell", "Toggle right sidebar") }
                            ShortcutRow { text: Translation.tr("Settings"); keys: root.bindFor("Apps", "Ninomae Settings") }
                            ShortcutRow {
                                text: Translation.tr("Every shortcut, searchable")
                                labelColor: Appearance.colors.colPrimary
                                keys: root.bindFor("Shell", "Keybinds")
                            }
                        }
                        ContentSection {
                            title: Translation.tr("Handy")
                            ShortcutRow { text: Translation.tr("Clipboard history"); keys: root.bindFor("Shell", "Clipboard history") }
                            ShortcutRow { text: Translation.tr("Screenshot"); keys: root.bindFor("Screen", "Screenshot") }
                        }
                        ContentSection {
                            title: Translation.tr("Session")
                            ShortcutRow { text: Translation.tr("Lock"); keys: root.bindFor("Session", "Lock screen") }
                            ShortcutRow { text: Translation.tr("Power menu"); keys: root.bindFor("Shell", "Power menu") }
                        }
                    }

                    // 7 · Done
                    Step {
                        index: 6
                        ContentSection {
                            title: Translation.tr("Where to next")
                            SettingRow {
                                text: Translation.tr("Settings")
                                description: Translation.tr("Wallpaper, bar, displays, games and everything else")
                                RippleButtonWithIcon {
                                    materialIcon: "settings"
                                    mainText: Translation.tr("Open Settings")
                                    onClicked: {
                                        Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh")]);
                                        root.close();
                                    }
                                }
                            }
                            SettingRow {
                                text: Translation.tr("Every shortcut")
                                description: Translation.tr("Searchable, and you can change them")
                                RippleButtonWithIcon {
                                    materialIcon: "keyboard_alt"
                                    mainText: Translation.tr("All shortcuts")
                                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh"), "keybinds"])
                                }
                            }
                            SettingRow {
                                text: Translation.tr("A new wallpaper any time")
                                description: Translation.tr("Type /wallpaper in the launcher")
                            }
                        }
                        ContentSection {
                            title: Translation.tr("This window")
                            SettingRow {
                                text: Translation.tr("Show this again at next login")
                                StyledSwitch {
                                    onClicked: root.setShowNextTime(checked)
                                }
                            }
                        }
                    }
                }

                // ── Back · Next ──
                RowLayout {
                    id: footer
                    anchors { bottom: parent.bottom; bottomMargin: 12 }
                    x: (parent.width - width) / 2
                    width: content.columnWidth
                    height: 44
                    RippleButton {
                        implicitWidth: backRow.implicitWidth + 28; implicitHeight: 44
                        buttonRadius: Appearance.rounding.container
                        opacity: root.current > 0 ? 1 : 0
                        enabled: root.current > 0
                        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        onClicked: root.back()
                        contentItem: Item {
                            RowLayout {
                                id: backRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol { text: "chevron_left"; iconSize: 20; color: Appearance.colors.colOnLayer0 }
                                StyledText { text: Translation.tr("Back"); color: Appearance.colors.colOnLayer0 }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        implicitWidth: nextRow.implicitWidth + 40; implicitHeight: 44
                        buttonRadius: Appearance.rounding.container
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.next()
                        contentItem: Item {
                            RowLayout {
                                id: nextRow
                                anchors.centerIn: parent
                                spacing: 6
                                StyledText {
                                    text: root.current === 0 ? Translation.tr("Get started")
                                        : root.current === root.pageCount - 1 ? Translation.tr("Finish") : Translation.tr("Next")
                                    color: Appearance.colors.colOnPrimary
                                    font.weight: Font.Medium
                                }
                                MaterialSymbol {
                                    text: root.current === root.pageCount - 1 ? "check" : "chevron_right"
                                    iconSize: 20
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────────
    // A step as a Settings page: its big title on top (SettingsHeader, with Close), its rows under it
    component Step: Item {
        id: step
        required property int index
        default property alias rows: rowsPage.contentData
        SettingsHeader {
            id: stepHeader
            anchors { top: parent.top; topMargin: 20 } // Close sits as far from the top edge as from the right
            width: content.columnWidth
            x: (parent.width - width) / 2
            page: root.stepPage(step.index)
            searchable: false
            onCloseClicked: root.close()
        }
        ContentPage {
            id: rowsPage
            anchors { top: stepHeader.bottom; topMargin: 18; left: parent.left; right: parent.right; bottom: parent.bottom }
            margin: 20
            bottomContentPadding: 8
        }
    }

    // A row saying what a shortcut does, with its keys as keycaps on the right. Hidden when the bind isn't there
    component ShortcutRow: SettingRow {
        id: sr
        property var keys: []
        visible: keys.length > 0
        Row {
            spacing: 4
            Repeater {
                model: sr.keys
                KeyboardKey { required property string modelData; key: modelData }
            }
        }
    }

    // The weather for the chosen place once it's found, as a check that it's the right one; else what's missing
    component WeatherCheck: Item {
        id: wc
        readonly property bool gps: Config.options.bar.weather.enableGPS
        readonly property string city: WeatherLocation.city.trim()
        readonly property bool found: Weather.locationValid && Weather.data.temp !== ""
            && (gps || (!Weather.cityNotFound && Weather._geocodedCity.trim() === city))
        readonly property string status: {
            if (gps) return Weather.gpsActive ? Translation.tr("Finding your location…")
                : Translation.tr("Couldn't get your location. Pick a city instead.");
            if (city.length === 0) return Translation.tr("Type a city to see its weather here.");
            if (Weather.cityNotFound) return Translation.tr("No place called “%1” found. Check the spelling.").arg(city);
            return Translation.tr("Looking up %1…").arg(city);
        }
        implicitHeight: 64
        RowLayout { // Found: the weather and where it's for
            visible: wc.found
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 14
            Rectangle {
                implicitWidth: 48; implicitHeight: 48
                radius: Appearance.rounding.small
                color: Appearance.colors.colPrimary
                MaterialSymbol { anchors.centerIn: parent; text: Weather.data.icon || "cloud"; iconSize: 26; fill: 1; color: Appearance.colors.colOnPrimary }
            }
            StyledText {
                text: Weather.data.temp
                font.family: Appearance.font.family.title
                font.pixelSize: 30
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: Weather.data.condition; color: Appearance.colors.colOnLayer1 }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: wc.gps ? Weather.resolvedCity : Weather.resolvedPlace
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
        RowLayout { // Not found (yet): what's happening or what's missing
            visible: !wc.found
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12
            MaterialSymbol {
                text: Weather.cityNotFound && !wc.gps ? "wrong_location" : "travel_explore"
                iconSize: 26
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: wc.status
                color: Appearance.colors.colSubtext
            }
        }
    }
}
