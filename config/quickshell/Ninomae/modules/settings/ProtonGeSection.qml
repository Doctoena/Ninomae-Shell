import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * GE-Proton, in Settings → Games: the latest release, installed with one click (downloaded, checked against
 * its checksum and unpacked into Steam's compatibilitytools.d, where ProtonUp-Qt puts them too), and the
 * installed versions with their size and the games set to them, each removable once nothing uses it.
 * scripts/game-launcher/proton_ge.py does the work. Steam only looks for new versions when it starts, so
 * after an install it offers to restart it. A game's version is picked in its Launch options.
 */
ContentSection {
    id: root
    icon: "wine_bar"
    title: Translation.tr("GE-Proton")
    spacing: 10

    readonly property string script: Quickshell.shellPath("scripts/game-launcher/proton_ge.py")
    property var installed: []
    property bool steamRunning: false
    property var latest: null // { tag, published, bytes }, or { error }
    property string busy: ""  // "install", "remove" or "restart" while one runs
    property string removing: "" // The version being removed
    property real progress: -1
    property string error: ""
    property bool needsRestart: false
    readonly property bool latestInstalled: !!latest?.tag && installed.some(v => (v.version ?? v.name) === latest.tag)

    function size(bytes) {
        return bytes >= 1073741824 ? (bytes / 1073741824).toFixed(1) + " GB" : Math.round(bytes / 1048576) + " MB";
    }
    function usedText(usedBy) {
        if (usedBy.includes("default")) return Translation.tr("Default for all games");
        if (usedBy.length === 1) return Translation.tr("Used by 1 game");
        if (usedBy.length > 1) return Translation.tr("Used by %1 games").arg(usedBy.length);
        return Translation.tr("Not used by any game");
    }
    function refresh() {
        listProc.running = false;
        listProc.running = true;
    }
    function run(kind, args) {
        root.busy = kind;
        root.error = "";
        root.progress = -1;
        actionProc.command = ["python3", "-I", root.script, ...args];
        actionProc.running = true;
    }

    Process {
        id: listProc
        command: ["python3", "-I", root.script, "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.installed = d.installed;
                    root.steamRunning = d.steamRunning;
                } catch (e) {}
            }
        }
    }
    Process {
        id: latestProc
        command: ["python3", "-I", root.script, "latest"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.latest = JSON.parse(text); } catch (e) { root.latest = { error: "" }; }
            }
        }
    }
    Process {
        id: actionProc
        stdout: SplitParser {
            onRead: line => {
                const [word, ...rest] = line.split(" ");
                if (word === "progress") root.progress = parseFloat(rest[0]) || 0;
                else if (word === "error") root.error = rest.join(" ");
                else if (word === "done" && root.busy === "install") root.needsRestart = true;
                else if (word === "done" && root.busy === "restart") root.needsRestart = false;
            }
        }
        onExited: {
            root.busy = "";
            root.removing = "";
            root.refresh();
        }
    }

    // ── The latest release ──
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10
        MaterialSymbol {
            text: "new_releases"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
                text: root.latest === null ? Translation.tr("Checking for the latest version…")
                    : root.latest.tag ? Translation.tr("Latest: %1").arg(root.latest.tag)
                    : Translation.tr("Couldn't check for the latest version")
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: {
                    if (root.busy === "install")
                        return root.progress < 0 ? Translation.tr("Starting the download…")
                            : root.progress < 0.9 ? Translation.tr("Downloading, %1%").arg(Math.floor(root.progress / 0.9 * 100))
                            : Translation.tr("Unpacking…");
                    if (!root.latest?.tag) return "";
                    const date = new Date(root.latest.published).toLocaleDateString(Qt.locale(), "d MMMM yyyy");
                    return Translation.tr("Released %1, a %2 download").arg(date).arg(root.size(root.latest.bytes));
                }
            }
        }
        DialogButton {
            visible: root.latest !== null && !root.latest.tag
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            buttonText: Translation.tr("Try again")
            onClicked: {
                root.latest = null;
                latestProc.running = true;
            }
        }
        DialogButton {
            visible: !!root.latest?.tag
            primary: !root.latestInstalled && root.busy === ""
            enabled: !root.latestInstalled && root.busy === ""
            buttonText: root.latestInstalled ? Translation.tr("Installed")
                : root.busy === "install" ? Translation.tr("Installing…") : Translation.tr("Install")
            onClicked: root.run("install", ["install", root.latest.tag])
        }
    }

    // ── What's installed ──
    ContentSubsection {
        title: Translation.tr("Installed")
        StyledText {
            visible: root.installed.length === 0
            Layout.leftMargin: 8
            text: Translation.tr("None yet")
            color: Appearance.colors.colSubtext
        }
        Repeater {
            model: root.installed
            RowLayout {
                id: versionRow
                required property var modelData
                readonly property bool used: modelData.usedBy.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 10
                MaterialSymbol {
                    text: "wine_bar"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: versionRow.modelData.name
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.size(versionRow.modelData.bytes) + " · " + root.usedText(versionRow.modelData.usedBy)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                DialogButton {
                    // A version a game is set to stays: the game would no longer start
                    enabled: !versionRow.used && root.busy === ""
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    buttonText: root.removing === versionRow.modelData.name ? Translation.tr("Removing…") : Translation.tr("Remove")
                    onClicked: {
                        root.removing = versionRow.modelData.name;
                        root.run("remove", ["remove", versionRow.modelData.name]);
                    }
                }
            }
        }
    }

    // ── After an install: Steam only sees it once it has restarted ──
    RowLayout {
        visible: root.needsRestart && (root.steamRunning || root.busy === "restart")
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10
        MaterialSymbol {
            text: "restart_alt"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("Steam looks for new versions when it starts. Restart it to pick this one in a game's Launch options")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        DialogButton {
            enabled: root.busy === ""
            primary: true
            buttonText: root.busy === "restart" ? Translation.tr("Restarting…") : Translation.tr("Restart Steam")
            onClicked: root.run("restart", ["restart-steam"])
        }
    }

    // ── What went wrong ──
    RowLayout {
        visible: root.error !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 8
        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: "warning"
            iconSize: 18
            color: Appearance.colors.colError
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.error.charAt(0).toUpperCase() + root.error.slice(1)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
