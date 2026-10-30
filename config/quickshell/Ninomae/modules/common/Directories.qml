pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common.functions
import QtCore
import QtQuick
import Quickshell
Singleton {
    // XDG Dirs, with "file://"
    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0]
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0]
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0]
    // Other dirs used by the shell, without "file://"
    property string assetsPath: Quickshell.shellPath("assets")
    property string scriptPath: Quickshell.shellPath("scripts")
    property string favicons: FileUtils.trimFileProtocol(`${Directories.cache}/media/favicons`)
    property string coverArt: FileUtils.trimFileProtocol(`${Directories.cache}/media/coverart`)
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/ninomae-shell`)
    property string shellConfigName: "config.json"
    property string shellConfigPath: `${Directories.shellConfig}/${Directories.shellConfigName}`
    // Settings → Display, per monitor (services/DeviceSettings.qml). Its own plain JSON file: the config's
    // JsonAdapter crashes when a free-form object field changes while the shell runs
    property string displaysPath: `${Directories.shellConfig}/displays.json`
    property string notificationsPath: FileUtils.trimFileProtocol(`${Directories.cache}/notifications/notifications.json`)
    property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/colors.json`)
    property string cliphistDecode: FileUtils.trimFileProtocol(`/tmp/quickshell/media/cliphist`)
    property string screenshotTemp: "/tmp/quickshell/media/screenshot"
    property string wallpaperSwitchScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/switchwall.sh`)
    // Cleanup on init
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`])
        // Paths are passed as arguments, not pasted into the scripts
        const emptyDir = 'case "$1" in /?*/*) rm -rf -- "$1" ;; esac; mkdir -p -- "$1"' // Never an empty or top-level path
        Quickshell.execDetached(["bash", "-c", emptyDir, "reset-dir", coverArt])
        Quickshell.execDetached(["bash", "-c", emptyDir, "reset-dir", cliphistDecode])
        // Symlink generated dir from scripts' state path to QS state path
        const scriptsGenDir = FileUtils.trimFileProtocol(home) + "/.local/state/quickshell/user/generated"
        const qsGenDir = FileUtils.trimFileProtocol(state) + "/user/generated"
        Quickshell.execDetached(["bash", "-c", 'mkdir -p -- "$1" && [ ! -e "$2" ] && mkdir -p -- "$(dirname -- "$2")" && ln -sfn -- "$1" "$2" || true',
            "link-generated", scriptsGenDir, qsGenDir])
    }
}
