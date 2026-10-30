//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// First-run setup, opened once after install (services/FirstRunExperience.qml). A step list on the left
// (as Settings' navigation), the step on the right: welcome → look (light/dark, wallpaper) → layout
// (tiling, bar; with a live preview) → weather (where the forecast is for) → gaming (launcher, clips, crosshair) → shortcuts → done.
// Every choice applies straight away and can be changed later in Settings (Super+I).
ApplicationWindow {
    id: root
    readonly property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    readonly property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    readonly property string wallpaperDir: `${Quickshell.env("HOME")}/Pictures/Wallpapers`
    readonly property var steps: [
        { icon: "waving_hand", name: Translation.tr("Welcome") },
        { icon: "palette", name: Translation.tr("Look") },
        { icon: "dashboard", name: Translation.tr("Layout") },
        { icon: "partly_cloudy_day", name: Translation.tr("Weather") },
        { icon: "sports_esports", name: Translation.tr("Gaming") },
        { icon: "keyboard", name: Translation.tr("Shortcuts") },
        { icon: "check_circle", name: Translation.tr("Done") }
    ]
    readonly property int pageCount: steps.length
    property int current: 0
    visible: true
    title: Translation.tr("Ninomae Welcome")
    minimumWidth: 860
    minimumHeight: 580
    width: 1000
    height: 680
    color: Appearance.colors.colLayer0
    onClosing: Qt.quit()
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0; // Each choice sets one option at a time, no need to batch
    }

    function go(i) { root.current = Math.max(0, Math.min(root.pageCount - 1, i)); }
    function next() { if (root.current < root.pageCount - 1) go(root.current + 1); else root.close(); }
    function back() { go(root.current - 1); }
    function setShowNextTime(show) {
        if (show) Quickshell.execDetached(["rm", "-f", root.firstRunFilePath]);
        else Quickshell.execDetached(["bash", "-c", 'printf "%s\\n" "$1" > "$2"', "welcome", root.firstRunFileContent, root.firstRunFilePath]);
    }
    // The live shortcut for a bind, by its description in keybinds.lua ("Category: Comment"), so the
    // cards show the right keys for the keyboard layout (Dvorak or QWERTY)
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

        // ── Steps: the brand, then each step (done ones checked, the current one in the accent) ──
        ColumnLayout {
            id: rail
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 16 }
            width: 200
            spacing: 4
            RowLayout {
                Layout.leftMargin: 10
                Layout.bottomMargin: 18
                Layout.topMargin: 6
                spacing: 10
                Rectangle {
                    implicitWidth: 36; implicitHeight: 36; radius: Appearance.rounding.container
                    color: Appearance.colors.colPrimary
                    MaterialSymbol { anchors.centerIn: parent; text: "auto_awesome"; iconSize: 20; color: Appearance.colors.colOnPrimary }
                }
                ColumnLayout {
                    spacing: 0
                    StyledText { text: "Ninomae"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                    StyledText { text: Translation.tr("Setup"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                }
            }
            Repeater {
                model: root.steps
                RippleButton {
                    id: stepBtn
                    required property var modelData
                    required property int index
                    readonly property bool active: index === root.current
                    readonly property bool done: index < root.current
                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.container
                    colBackground: active ? Appearance.colors.colLayer1 : "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: root.go(index)
                    contentItem: RowLayout {
                        spacing: 12
                        Rectangle { // Accent squircle behind the current step's icon
                            Layout.leftMargin: 6
                            implicitWidth: 32; implicitHeight: 32; radius: Appearance.rounding.segment
                            color: stepBtn.active ? Appearance.colors.colPrimary : "transparent"
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: stepBtn.done ? "check" : stepBtn.modelData.icon
                                iconSize: 18
                                fill: stepBtn.active ? 1 : 0
                                color: stepBtn.active ? Appearance.colors.colOnPrimary
                                    : stepBtn.done ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: stepBtn.modelData.name
                            font.weight: stepBtn.active ? Font.DemiBold : Font.Normal
                            color: stepBtn.active || stepBtn.done ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                wrapMode: Text.Wrap
                text: Translation.tr("Everything can be changed later in Settings.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // ── The step: a card, with Back / Next under it ──
        Rectangle {
            id: card
            anchors { left: rail.right; leftMargin: 8; right: parent.right; top: parent.top; bottom: footer.top; margins: 16; bottomMargin: 10 }
            radius: Appearance.rounding.windowRounding
            color: Appearance.colors.colLayer1
            clip: true
            StackLayout {
                id: pages
                anchors.fill: parent
                currentIndex: root.current

                // 1 · Welcome: the wallpaper behind a greeting
                ClippingRectangle {
                    radius: card.radius
                    color: "transparent"
                    Image {
                        anchors.fill: parent
                        source: Config.wallpaperPath ? "file://" + Config.wallpaperPath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 1280
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45) }
                            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.05) }
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 80, 560)
                        spacing: 12
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "NINOMAE"
                            color: Appearance.colors.colPrimary
                            font.pixelSize: 60
                            font.weight: Font.Bold
                            font.letterSpacing: 14
                            font.family: Appearance.font.family.title
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Welcome, %1").arg(SystemInfo.username)
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.hugeass
                            font.family: Appearance.font.family.title
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: Translation.tr("A desktop that takes its colours from your wallpaper. A few quick choices and you're set, in about a minute.")
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // 2 · Look: light/dark and the colours, then the wallpapers
                WelcomePage {
                    title: Translation.tr("Make it yours")
                    subtitle: Translation.tr("Pick a wallpaper. The shell, your apps, the browser and the login screen all take their colours from it.")
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        ButtonGroup {
                            LightDarkPreferenceButton { dark: false }
                            LightDarkPreferenceButton { dark: true }
                        }
                        Item { Layout.fillWidth: true }
                        ColumnLayout { // The colours the wallpaper gives, as they are now
                            spacing: 6
                            StyledText { text: Translation.tr("Your colours"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                            Row {
                                spacing: 6
                                Repeater {
                                    model: [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary,
                                            Appearance.m3colors.m3primaryContainer]
                                    Rectangle {
                                        required property color modelData
                                        width: 28; height: 28; radius: Appearance.rounding.chip
                                        color: modelData
                                        border.width: 1; border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
                                        Behavior on color { ColorAnimation { duration: 400 } }
                                    }
                                }
                            }
                        }
                    }
                    GridView {
                        id: wallpaperGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        readonly property int cols: Math.max(2, Math.floor(width / 200))
                        cellWidth: Math.floor(width / cols)
                        cellHeight: Math.round(cellWidth * 0.62)
                        FolderListModel {
                            id: wallpaperFiles
                            folder: "file://" + root.wallpaperDir
                            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
                            showDirs: false
                            onCountChanged: wallpaperGrid.collect()
                            onStatusChanged: wallpaperGrid.collect()
                        }
                        // Size versions ("name_5120x1440.png") show as their plain wallpaper (WallpaperVariants)
                        property var wallpapers: []
                        function collect() {
                            const list = [];
                            for (let i = 0; i < wallpaperFiles.count; i++) list.push(wallpaperFiles.get(i, "filePath"));
                            wallpapers = WallpaperVariants.withoutVariants(list);
                        }
                        model: wallpapers
                        delegate: Item {
                            id: tile
                            required property string modelData
                            readonly property string filePath: modelData
                            readonly property bool chosen: WallpaperVariants.fileName(WallpaperVariants.plainOf(Config.wallpaperPath))
                                === WallpaperVariants.fileName(filePath)
                            width: wallpaperGrid.cellWidth
                            height: wallpaperGrid.cellHeight
                            ClippingRectangle {
                                anchors { fill: parent; margins: 5 }
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer2
                                scale: thumbArea.containsMouse ? 1.03 : 1
                                Behavior on scale { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + tile.filePath
                                    sourceSize.width: 400 // Decoded at tile size, not the wallpaper's
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Rectangle { // The chosen one: an accent frame and a check
                                    anchors.fill: parent
                                    radius: Appearance.rounding.normal
                                    color: "transparent"
                                    border.width: tile.chosen ? 3 : 0
                                    border.color: Appearance.colors.colPrimary
                                }
                                Rectangle {
                                    visible: tile.chosen
                                    anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                                    width: 26; height: 26; radius: Appearance.rounding.chip
                                    color: Appearance.colors.colPrimary
                                    MaterialSymbol { anchors.centerIn: parent; text: "check"; iconSize: 16; color: Appearance.colors.colOnPrimary }
                                }
                                MouseArea {
                                    id: thumbArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--image", tile.filePath])
                                }
                            }
                        }
                        StyledText {
                            visible: wallpaperGrid.count === 0
                            anchors.centerIn: parent
                            text: Translation.tr("No wallpapers in ~/Pictures/Wallpapers yet")
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // 3 · Layout: the choices on the left, a live mock desktop on the right
                WelcomePage {
                    title: Translation.tr("Arrange your windows")
                    subtitle: Translation.tr("How windows tile, and where the bar sits. Changes apply straight away.")
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 24
                        ColumnLayout {
                            Layout.preferredWidth: 300
                            Layout.alignment: Qt.AlignTop
                            spacing: 14
                            ContentSubsection {
                                Layout.fillWidth: true
                                title: Translation.tr("Tiling")
                                ConfigSelectionArray {
                                    currentValue: Config.options.windows.layoutPreset
                                    onSelected: newValue => { Config.options.windows.layoutPreset = newValue; }
                                    options: [
                                        { displayName: Translation.tr("Auto"), icon: "hdr_auto", value: "auto" },
                                        { displayName: Translation.tr("Normal"), icon: "dashboard", value: "normal" },
                                        { displayName: Translation.tr("Side by side"), icon: "vertical_split", value: "sideBySide" },
                                        { displayName: Translation.tr("Centred"), icon: "center_focus_weak", value: "centred" },
                                        { displayName: Translation.tr("Columns"), icon: "view_week", value: "columns" }
                                    ]
                                }
                            }
                            ContentSubsection {
                                Layout.fillWidth: true
                                title: Translation.tr("Bar style")
                                ConfigSelectionArray {
                                    currentValue: Config.options.bar.cornerStyle
                                    onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                                    options: [
                                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                                        { displayName: Translation.tr("Float"), icon: "page_header", value: 1 },
                                        { displayName: Translation.tr("Square"), icon: "toolbar", value: 2 }
                                    ]
                                }
                            }
                            ContentSubsection {
                                Layout.fillWidth: true
                                title: Translation.tr("Bar position")
                                ConfigSelectionArray {
                                    currentValue: Config.options.bar.bottom ? 1 : 0
                                    onSelected: newValue => { Config.options.bar.bottom = newValue === 1; }
                                    options: [
                                        { displayName: Translation.tr("Top"), icon: "arrow_upward", value: 0 },
                                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 }
                                    ]
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10
                            LayoutPreview {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(width * 10 / 16, parent.height - 60)
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: ({
                                    "auto": Translation.tr("Centred on an ultrawide monitor, regular tiling on anything narrower. Follows the screen you're on."),
                                    "normal": Translation.tr("Each new window splits the space. Best on a normal-width monitor."),
                                    "sideBySide": Translation.tr("Two windows split the screen 50/50. More stack on the right half."),
                                    "centred": Translation.tr("The main window sits in the middle, others stack at the sides. Made for ultrawide monitors."),
                                    "columns": Translation.tr("Scrolling columns, each a third of the screen wide. More scroll in as you move focus.")
                                })[Config.options.windows.layoutPreset] ?? ""
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // 4 · Weather: where the clock drawer's forecast is for, with a live check on the right
                WelcomePage {
                    title: Translation.tr("Your weather")
                    subtitle: Translation.tr("The clock drawer shows the weather and the next hours. Pick a city or let it find you.")
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 24
                        ColumnLayout {
                            Layout.preferredWidth: 300
                            Layout.maximumWidth: 300
                            Layout.alignment: Qt.AlignTop
                            spacing: 14
                            ConfigSwitch {
                                Layout.fillWidth: true
                                buttonIcon: "cloud"
                                text: Translation.tr("Show the weather")
                                option: "bar.weather.enable"
                            }
                            ContentSubsection {
                                Layout.fillWidth: true
                                visible: Config.options.bar.weather.enable
                                title: Translation.tr("Location")
                                ConfigSelectionArray {
                                    currentValue: Config.options.bar.weather.enableGPS ? 1 : 0
                                    onSelected: newValue => { Config.options.bar.weather.enableGPS = newValue === 1; }
                                    options: [
                                        { displayName: Translation.tr("A city"), icon: "location_city", value: 0 },
                                        { displayName: Translation.tr("My location"), icon: "my_location", value: 1 }
                                    ]
                                }
                            }
                            ContentSubsection {
                                Layout.fillWidth: true
                                visible: Config.options.bar.weather.enable && !Config.options.bar.weather.enableGPS
                                title: Translation.tr("City")
                                MaterialTextArea {
                                    Layout.fillWidth: true
                                    text: WeatherLocation.city
                                    onTextChanged: if (text !== WeatherLocation.city) WeatherLocation.setCity(text)
                                }
                            }
                            ContentSubsection {
                                Layout.fillWidth: true
                                visible: Config.options.bar.weather.enable
                                title: Translation.tr("Units")
                                ConfigSelectionArray {
                                    currentValue: Config.options.bar.weather.useUSCS ? 1 : 0
                                    onSelected: newValue => { Config.options.bar.weather.useUSCS = newValue === 1; }
                                    options: [
                                        { displayName: Translation.tr("Celsius"), icon: "thermometer", value: 0 },
                                        { displayName: Translation.tr("Fahrenheit"), icon: "thermometer", value: 1 }
                                    ]
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            WeatherCheck { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // 5 · Gaming
                WelcomePage {
                    title: Translation.tr("Built for games")
                    subtitle: Translation.tr("Your Steam, Lutris and other games in one launcher, with clips and a crosshair when you play.")
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false // As tall as its tallest card; the cards match it
                        columns: 3
                        columnSpacing: 12
                        FeatureCard {
                            icon: "sports_esports"
                            title: Translation.tr("Game launcher")
                            text: Translation.tr("Every game in one place: covers, playtime, news, achievements and screenshots.")
                            keys: root.bindFor("Shell", "Toggle game launcher")
                        }
                        FeatureCard {
                            icon: "movie"
                            title: Translation.tr("Gameplay clips")
                            text: Translation.tr("While a game runs, one key saves the last minute. Clips land in ~/Videos/Clips.")
                            // The backtick alone is too small to read on a keycap: shown as the key's ~ ` legend
                            keys: [((l) => l === "`" ? "~ `" : l)(Config.options.gameLauncher.clipKeyLabel || "`")]
                            switchable: true
                            on: Config.options.gameLauncher.clipsEnabled
                            onToggled: v => Config.options.gameLauncher.clipsEnabled = v
                        }
                        FeatureCard {
                            icon: "my_location"
                            title: Translation.tr("Crosshair")
                            text: Translation.tr("An on-screen crosshair, turned on per game from its page. Design it in Settings.")
                            keys: root.bindFor("Shell", "Show/hide crosshair")
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // 6 · Shortcuts
                WelcomePage {
                    title: Translation.tr("The essentials")
                    subtitle: Translation.tr("A few shortcuts to get around. The full list is one shortcut away.")
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10
                        ShortcutCard { icon: "search"; label: Translation.tr("Launcher, apps and search"); keys: root.bindFor("Shell", "Toggle overview/launcher") }
                        ShortcutCard { icon: "view_sidebar"; label: Translation.tr("Sidebar: toggles, notifications"); keys: root.bindFor("Shell", "Toggle right sidebar") }
                        ShortcutCard { icon: "settings"; label: Translation.tr("Settings"); keys: root.bindFor("Apps", "Settings app") }
                        ShortcutCard { icon: "content_paste"; label: Translation.tr("Clipboard history"); keys: root.bindFor("Shell", "Clipboard history") }
                        ShortcutCard { icon: "screenshot_region"; label: Translation.tr("Screenshot"); keys: root.bindFor("Screen", "Screenshot") }
                        ShortcutCard { icon: "lock"; label: Translation.tr("Lock"); keys: root.bindFor("Session", "Lock screen") }
                        ShortcutCard { icon: "power_settings_new"; label: Translation.tr("Power menu"); keys: root.bindFor("Shell", "Power menu") }
                        ShortcutCard { icon: "keyboard_alt"; label: Translation.tr("Every shortcut, searchable"); keys: root.bindFor("Shell", "Keybinds"); highlighted: true }
                    }
                    Item { Layout.fillHeight: true }
                }

                // 7 · Done
                Item {
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 80, 520)
                        spacing: 14
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 80; implicitHeight: 80; radius: Appearance.rounding.verylarge
                            color: Appearance.colors.colPrimary
                            MaterialSymbol { anchors.centerIn: parent; text: "check"; iconSize: 44; color: Appearance.colors.colOnPrimary }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("You're all set")
                            font.pixelSize: Appearance.font.pixelSize.hugeass
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Everything here, and much more, is in Settings. Type /wallpaper in the launcher to change the wallpaper any time.")
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            spacing: 10
                            RippleButtonWithIcon {
                                materialIcon: "settings"
                                mainText: Translation.tr("Open Settings")
                                onClicked: {
                                    Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh")]);
                                    root.close();
                                }
                            }
                            RippleButtonWithIcon {
                                materialIcon: "keyboard_alt"
                                mainText: Translation.tr("All shortcuts")
                                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/open-settings.sh"), "keybinds"])
                            }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Show this again at next login")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledSwitch {
                                scale: 0.7
                                checked: false
                                onCheckedChanged: root.setShowNextTime(checked)
                            }
                        }
                    }
                }
            }
        }

        // ── Back · Next ──
        RowLayout {
            id: footer
            anchors { left: card.left; right: card.right; bottom: parent.bottom; bottomMargin: 16 }
            height: 44
            RippleButton {
                implicitWidth: 100; implicitHeight: 44
                buttonRadius: Appearance.rounding.container
                opacity: root.current > 0 ? 1 : 0
                enabled: root.current > 0
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: root.back()
                contentItem: RowLayout {
                    spacing: 4
                    MaterialSymbol { Layout.leftMargin: 10; text: "chevron_left"; iconSize: 20; color: Appearance.colors.colOnLayer0 }
                    StyledText { text: Translation.tr("Back"); color: Appearance.colors.colOnLayer0 }
                }
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: Translation.tr("Step %1 of %2").arg(root.current + 1).arg(root.pageCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
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

    // ── Pieces ──────────────────────────────────────────────────────────────
    // A step: title and subtitle, then its content
    // The weather step's right side: the weather for the chosen place once it's found, else what's missing
    component WeatherCheck: Rectangle {
        id: wc
        readonly property bool gps: Config.options.bar.weather.enableGPS
        readonly property string city: WeatherLocation.city.trim()
        readonly property bool found: Weather.locationValid && Weather.data.temp !== ""
            && (gps || (!Weather.cityNotFound && Weather._geocodedCity.trim() === city))
        readonly property string status: {
            if (!Config.options.bar.weather.enable) return Translation.tr("Weather is off. You can turn it on here or in Settings any time.");
            if (gps) return Weather.gpsActive ? Translation.tr("Finding your location…")
                : Translation.tr("Couldn't get your location. Pick a city instead.");
            if (city.length === 0) return Translation.tr("Type a city to see its weather here.");
            if (Weather.cityNotFound) return Translation.tr("No place called “%1” found. Check the spelling.").arg(city);
            return Translation.tr("Looking up %1…").arg(city);
        }
        implicitHeight: 220
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        ColumnLayout { // Found: the weather, as a check that it's the right place
            visible: wc.found && Config.options.bar.weather.enable
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 6
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 14
                MaterialSymbol { text: Weather.data.icon; iconSize: 56; color: Appearance.colors.colPrimary }
                StyledText {
                    text: Weather.data.temp
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer2
                }
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Weather.data.condition
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: wc.gps ? Weather.resolvedCity : Weather.resolvedPlace
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
        RowLayout { // Not found (yet): what's happening or what's missing
            visible: !wc.found || !Config.options.bar.weather.enable
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 12
            MaterialSymbol {
                text: Weather.cityNotFound && !wc.gps ? "wrong_location" : "travel_explore"
                iconSize: 28
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

    component WelcomePage: Item {
        id: page
        property string title
        property string subtitle
        default property alias content: body.data
        ColumnLayout {
            anchors { fill: parent; margins: 28 }
            spacing: 18
            ColumnLayout {
                spacing: 4
                StyledText {
                    text: page.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.subtitle
                    color: Appearance.colors.colSubtext
                }
            }
            ColumnLayout {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
            }
        }
    }

    // The keys of a shortcut, as keycaps
    component Keys: Row {
        property var keys: []
        spacing: 4
        Repeater {
            model: parent.keys
            KeyboardKey { required property string modelData; key: modelData }
        }
    }

    // A shortcut: icon, what it does, its keys. Hidden when the bind isn't there
    component ShortcutCard: Rectangle {
        id: sc
        property string icon
        property string label
        property var keys: []
        property bool highlighted: false
        visible: keys.length > 0
        Layout.fillWidth: true
        implicitHeight: 58
        radius: Appearance.rounding.normal
        color: highlighted ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86) : Appearance.colors.colLayer2
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
            spacing: 12
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: Appearance.rounding.segment
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                MaterialSymbol { anchors.centerIn: parent; text: sc.icon; iconSize: 19; color: Appearance.colors.colPrimary }
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: sc.label
                color: Appearance.colors.colOnLayer2
            }
            Keys { keys: sc.keys }
        }
    }

    // A feature: accent icon, name, what it does, its key, and (switchable) an on/off switch
    component FeatureCard: Rectangle {
        id: fc
        property string icon
        property string title
        property string text
        property var keys: []
        property bool switchable: false
        property bool on: true
        signal toggled(bool value)
        Layout.fillWidth: true
        Layout.fillHeight: true // The row's cards share the tallest one's height
        implicitHeight: fcCol.implicitHeight + 36
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        ColumnLayout {
            id: fcCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 44; implicitHeight: 44; radius: Appearance.rounding.container
                    color: Appearance.colors.colPrimary
                    MaterialSymbol { anchors.centerIn: parent; text: fc.icon; iconSize: 24; color: Appearance.colors.colOnPrimary }
                }
                Item { Layout.fillWidth: true }
                StyledSwitch {
                    visible: fc.switchable
                    scale: 0.8
                    checked: fc.on
                    onClicked: fc.toggled(checked)
                }
            }
            StyledText {
                text: fc.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: fc.text
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            Keys {
                visible: fc.keys.length > 0
                Layout.topMargin: 4
                keys: fc.keys
                opacity: !fc.switchable || fc.on ? 1 : 0.4
            }
        }
    }

    // A small desktop on the current wallpaper: the bar (style, top/bottom) and windows tiled as the
    // chosen layout tiles them; they slide into place as the choices change
    component LayoutPreview: ClippingRectangle {
        id: lp
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        readonly property string preset: Config.options.windows.layoutPreset === "auto" ? "normal" : Config.options.windows.layoutPreset
        readonly property int barStyle: Config.options.bar.cornerStyle
        readonly property bool barBottom: Config.options.bar.bottom
        readonly property real m: 10 // Gaps
        readonly property real barH: Math.round(height * 0.075)
        readonly property real barSpace: barStyle === 1 ? barH + m : barH
        // The area windows tile in, as fractions of it laid out below
        readonly property real ax: m
        readonly property real ay: (barBottom ? 0 : barSpace) + m
        readonly property real aw: width - m * 2
        readonly property real ah: height - barSpace - m * 2
        // Window boxes [x, y, w, h] in fractions of the area; the first has the focus
        readonly property var boxes: ({
            "normal": [[0, 0, 0.5, 1], [0.5, 0, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]],
            "sideBySide": [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]],
            "centred": [[0.25, 0, 0.5, 1], [0, 0, 0.25, 1], [0.75, 0, 0.25, 0.5], [0.75, 0.5, 0.25, 0.5]],
            "columns": [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1], [1, 0, 1 / 3, 1]]
        })[preset] ?? []

        Image {
            anchors.fill: parent
            source: Config.wallpaperPath ? "file://" + Config.wallpaperPath : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 900
        }
        Repeater { // Four slots; the unused ones fade out where they are
            model: 4
            Rectangle {
                required property int index
                readonly property var b: lp.boxes[index] ?? null
                readonly property real g: lp.m / 2
                x: lp.ax + (b ? b[0] : 0.5) * lp.aw + g
                y: lp.ay + (b ? b[1] : 0.5) * lp.ah + g
                width: Math.max(0, (b ? b[2] : 0) * lp.aw - lp.m)
                height: Math.max(0, (b ? b[3] : 0) * lp.ah - lp.m)
                opacity: b ? 1 : 0
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.08)
                border.width: index === 0 ? 2 : 0
                border.color: Appearance.colors.colPrimary
                Behavior on x { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on y { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on height { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Rectangle { // A title bar line, so they read as windows
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
                    height: 4; radius: 2
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                }
            }
        }
        Rectangle { // The bar: Hug sits on the edge, Float is inset and rounded, Rect is a plain strip
            x: lp.barStyle === 1 ? lp.m : 0
            y: lp.barBottom ? lp.height - lp.barH - (lp.barStyle === 1 ? lp.m : 0) : (lp.barStyle === 1 ? lp.m : 0)
            width: lp.width - (lp.barStyle === 1 ? lp.m * 2 : 0)
            height: lp.barH
            radius: lp.barStyle === 1 ? Appearance.rounding.small : 0
            color: Appearance.colors.colLayer0
            Behavior on x { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on y { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Row { // Workspace dots, and a clock pill
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 4
                Repeater { model: 5; Rectangle { required property int index; width: 6; height: 6; radius: 3; color: index === 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant } }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.height * 2.2; height: parent.height * 0.5; radius: height / 2
                color: Appearance.colors.colLayer2
            }
        }
    }
}
