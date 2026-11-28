pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * The weather city. It's personal, so it lives in its own file in the state folder instead of config.json
 * (which is in the public Ninomae-Shell repo). The shell, Settings and the welcome window each load this:
 * the file is watched, so a city set in one shows up in the others.
 */
Singleton {
    id: root
    readonly property string path: FileUtils.trimFileProtocol(`${Directories.state}/user/weather_city.txt`)
    property string city: ""
    property bool loaded: false

    // Typing in a city field calls this on every key: the file (and the shell's lookup) waits for a pause
    function setCity(name) {
        root.city = name;
        saveTimer.restart();
    }
    Timer {
        id: saveTimer
        interval: 700
        onTriggered: cityFile.setText(root.city.trim())
    }

    FileView {
        id: cityFile
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!saveTimer.running) root.city = text().trim(); // Not while a typed city waits to be saved
            root.loaded = true;
            root.moveFromConfig();
        }
        onLoadFailed: error => {
            root.loaded = true; // No file yet
            root.moveFromConfig();
        }
    }

    // Older setups kept the city in config.json: move it here once, then clear it there
    function moveFromConfig() {
        if (!root.loaded || !Config.ready) return;
        const old = (Config.options.bar.weather.city ?? "").trim();
        if (old.length === 0) return;
        if (root.city.length === 0) {
            root.city = old;
            cityFile.setText(old);
        }
        Config.options.bar.weather.city = "";
    }
    Connections {
        target: Config
        function onReadyChanged() { root.moveFromConfig(); }
    }
}
