pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.modules.common

/**
 * Size versions of a wallpaper. "name_5120x1440.png" (or "name_5120x1440(1).png", as a browser names a second
 * download) is a version of "name.png" for screens of that shape. Each screen shows the version closest to
 * its own shape, and the pickers list the pair as one wallpaper: the plain one. Matched by file name, since
 * the same folder can be reached through a symlink.
 */
Singleton {
    id: root

    function fileName(path) { return path.replace(/^.*\//, ""); }
    function folderOf(path) { return path.replace(/\/[^\/]*$/, ""); }
    function stem(name) { return name.replace(/\.[^.]+$/, ""); }
    // { base, width, height } for a size version's name, else null
    function parse(name) {
        const m = /^(.+)_(\d+)x(\d+) ?(?:\(\d+\))?\.[^.]+$/.exec(name);
        return m ? { base: m[1], width: Number(m[2]), height: Number(m[3]) } : null;
    }

    // The list without size versions whose plain wallpaper is in it too
    function withoutVariants(paths) {
        const plain = paths.map(fileName).filter(n => !parse(n)).map(stem);
        return paths.filter(p => {
            const v = parse(fileName(p));
            return !v || !plain.includes(v.base);
        });
    }
    // The plain wallpaper for a size version (in the same folder), or the path itself
    function plainOf(path, paths = root.files) {
        const v = parse(fileName(path));
        if (!v) return path;
        const match = paths.map(fileName).find(n => !parse(n) && stem(n) === v.base);
        return match ? `${folderOf(path)}/${match}` : path;
    }
    // The version of `path` for a screen: a size version within 10% of the screen's shape, else the plain one
    function forScreen(path, screenWidth, screenHeight, paths = root.files) {
        if (!path || !screenWidth || !screenHeight) return path;
        const plain = plainOf(path, paths);
        const base = stem(fileName(plain));
        const screenRatio = screenWidth / screenHeight;
        let best = "", bestOff = Infinity;
        for (const name of paths.map(fileName)) {
            const v = parse(name);
            if (!v || v.base !== base) continue;
            const off = Math.abs(Math.log(v.width / v.height / screenRatio));
            if (off < bestOff) { best = name; bestOff = off; }
        }
        return bestOff < Math.log(1.1) ? `${folderOf(plain)}/${best}` : plain;
    }

    // The files beside the current wallpaper, for the background's per-screen choice
    property var files: []
    FolderListModel {
        id: folderModel
        folder: Config.wallpaperPath ? "file://" + root.folderOf(Config.wallpaperPath) : ""
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) root.collect()
        onCountChanged: root.collect()
    }
    function collect() {
        const list = [];
        for (let i = 0; i < folderModel.count; i++) list.push(folderModel.get(i, "fileName"));
        root.files = list;
    }
}
