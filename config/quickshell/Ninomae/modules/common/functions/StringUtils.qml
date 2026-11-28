pragma Singleton
import QtQuick
import Quickshell
Singleton {
    id: root
    /**
     * Opens a link that came from outside (a notification, a game's news) only if it's a web or email link:
     * file://, steam:// and other schemes could start programs or open files. Returns whether it opened
     */
    function openWebLink(link) {
        if (!/^(https?:|mailto:)/i.test(String(link ?? "").trim())) {
            console.warn("[StringUtils] not opening a link that isn't a web or email link:", link);
            return false;
        }
        Qt.openUrlExternally(String(link).trim());
        return true;
    }
    /**
     * Formats a string according to the args that are passed inc
     * @param { string } str
     * @param  {...any} args
     * @returns { string }
     */
    function format(str, ...args) {
        return str.replace(/{(\d+)}/g, (match, index) => typeof args[index] !== 'undefined' ? args[index] : match);
    }
    /**
     * Returns the domain of the passed in url or null
     * @param { string } url
     * @returns { string| null }
     */
    function getDomain(url) {
        const match = url.match(/^(?:https?:\/\/)?(?:www\.)?([^\/]+)/);
        return match ? match[1] : null;
    }
    /**
     * Cleans up a music title: leading bracketed bits, the tags videos carry ("[uncensored]",
     * "(Official Music Video)", "(Lyrics)") and, given the artist, the artist repeated in it ("Song - Artist")
     * @param { string } title
     * @param { string } artist
     * @returns { string }
     */
    function cleanMusicTitle(title, artist = "") {
        if (!title)
            return "";
        // Brackets
        title = title.replace(/^ *\([^)]*\) */g, " "); // Round brackets
        title = title.replace(/^ *\[[^\]]*\] */g, " "); // Square brackets
        title = title.replace(/^ *\{[^\}]*\} */g, " "); // Curly brackets
        // Japenis brackets
        title = title.replace(/^ *【[^】]*】/, ""); // Touhou
        title = title.replace(/^ *《[^》]*》/, ""); // ??
        title = title.replace(/^ *「[^」]*」/, ""); // OP/ED thingie
        title = title.replace(/^ *『[^』]*』/, ""); // OP/ED thingie
        // Video tags, anywhere: (Official Video), [Official HD Music Video], (Lyrics), [uncensored], (4K)…
        title = title.replace(/\s*[\[(][^\])]*\b(?:official|lyrics?|audio|visuali[sz]er|uncensored|explicit|hd|hq|4k|mv|m\/v|music video|video clip)\b[^\])]*[\])]/gi, "");
        // The artist repeated: "Song - Artist" or "Artist - Song"
        const a = String(artist ?? "").trim();
        if (a !== "") {
            const esc = a.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            const cut = title.replace(new RegExp(`\\s+[-–—|]\\s+${esc}\\s*$`, "i"), "").replace(new RegExp(`^${esc}\\s+[-–—]\\s+`, "i"), "");
            if (cut.trim() !== "") title = cut;
        }
        return title.trim();
    }
    /**
     * Converts seconds to a friendly time string (e.g. 1:23 or 1:02:03).
     * @param { number } seconds
     * @returns { string }
     */
    function friendlyTimeForSeconds(seconds) {
        if (isNaN(seconds) || seconds < 0)
            return "0:00";
        seconds = Math.floor(seconds);
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        if (h > 0) {
            return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
        } else {
            return `${m}:${s.toString().padStart(2, '0')}`;
        }
    }
    /**
     * Escapes HTML special characters in a string.
     * @param { string } str
     * @returns { string }
     */
    function escapeHtml(str) {
        if (typeof str !== 'string')
            return str;
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }
    /**
     * Cleans a cliphist entry by removing leading digits and tab.
     * @param { string } str
     * @returns { string }
     */
    function cleanCliphistEntry(str: string): string {
        return str.replace(/^\d+\t/, "");
    }
    /**
     * Removes the given prefix from the string if present.
     * @param { string } str
     * @param { string } prefix
     * @returns { string }
     */
    function cleanPrefix(str, prefix) {
        if (str.startsWith(prefix)) {
            return str.slice(prefix.length);
        }
        return str;
    }
    /**
     * Removes the first matching prefix from the string if present.
     * @param { string } str
     * @param { string[] } prefixes
     * @returns { string }
     */
    function cleanOnePrefix(str, prefixes) {
        for (let i = 0; i < prefixes.length; ++i) {
            if (str.startsWith(prefixes[i])) {
                return str.slice(prefixes[i].length);
            }
        }
        return str;
    }
}
