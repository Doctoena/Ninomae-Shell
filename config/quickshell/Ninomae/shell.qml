//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Adjust this to make the shell smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1
// Log rules for harmless warnings are set in hypr/hyprland/env.lua (QT_LOGGING_RULES)

// ============================================================================
// IMPORTS
// ============================================================================
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// Core UI modules
import qs.modules.bar
import qs.modules.background
import qs.modules.dock
import qs.modules.sidebarRight

// Overlays & Popups
import qs.modules.notificationPopup
import qs.modules.polkit
import qs.modules.regionSelector

// Full-screen interfaces
import qs.modules.lock
import qs.modules.themeTransition
import qs.modules.sessionScreen
import qs.modules.overview
import qs.modules.gameLauncher
import qs.modules.mediaControls

// Utility modules
import qs.modules.onScreenDisplay
import qs.modules.crosshair

// ============================================================================
// MAIN SHELL
// ============================================================================
ShellRoot {
    // ------------------------------------------------------------------------
    // Module Enable/Disable Flags
    // False = not loaded at all (memory efficient)
    // ------------------------------------------------------------------------
    // Core UI
    property bool enableBar: true
    property bool enableBackground: true
    property bool enableDock: true
    property bool enableSidebarRight: true

    // Overlays & Popups
    property bool enableNotificationPopup: true
    property bool enableReloadPopup: true
    property bool enablePolkit: true
    property bool enableRegionSelector: true

    // Full-screen interfaces
    property bool enableLock: true
    property bool enableSessionScreen: true
    property bool enableOverview: true
    property bool enableGameLauncher: true
    property bool enableMediaControls: true

    // Utility modules
    property bool enableOnScreenDisplay: true

    // ------------------------------------------------------------------------
    // Initialize singletons on startup
    // ------------------------------------------------------------------------
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        WindowLayout.load()
        DeviceSettings.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        GameClips.load()
        Crosshair.load()
        WindowRules.load()
        KeybindOverrides.load()
    }

    // ------------------------------------------------------------------------
    // Core UI Components
    // ------------------------------------------------------------------------
    LazyLoader { active: enableBar && Config.ready; component: Bar {} } // Horizontal only (vertical bar removed)
    LazyLoader { active: enableBackground; component: Background {} }
    LazyLoader { active: Config.ready && Config.options.appearance.themeTransition; component: ThemeTransition {} }
    LazyLoader { active: enableDock && Config.options.dock.enable; component: Dock {} }
    LazyLoader { active: enableSidebarRight; component: SidebarRight {} }

    // ------------------------------------------------------------------------
    // Overlays & Popups
    // ------------------------------------------------------------------------
    LazyLoader { active: enableNotificationPopup; component: NotificationPopup {} }
    LazyLoader { active: enableReloadPopup; component: ReloadPopup {} }
    LazyLoader { active: enablePolkit; component: Polkit {} }
    LazyLoader { active: enableRegionSelector; component: RegionSelector {} }

    // ------------------------------------------------------------------------
    // Full-screen Interfaces
    // ------------------------------------------------------------------------
    LazyLoader { active: enableLock; component: Lock {} }
    LazyLoader { active: enableSessionScreen; component: SessionScreen {} }
    LazyLoader { active: enableOverview; component: Overview {} }
    LazyLoader { active: enableGameLauncher; component: GameLauncher {} }
    CrosshairOverlay {}
    LazyLoader { active: enableMediaControls; component: MediaControls {} }

    // ------------------------------------------------------------------------
    // Utility Components
    // ------------------------------------------------------------------------
    LazyLoader { active: enableOnScreenDisplay; component: OnScreenDisplay {} }
}
