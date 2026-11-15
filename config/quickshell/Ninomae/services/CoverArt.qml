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
 * a local file (browsers write theirs to disk, under a new name each update) is used as it is, except a temporary
 * one in /tmp (Electron apps', YouTube Music's): that's deleted moments later, before the colour reader
 * (CoverTint) gets to it, so it's copied here too and shown from the copy once it's made.
 *
 * Browsers hand over a tiny copy of the art (Firefox and Zen: 60 px), blurry once it's shown bigger. When the
 * page playing is YouTube or YouTube Music, sharpUrl() is YouTube's full-size picture of it instead: show
 * localUrl(sharpUrl) and fall back to the small one until it's downloaded (or when there's none).
 *
 * The YouTube Music app (pear-desktop) hands over a 120 px cover and no link. With its API Server plugin on, its
 * song endpoint (local, localhost:26538) gives the full-size cover: that's asked for on each track and kept as the
 * track's sharp copy. Its access key is asked for once (POST /auth) and kept in the state folder.
 */
Singleton {
    id: root
    property var downloaded: ({}) // url → true. Replaced (never mutated) so bindings see changes
    property var pending: ({})    // url → the Process downloading it

    function pathFor(url: string): string {
        return `${Directories.coverArt}/${Qt.md5(url)}`;
    }
    function isTemporary(url: string): bool { return url.startsWith("file:///tmp/"); }
    function localUrl(url: string): string {
        if (isTemporary(url)) return root.downloaded[url] ? Qt.resolvedUrl(pathFor(url)) : url;
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
        if (url.length === 0 || (url.startsWith("file://") && !isTemporary(url)) || root.downloaded[url] || root.pending[url]) return;
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
            // A temporary local file (file:///tmp/…) is copied rather than fetched
            command: ["bash", "-c", 'p=$1; shift; for u in "$@"; do if [[ $u == file://* ]]; then cp -f -- "${u#file://}" "$p.part"; else curl -fsSL --max-time 15 -o "$p.part" -- "$u"; fi && mv -f "$p.part" "$p" && exit 0; done; rm -f "$p.part"; exit 1',
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

    // ── YouTube Music app: the full-size cover from its local API ──
    readonly property string ytmTokenFile: `${Directories.state}/user/ytmusic_api_token`.replace(/^file:\/\//, "")
    function isYtMusicApp(player): bool { return /youtube-music/i.test(player?.identity ?? ""); }
    function askYtMusic(player): void {
        if (!isYtMusicApp(player) || (player.trackTitle ?? "") === "" || root.sharpByTrack[trackKey(player)]) return;
        ytmComp.createObject(root, { key: trackKey(player), tries: 0 }).running = true;
    }
    Component {
        id: ytmComp
        Process {
            id: ytm
            required property string key // The track it was asked for
            required property int tries // Asked again (a second apart) while the app still names the last song
            // Prints the song's title, artist and cover, one a line. The key is made once (the app may ask you to
            // allow it) and asked for again if it stops working
            command: ["bash", "-c", `f=$1; sleep "$2"; api=http://localhost:26538
key() { curl -fsS --max-time 30 -X POST "$api/auth/ninomae-shell" | sed -n 's/.*"accessToken":"\\([^"]*\\)".*/\\1/p'; }
t=$(cat "$f" 2>/dev/null); [ -n "$t" ] || { t=$(key); [ -n "$t" ] && (umask 077; printf %s "$t" > "$f"); }
song() { curl -fsS --max-time 5 -H "Authorization: Bearer $t" "$api/api/v1/song"; }
out=$(song) || { t=$(key); [ -n "$t" ] && (umask 077; printf %s "$t" > "$f"); out=$(song); } || exit 1
printf %s "$out" | python3 -Ic 'import json,sys; d=json.load(sys.stdin); print(d.get("title") or ""); print(d.get("artist") or ""); print(d.get("imageSrc") or "")'`,
                "ytmusic-cover", root.ytmTokenFile, ytm.tries > 0 ? "1" : "0"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const [title, artist, image] = text.split("\n");
                    // Only for the track it was asked for (the song may have moved on); bigger than the 544 px it says
                    if (image && `${title}\n${artist}` === ytm.key && !root.sharpByTrack[ytm.key]) {
                        const big = image.replace(/=w\d+-h\d+/, "=w1200-h1200");
                        root.sharpByTrack = Object.assign({}, root.sharpByTrack, { [ytm.key]: big });
                    } else if (`${title}\n${artist}` !== ytm.key && ytm.tries < 3) {
                        ytmComp.createObject(root, { key: ytm.key, tries: ytm.tries + 1 }).running = true;
                    }
                    ytm.destroy();
                }
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
            // The YouTube Music app: its full-size cover, a moment after a new track (title and artist come together)
            readonly property string track: root.trackKey(modelData)
            onTrackChanged: Qt.callLater(() => root.askYtMusic(watcher.modelData))
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
                root.askYtMusic(modelData);
                remember();
            }
        }
    }
}
