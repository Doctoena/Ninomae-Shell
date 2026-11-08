pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

/**
 * Album art cache shared by the bar's media pill and the media panel, so a track's art is
 * downloaded once. Files are named by the URL's hash in Directories.coverArt.
 *
 *   readonly property string art: CoverArt.coverFor(player)
 *
 * Every player's art is fetched here as it changes, so whatever shows it only asks coverFor().
 * localUrl() is "" until the file is there, and bindings update when it arrives. Art that's already
 * a local file (browsers write theirs to disk, under a new name each update) is used as it is.
 *
 * Browsers hand over a tiny copy of the art (Firefox and Zen: 60 px), blurry once it's shown bigger. When the
 * page playing is YouTube or YouTube Music, sharpUrl() is YouTube's full-size picture of it instead: show
 * localUrl(sharpUrl) and fall back to the small one until it's downloaded (or when there's none).
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
    // YouTube's full-size picture of what's playing, or "". The browser reports the tab's address (xesam:url),
    // which names the video only on its own page: browsing YouTube Music while it plays shows a playlist or the
    // home page instead. So each track's picture is remembered once seen, and kept while you browse
    property var sharpByTrack: ({}) // "title\nartist" → picture URL. Replaced (never mutated) so bindings see changes
    function trackKey(player): string {
        return `${player?.trackTitle ?? ""}\n${player?.trackArtist ?? ""}`;
    }
    function pageSharpUrl(player): string {
        const page = player?.metadata?.["xesam:url"] ?? "";
        const id = page.match(/^https?:\/\/(?:music\.|www\.|m\.)?youtube\.com\/watch\?(?:.*&)?v=([\w-]{11})/)?.[1]
            ?? page.match(/^https?:\/\/youtu\.be\/([\w-]{11})/)?.[1];
        return id ? `https://i.ytimg.com/vi/${id}/maxresdefault.jpg` : "";
    }
    function sharpUrl(player): string {
        return pageSharpUrl(player) || (root.sharpByTrack[trackKey(player)] ?? "");
    }
    // The cover to show for a player: the sharp copy once it's here, else the player's own (or "")
    function coverFor(player): string {
        return localUrl(sharpUrl(player)) || localUrl(player?.trackArtUrl ?? "");
    }
    // Where to fetch a URL from, best first: not every video has the biggest YouTube picture
    function sources(url: string): list<string> {
        const yt = url.match(/^(https:\/\/i\.ytimg\.com\/vi\/[\w-]{11}\/)maxresdefault\.jpg$/)?.[1];
        return yt ? [url, `${yt}hq720.jpg`, `${yt}hqdefault.jpg`] : [url];
    }
    function request(url: string): void {
        if (url.length === 0 || url.startsWith("file://") || root.downloaded[url] || root.pending[url]) return;
        const proc = downloaderComp.createObject(root, { url: url, path: pathFor(url), sources: sources(url) });
        root.pending = Object.assign({}, root.pending, { [url]: proc });
        proc.running = true;
    }

    Component {
        id: downloaderComp
        Process {
            id: proc
            required property string url
            required property string path
            required property list<string> sources
            // URL and path go in as arguments, never into the script text: the URL comes from whatever is
            // playing (any website), and a quote in it would otherwise run as shell code. Each source is tried
            // in turn, downloaded to a temp file and kept only if curl succeeded, so a failed fetch isn't
            // cached as "the art". Fetched once a session (`downloaded` skips repeats); the folder keeps files
            // for two days (Directories.qml prunes older ones at startup)
            command: ["bash", "-c", 'p=$1; shift; for u in "$@"; do curl -fsSL --max-time 15 -o "$p.part" -- "$u" && mv -f "$p.part" "$p" && exit 0; done; rm -f "$p.part"; exit 1',
                "coverart", proc.path, ...proc.sources]
            onExited: exitCode => {
                const pending = Object.assign({}, root.pending);
                delete pending[proc.url];
                root.pending = pending;
                if (exitCode === 0) root.downloaded = Object.assign({}, root.downloaded, { [proc.url]: true });
                proc.destroy();
            }
        }
    }

    // Each player's art and its sharp copy, fetched as soon as they change
    Instantiator {
        model: Mpris.players
        delegate: QtObject {
            id: watcher
            required property MprisPlayer modelData
            readonly property string art: modelData?.trackArtUrl ?? ""
            readonly property string sharp: root.sharpUrl(modelData)
            readonly property string pageSharp: root.pageSharpUrl(modelData)
            onArtChanged: root.request(art)
            onSharpChanged: root.request(sharp)
            // Remembered a moment later: a new track's address and title don't arrive in the same instant
            onPageSharpChanged: Qt.callLater(watcher.remember)
            function remember() {
                const key = root.trackKey(modelData);
                if (pageSharp && key !== "\n" && root.sharpByTrack[key] !== pageSharp)
                    root.sharpByTrack = Object.assign({}, root.sharpByTrack, { [key]: pageSharp });
            }
            Component.onCompleted: {
                root.request(art);
                root.request(sharp);
                remember();
            }
        }
    }
}
