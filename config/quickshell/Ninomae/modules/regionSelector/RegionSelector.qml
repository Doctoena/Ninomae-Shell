pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The screenshot tool (Super+Shift+A; Super+Shift+S searches): a frozen frame on every screen to pick a
 * region on (RegionSelection), then snip.sh does the picked action with it. The action and the shape are
 * kept here, so a change on one screen's toolbar shows on all of them.
 * IPC: `qs -c Ninomae ipc call region screenshot|edit|search|ocr|close`
 */
Scope {
    id: root
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners

    function open(action, mode) {
        root.action = action;
        root.selectionMode = mode ?? RegionSelection.SelectionMode.RectCorners;
        GlobalStates.regionSelectorOpen = true;
    }
    function dismiss() { GlobalStates.regionSelectorOpen = false; }
    function screenshot() { open(RegionSelection.SnipAction.Copy); }
    function edit() { open(RegionSelection.SnipAction.Edit); }
    function search() {
        open(RegionSelection.SnipAction.Search, Config.options.search.imageSearch.useCircleSelection
            ? RegionSelection.SelectionMode.Circle : RegionSelection.SelectionMode.RectCorners);
    }
    function ocr() { open(RegionSelection.SnipAction.CharRecognition); }

    // Layers and monitors aren't kept live (services/HyprlandData.qml): fetch them for this selection
    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen) HyprlandData.updateAll();
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen
            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                action: root.action
                selectionMode: root.selectionMode
                onActionRequested: a => root.action = a
                onSelectionModeRequested: m => root.selectionMode = m
                onDismiss: root.dismiss()
            }
        }
    }

    IpcHandler {
        target: "region"
        function screenshot(): void { root.screenshot(); }
        function edit(): void { root.edit(); }
        function search(): void { root.search(); }
        function ocr(): void { root.ocr(); }
        function close(): void { root.dismiss(); }
    }
    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
}
