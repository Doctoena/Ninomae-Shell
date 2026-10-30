pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Album art cache shared by the bar's media pill and the media panel, so a track's art is
 * downloaded once. Files are named by the URL's hash in Directories.coverArt.
 *
 *   readonly property string art: CoverArt.localUrl(player?.trackArtUrl ?? "")
 *   onArtUrlChanged: CoverArt.request(artUrl)
 *
 * localUrl() is "" until the file is there, and bindings update when it arrives. Art that's already
 * a local file (browsers write theirs to disk, under a new name each update) is used as it is.
 */
Singleton {
    id: root
    property var downloaded: ({}) // url → true. Replaced (never mutated) so bindings see changes
    property var pending: ({})    // url → the Process downloading it

    function pathFor(url: string): string {
        return `${Directories.coverArt}/${Qt.md5(url)}`;
    }
    function localUrl(url: string): string {
        if (url.startsWith("file://")) return url;
        return url.length > 0 && root.downloaded[url] ? Qt.resolvedUrl(pathFor(url)) : "";
    }
    function request(url: string): void {
        if (url.length === 0 || url.startsWith("file://") || root.downloaded[url] || root.pending[url]) return;
        const proc = downloaderComp.createObject(root, { url: url, path: pathFor(url) });
        root.pending = Object.assign({}, root.pending, { [url]: proc });
        proc.running = true;
    }

    Component {
        id: downloaderComp
        Process {
            id: proc
            required property string url
            required property string path
            // URL and path go in as arguments, never into the script text: the URL comes from whatever is
            // playing (any website), and a quote in it would otherwise run as shell code. Download to a
            // temp file and keep it only if curl succeeded, so a failed fetch isn't cached as "the art".
            // Always fetches: the folder is emptied at startup (Directories.qml), so a file still there
            // when the shell starts may be deleted a moment later; within a session `downloaded` skips repeats
            command: ["bash", "-c", '{ curl -fsSL --max-time 15 -o "$1.part" -- "$2" && mv -f "$1.part" "$1"; } || { rm -f "$1.part"; exit 1; }',
                "coverart", proc.path, proc.url]
            onExited: exitCode => {
                const pending = Object.assign({}, root.pending);
                delete pending[proc.url];
                root.pending = pending;
                if (exitCode === 0) root.downloaded = Object.assign({}, root.downloaded, { [proc.url]: true });
                proc.destroy();
            }
        }
    }
}
