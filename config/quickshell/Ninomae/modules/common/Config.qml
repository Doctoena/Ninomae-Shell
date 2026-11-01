pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false
    // Paths are stored with "~/" instead of the home folder, so config.json has no user-specific paths
    // (it's part of the dotfiles). Read the wallpaper through these, not options.background directly
    readonly property string wallpaperPath: expandHome(options.background.wallpaperPath)
    readonly property string thumbnailPath: expandHome(options.background.thumbnailPath)
    function expandHome(path) {
        return (path ?? "").startsWith("~/") ? Quickshell.env("HOME") + path.substring(1) : (path ?? "");
    }
    // An option by its dotted key ("bar.weather.enable"), for the Settings widgets' `option` property.
    // Read inside a binding, it follows the option like a direct Config.options.… read would
    function get(key) {
        return key.split(".").reduce((obj, part) => obj?.[part], root.options);
    }
    function set(key, value) {
        const parts = key.split(".");
        const last = parts.pop();
        const obj = parts.reduce((o, part) => o?.[part], root.options);
        if (obj && obj[last] !== value) obj[last] = value;
    }
    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        // Traverse to the parent object.
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
        }
        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }
        obj[keys[keys.length - 1]] = convertedValue;
    }
    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload()
        }
    }
    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.writeAdapter()
        }
    }
    // config.json is each machine's own (git ignores it). The first time, it starts as a copy of the shipped
    // config.default.json, or from the defaults below if that's missing too
    Process {
        id: firstConfig
        command: ["cp", "-n", `${Directories.shellConfig}/config.default.json`, root.filePath]
        onExited: (code, status) => {
            if (code === 0) configFileView.reload();
            else configFileView.writeAdapter();
        }
    }
    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error != FileViewError.FileNotFound) return;
            // Deleted while running (a git pull, say): write back the settings in use
            if (root.ready) writeAdapter();
            else firstConfig.running = true;
        }
        JsonAdapter {
            id: configOptionsJsonAdapter
            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                property bool themeTransition: true // Circular reveal when the wallpaper/colours change
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property bool forceDarkMode: false
                    }
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                }
            }
            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }
            // What the menus' Settings buttons and the session screen's Tasks open (no KDE here)
            property JsonObject apps: JsonObject {
                property string bluetooth: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "blueman-manager" "kitty -1 bluetoothctl"`
                property string network: "nm-connection-editor"
                property string networkEthernet: "nm-connection-editor"
                property string taskManager: "kitty -1 btop"
                property string terminal: "kitty -1" // This is only for shell actions
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }
            property JsonObject background: JsonObject {
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                property bool hideWhenFullscreen: true
                property JsonObject parallax: JsonObject {
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.07 // Relative to your screen, not wallpaper size
                }
            }
            property JsonObject bar: JsonObject {
                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Square (a plain strip)
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
                property bool borderless: false // true for no grouping of items
                property bool showBackground: true
                property bool verbose: true
                property JsonObject resources: JsonObject {
                    property int memoryWarningThreshold: 95
                    property int cpuWarningThreshold: 90
                }
                property list<string> screenList: ["eDP-1", "DP-1"] // List of names, like "eDP-1", find out with 'hyprctl monitors' command. Leave only one monitor name to show bar on one display
                property JsonObject tray: JsonObject {
                    property bool monochromeIcons: true
                    property bool showItemId: false
                    property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                    property list<string> pinnedItems: [ ]
                    property bool filterPassive: true
                }
                property JsonObject workspaces: JsonObject {
                    property int shown: 10
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useNerdFont: false
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // Older setups only: the city is in WeatherLocation.qml's file, out of the repo
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                    property JsonObject battery: JsonObject {
                        property bool show: true
                    }
                }
            }
            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }
            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }
            property JsonObject crosshair: JsonObject {
                property list<string> games: [] // Launcher game ids it shows in (the crosshair button under Play on a game's page)
                property string color: "accent" // "accent", or "#rrggbb"
                property bool outline: true
                property int outlineThickness: 1
                property int outlineOpacity: 60 // %, of each part's own
                property bool dot: false
                property int dotSize: 2
                property int dotOpacity: 100
                property bool lines: true // Inner lines
                property bool topLine: true // Off: a T (inner and outer)
                property int length: 6
                property int verticalLength: 0 // 0: same as length
                property int thickness: 2
                property int gap: 3
                property int lineOpacity: 100
                property bool outerLines: false
                property int outerLength: 2
                property int outerThickness: 2
                property int outerGap: 10
                property int outerOpacity: 50
                property bool circle: false
                property int circleRadius: 10
                property int circleThickness: 1
                property int circleOpacity: 100
            }
            property JsonObject dock: JsonObject {
                property bool enable: false
                property bool monochromeIcons: true
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.gnome.Nautilus", "kitty",]
                property list<string> ignoredAppRegexes: []
            }
            property JsonObject gameLauncher: JsonObject {
                property string sortOrder: "recency"
                property bool fallbackToIcons: true
                property bool hideWithoutBoxArt: true
                property bool hidePartialBoxArt: true
                property bool launchAnimation: true // Drawer under the bar following a launched game until its window opens (LaunchSplash.qml)
                property bool newsUpdatesOnly: false // News sheet: only game updates (patch notes), not events and promos
                property string steamApiKey: ""
                property string steamGridDbApiKey: ""
                property bool immichEnabled: false // Screenshots panel: upload button to an Immich server
                property string immichUrl: "" // Older setups only: the server URL is in the keyring with its key, out of the dotfiles
                // Gameplay clips (services/GameClips.qml): a replay buffer while a game runs, saved with `
                property bool clipsEnabled: true
                property bool overlayEnabled: true // The in-game overlay (Super+Shift+G, modules/gameOverlay)
                property int clipSeconds: 60
                property bool clipMic: true // Your mic mixed in with the game audio
                property string clipsFolder: "~/Videos/Clips"
                property string clipKey: "grave"   // The save key as Hyprland writes it ("SUPER + F9", "code:49"…)
                property string clipKeyLabel: "`"  // …and as it's shown
            }
            // Settings → Input (applied by services/DeviceSettings.qml over hypr/hyprland/general.lua's values,
            // which these defaults match)
            property JsonObject input: JsonObject {
                property JsonObject keyboard: JsonObject {
                    property int repeatRate: 35 // Repeats per second
                    property int repeatDelay: 250 // ms before a held key repeats
                    property bool numlockByDefault: true
                }
                property JsonObject mouse: JsonObject {
                    property real sensitivity: 0 // -1 to 1
                    property string accelProfile: "flat" // "adaptive" or "flat"
                    property bool naturalScroll: false
                    property real scrollFactor: 1
                    property bool leftHanded: false
                }
                property JsonObject touchpad: JsonObject {
                    property bool tapToClick: true
                    property bool naturalScroll: false
                    property bool disableWhileTyping: true
                    property real scrollFactor: 1
                    property bool clickfinger: false // Two-finger click = right click (instead of the bottom-right corner)
                    property bool tapAndDrag: true
                }
            }
            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }
            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
            }
            property JsonObject lock: JsonObject {
                property bool launchOnStartup: false
                property JsonObject blur: JsonObject {
                    property bool enable: false
                    property real radius: 100
                    property real extraZoom: 1.1
                }
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
            }
            property JsonObject media: JsonObject {
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true
            }
            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }
            property JsonObject notifications: JsonObject {
                property int timeout: 7000
            }
            property JsonObject osd: JsonObject {
                property int timeout: 1000
            }
            property JsonObject regionSelector: JsonObject {
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                // Screenshots are always copied; with save on they're also kept in saveDir (~ allowed)
                property bool save: true
                property string saveDir: "~/Pictures/Screenshots"
            }
            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
            }
            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
            }
            property JsonObject sidebar: JsonObject {
                property bool keepRightSidebarLoaded: true
                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        property list<var> toggles: [
                            { "size": 2, "type": "network" },
                            { "size": 2, "type": "bluetooth"  },
                            { "size": 1, "type": "idleInhibitor" },
                            { "size": 1, "type": "mic" },
                            { "size": 2, "type": "audio" },
                            { "size": 2, "type": "nightLight" }
                        ]
                    }
                }
                property JsonObject quickSliders: JsonObject {
                    property bool enable: false
                    property bool showMic: false
                    property bool showVolume: true
                    property bool showBrightness: true
                }
                property JsonObject resourceMonitor: JsonObject {
                    property bool enable: true
                }
            }
            property JsonObject sounds: JsonObject {
                property bool battery: false
                property string theme: "freedesktop"
            }
            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm" // 12-hour: "h:mm AP"
                property bool showAmPm: true // false hides AM/PM from a 12-hour format (the bar shows "8:15")
                property string dateFormat: "ddd, dd/MM"
                property bool secondPrecision: false
            }
            property JsonObject windows: JsonObject {
                property string layoutPreset: "auto" // auto | centred | sideBySide | columns | normal (services/WindowLayout.qml)
            }
            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }
        }
    }
}
