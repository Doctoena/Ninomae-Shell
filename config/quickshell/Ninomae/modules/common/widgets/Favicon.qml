import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell.Io
import Quickshell.Widgets
IconImage {
    id: root
    property string url
    property string displayText
    property real size: 32
    property string downloadUserAgent: Config.options?.networking.userAgent ?? ""
    property string faviconDownloadPath: Directories.favicons
    property string domainName: url.includes("vertexaisearch") ? displayText : StringUtils.getDomain(url)
    property string faviconUrl: `https://www.google.com/s2/favicons?domain=${encodeURIComponent(domainName)}&sz=32`
    property string fileName: `${domainName.replace(/[^A-Za-z0-9.-]/g, "_")}.ico` // Comes from a web page: no slashes or quotes in the path
    property string faviconFilePath: `${faviconDownloadPath}/${fileName}`
    property string urlToLoad
    Process {
        id: faviconDownloadProcess
        running: false
        // Values as arguments, never script text (the domain comes from a web page)
        command: ["bash", "-c", '[ -s "$1" ] || curl -fsSL --max-time 10 -A "$3" -o "$1" -- "$2"',
            "favicon", root.faviconFilePath, root.faviconUrl, root.downloadUserAgent]
        onExited: (exitCode, exitStatus) => {
            root.urlToLoad = root.faviconFilePath
        }
    }
    Component.onCompleted: {
        faviconDownloadProcess.running = true
    }
    source: Qt.resolvedUrl(root.urlToLoad)
    implicitSize: root.size
    layer.enabled: true
    layer.effect: RoundedMask { maskWidth: root.implicitSize; maskHeight: root.implicitSize; radius: Appearance.rounding.full }
}