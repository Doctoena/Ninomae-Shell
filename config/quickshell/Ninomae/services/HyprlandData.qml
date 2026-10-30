pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common

/**
 * Provides access to Hyprland data not available in Quickshell.Hyprland.
 * Only the window list is kept live (the bar's workspace icons use it). Monitors, layers and
 * workspaces are fetched on demand with updateAll(), e.g. when the region selector opens.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Everything, once (the region selector calls this when it opens)
    function updateAll() {
        getAllData.runNow()
    }
    function updateWindows() {
        getWindows.trigger()
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId)
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0)
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0)
            return winArea > maxArea ? win : maxWin
        }, null)
    }

    Component.onCompleted: updateAll()

    // Events that can't change the window list's workspaces, sizes or classes. Title changes are
    // the big one: terminals and browsers send them constantly
    readonly property var ignoredEvents: new Set(["activelayout", "submap", "bell", "screencast", "windowtitle",
        "windowtitlev2", "activewindow", "urgent", "minimized", "lockgroups", "ignoregrouplock", "focusedmon",
        "focusedmonv2", "activespecial", "activespecialv2", "openlayer", "closelayer", "custom"])

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.ignoredEvents.has(event.name))
                root.updateWindows()
        }
    }

    function applyWindows(json) {
        root.windowList = JSON.parse(json)
        const tempWinByAddress = {}
        for (let i = 0; i < root.windowList.length; ++i) {
            const win = root.windowList[i]
            tempWinByAddress[win.address] = win
        }
        root.windowByAddress = tempWinByAddress
        root.addresses = root.windowList.map(win => win.address)
    }

    PollingProcess {
        id: getWindows
        debounce: 100 // Events come in bursts
        command: ["hyprctl", "-j", "clients"]
        onResult: text => {
            try {
                root.applyWindows(text)
            } catch (e) {
                console.error("[HyprlandData] Failed to parse clients:", e)
            }
        }
    }

    // Single hyprctl call for everything; --batch separates each reply with two blank lines
    PollingProcess {
        id: getAllData
        command: ["hyprctl", "-j", "--batch", "clients; monitors; layers; workspaces; activeworkspace"]
        onResult: text => {
            {
                try {
                    const parts = text.split("\n\n\n").map(s => s.trim())
                    if (parts[0]) root.applyWindows(parts[0])
                    if (parts[1]) root.monitors = JSON.parse(parts[1])
                    if (parts[2]) root.layers = JSON.parse(parts[2])
                    if (parts[3]) {
                        root.workspaces = JSON.parse(parts[3])
                        const tempWorkspaceById = {}
                        for (let i = 0; i < root.workspaces.length; ++i) {
                            const ws = root.workspaces[i]
                            tempWorkspaceById[ws.id] = ws
                        }
                        root.workspaceById = tempWorkspaceById
                        root.workspaceIds = root.workspaces.map(ws => ws.id)
                    }
                    if (parts[4]) root.activeWorkspace = JSON.parse(parts[4])
                } catch (e) {
                    console.error("[HyprlandData] Failed to parse batch data:", e)
                }
            }
        }
    }
}
