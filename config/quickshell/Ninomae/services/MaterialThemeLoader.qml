pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Automatically reloads generated material colors.
 * Uses proper file loading callbacks instead of race condition delays.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath
    property bool isLoaded: false
    // Theme transition: hold new colours until release() so they appear together with the reveal
    property bool hold: false
    property string pendingContent: ""
    function release() {
        hold = false;
        if (pendingContent.length > 0) {
            const content = pendingContent;
            pendingContent = "";
            applyColors(content);
        }
    }

    function reapplyTheme() {
        isLoaded = false
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        if (!fileContent || fileContent.length === 0) return
        try {
            const json = JSON.parse(fileContent)
            for (const key in json) {
                if (json.hasOwnProperty(key)) {
                    const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                    const m3Key = `m3${camelCaseKey}`
                    Appearance.m3colors[m3Key] = json[key]
                }
            }
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
            isLoaded = true
        } catch (e) {
            console.error("[MaterialThemeLoader] Failed to parse theme file:", e)
        }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    // Reset file path on wallpaper change
    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options?.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    // FileView with proper loading callbacks - no timer needed
    FileView {
        id: themeFileView
        path: root.filePath ? Qt.resolvedUrl(root.filePath) : ""
        watchChanges: true

        onLoaded: {
            const fileContent = themeFileView.text()
            if (fileContent && fileContent.length > 0) {
                if (root.hold) root.pendingContent = fileContent
                else root.applyColors(fileContent)
            }
        }

        onLoadFailed: (error) => {
            console.error("[MaterialThemeLoader] Failed to load theme file:", error)
            root.resetFilePathNextTime()
        }

        onFileChanged: {
            // File changed - reload will be triggered automatically by FileView
            this.reload()
        }
    }
}
