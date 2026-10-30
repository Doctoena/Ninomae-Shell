pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property string firstRunFilePath: `${Directories.state}/user/first_run.txt`
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string defaultWallpaperPath: FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper.png`)
    property string welcomeQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("welcome.qml"))
    function load() {
        firstRunFileView.reload()
    }
    function handleFirstRun() {
        // Only when no wallpaper is set yet: install.sh already picks one (and generates its colours),
        // and replacing it here undid that on the first login
        if ((Config.options?.background?.wallpaperPath ?? "") === "")
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath])
        Quickshell.execDetached(["qs", "-p", root.welcomeQmlPath])
    }
    FileView {
        id: firstRunFileView
        path: Qt.resolvedUrl(firstRunFilePath)
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                firstRunFileView.setText(root.firstRunFileContent)
                root.handleFirstRun()
            }
        }
    }
}
