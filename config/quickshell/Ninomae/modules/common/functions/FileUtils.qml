pragma Singleton
import Quickshell
Singleton {
    id: root
    /**
     * Trims the File protocol off the input string
     * @param {string} str
     * @returns {string}
     */
    function trimFileProtocol(str) {
        let s = str;
        if (typeof s !== "string") s = str.toString(); // Convert to string if it's an url or whatever
        // Handle both file:///path (standard) and file:/path (compact) URL forms
        if (s.startsWith("file:///")) return s.slice(7);
        if (s.startsWith("file:/")) return s.slice(5);
        return s;
    }
}
