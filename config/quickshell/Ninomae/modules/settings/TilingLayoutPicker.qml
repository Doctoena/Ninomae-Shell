import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The tiling layouts as little screens to pick from (Settings → Appearance, the welcome window): each one's windows
 * drawn as it tiles them, the focused one in accent, and a line on what the chosen one does under them.
 */
SettingsCard {
    id: tilingLayout
    readonly property string chosen: Config.options.windows.layoutPreset
    // Auto's pick on this screen, as services/WindowLayout.qml makes it: Centred from 21:9 up
    readonly property bool ultrawide: (Hyprland.focusedMonitor?.width ?? 0) / Math.max(1, Hyprland.focusedMonitor?.height ?? 1) >= 2.1
    readonly property var choices: [
        { displayName: Translation.tr("Auto"), value: "auto",
            about: Translation.tr("Centred on an ultrawide monitor, Normal on anything narrower") },
        { displayName: Translation.tr("Centred"), value: "centred",
            about: Translation.tr("The main window in the middle at half the width, others at the sides") },
        { displayName: Translation.tr("Side by side"), value: "sideBySide",
            about: Translation.tr("Two windows split the screen in half, more stack on the right") },
        { displayName: Translation.tr("Columns"), value: "columns",
            about: Translation.tr("Scrolling columns, each a third of the screen wide") },
        { displayName: Translation.tr("Normal"), value: "normal",
            about: Translation.tr("Regular tiling, for normal-width monitors") }
    ]
    // Each layout's windows on the mini screen: [x, y, width, height] as parts of the space under the
    // bar, and whether it's the focused one. Columns' fourth one runs off the edge, as it scrolls
    readonly property var windows: ({
        normal: [[0, 0, 0.5, 1, true], [0.5, 0, 0.5, 0.5], [0.5, 0.5, 0.25, 0.5], [0.75, 0.5, 0.25, 0.5]],
        centred: [[0.25, 0, 0.5, 1, true], [0, 0, 0.25, 1], [0.75, 0, 0.25, 1]],
        sideBySide: [[0, 0, 0.5, 1, true], [0.5, 0, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]],
        columns: [[0, 0, 0.333, 1], [0.333, 0, 0.333, 1, true], [0.667, 0, 0.333, 1], [1, 0, 0.333, 1]]
    })
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            columns: Math.max(2, Math.min(5, Math.floor((width + columnSpacing) / (170 + columnSpacing))))
            columnSpacing: 16
            rowSpacing: 14
            uniformCellWidths: true
            Repeater {
                model: tilingLayout.choices
                delegate: PreviewTile {
                    id: tile
                    required property var modelData
                    readonly property string drawn: modelData.value === "auto"
                        ? (tilingLayout.ultrawide ? "centred" : "normal") : modelData.value
                    readonly property real gap: Math.max(3, Math.round(width * 0.022))
                    readonly property real barHeight: Math.max(8, Math.round(width * 0.045))
                    name: modelData.displayName
                    chosen: tilingLayout.chosen === modelData.value
                    badge: modelData.value === "auto" ? (tilingLayout.ultrawide ? Translation.tr("Centred") : Translation.tr("Normal")) : ""
                    onClicked: Config.set("windows.layoutPreset", modelData.value)
                    Rectangle { // A thin bar, for scale
                        x: tile.gap; y: tile.gap
                        width: parent.width - tile.gap * 2
                        height: tile.barHeight
                        radius: height / 2
                        color: Appearance.colors.colLayer0
                    }
                    Repeater {
                        model: tilingLayout.windows[tile.drawn]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property real areaY: tile.gap * 2 + tile.barHeight
                            readonly property real areaWidth: parent.width - tile.gap
                            readonly property real areaHeight: parent.height - areaY - tile.gap / 2
                            x: tile.gap / 2 + modelData[0] * areaWidth + tile.gap / 2
                            y: areaY + modelData[1] * areaHeight
                            width: modelData[2] * areaWidth - tile.gap
                            height: modelData[3] * areaHeight - tile.gap / 2
                            radius: Math.max(2, tile.gap)
                            color: Appearance.colors.colLayer0
                            opacity: 0.92
                            border.width: modelData[4] ? 2 : 1
                            border.color: modelData[4] ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        }
                    }
                }
            }
        }
        StyledText { // What the chosen one does
            Layout.fillWidth: true
            Layout.leftMargin: 2
            wrapMode: Text.Wrap
            text: tilingLayout.choices.find(c => c.value === tilingLayout.chosen)?.about ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
}
