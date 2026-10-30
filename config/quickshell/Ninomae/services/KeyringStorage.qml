pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick
/**
 * For storing sensitive data in the keyring.
 * Use this for small data only, since it stores a JSON of the contents directly and doesn't use a database.
 */
Singleton {
    id: root
    property bool loaded: false
    property var keyringData: ({})
    property var properties: {
        "application": "ninomae-shell",
        "explanation": Translation.tr("For storing API keys and other sensitive information"),
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("ninomae-shell")
    function fetchKeyringData() {
        getData.running = true;
    }
    signal saved(bool ok)
    function saveKeyringData() {
        saveData.stdinEnabled = true;
        saveData.running = true;
    }
    // get("gameLauncher", "steamApiKey") / set(…, value): one value in the stored JSON
    function get(group, key) { return root.keyringData?.[group]?.[key] ?? ""; }
    function set(group, key, value) {
        const data = Object.assign({}, root.keyringData);
        data[group] = Object.assign({}, data[group] ?? {});
        data[group][key] = value;
        root.keyringData = data;
        saveKeyringData();
    }
    Process {
        id: saveData
        command: [
            "secret-tool", "store", "--label=" + keyringLabel,
            ...propertiesAsArgs,
        ]
        onRunningChanged: {
            if (saveData.running) {
                saveData.write(JSON.stringify(root.keyringData));
                stdinEnabled = false // End input stream
            }
        }
        onExited: (exitCode, exitStatus) => root.saved(exitCode === 0)
    }
    Process {
        id: getData
        command: [ // We need to use echo for a newline so splitparser does parse
            "bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`,
        ]
        stdout: StdioCollector {
            id: keyringDataOutputCollector
            onStreamFinished: {
                const data = keyringDataOutputCollector.text;
                if (data.length === 0 || !data.startsWith("{")) return;
                try {
                    root.keyringData = JSON.parse(data);
                } catch (e) {
                    console.error("[KeyringStorage] Failed to get keyring data, reinitializing.");
                    root.keyringData = {};
                    saveKeyringData()
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                console.error("[KeyringStorage] Entry not found, initializing.");
                root.keyringData = {};
                saveKeyringData()
            }
            if (exitCode !== 2) {
                root.loaded = true;
            }
        }
    }
}
