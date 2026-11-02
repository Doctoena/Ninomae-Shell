import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound
Singleton {
    id: root
    property bool barOpen: true
    // Whether the bar is there on a screen: on, and no fullscreen window (a game) over it. The drawers
    // that grow out of it stand on their own as cards while it isn't (DrawerBackground's followBar)
    function barShownOn(screen) {
        if (!barOpen) return false;
        if (!screen) return true;
        return !(Hyprland.monitorFor(screen)?.activeWorkspace?.toplevels?.values ?? []).some(w => w.wayland?.fullscreen);
    }
    // Where a drawer's top goes: right below the bar, or near the screen's top edge while there's none
    readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
    function drawerTopOn(screen) { return barShownOn(screen) ? barBottom : 10; }
    // Theme transition: while true the wallpaper and colours keep their current look (the new ones are
    // generated in the background), so the change can be revealed in one go
    property bool themeHold: false
    // Where the old wallpaper zooms from as it fades (global coordinates); bumping the serial starts a reveal
    property real themeRevealX: 0
    property real themeRevealY: 0
    property int themeRevealSerial: 0
    property bool gameLauncherOpen: false
    property bool gameOverlayOpen: false // The in-game overlay (modules/gameOverlay, Super+Shift+G)
    property bool gameLauncherFilePickerActive: false
    property bool sidebarRightOpen: false
    property bool sysTrayOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    // Screen-x ranges [x, width] where a drawer is joined to the bar (see common/widgets/BarJoin.qml).
    // The bar skips its bottom border there, otherwise it shows through the translucent drawer as a line.
    property var barJoins: ({})
    function setBarJoin(name, x, width) {
        const current = barJoins[name];
        if (current && current[0] === x && current[1] === width) return;
        let joins = Object.assign({}, barJoins);
        joins[name] = [x, width];
        barJoins = joins;
    }
    function clearBarJoin(name) {
        if (!(name in barJoins)) return;
        let joins = Object.assign({}, barJoins);
        delete joins[name];
        barJoins = joins;
    }
    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }
    property real screenZoom: 1
    onScreenZoomChanged: {
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ cursor = { zoom_factor = ${root.screenZoom} } })`]);
    }
    Behavior on screenZoom {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
    GlobalShortcut {
        name: "gameLauncher"
        description: "Toggle game launcher"
        onPressed: {
            root.gameLauncherOpen = !root.gameLauncherOpen
        }
    }
    IpcHandler {
        target: "zoom"
        function zoomIn() {
            screenZoom = Math.min(screenZoom + 0.4, 3.0)
        }
        function zoomOut() {
            screenZoom = Math.max(screenZoom - 0.4, 1)
        }
    }
}