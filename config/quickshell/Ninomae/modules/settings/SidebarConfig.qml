import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    id: page
    readonly property var toggles: Config.options.sidebar.quickToggles

    // A quick toggle style to pick: a little screen with the sidebar open on the right, its toggles drawn
    // that way. Android's are your own tiles, in your column count
    component StyleTile: PreviewTile {
        id: tile
        required property string styleName // sidebar.quickToggles.style
        chosen: page.toggles.style === styleName
        onClicked: Config.set("sidebar.quickToggles.style", styleName)
        readonly property real gap: Math.max(3, Math.round(width * 0.02))
        Rectangle { // The sidebar
            id: panel
            readonly property real pad: Math.round(tile.gap * 1.6)
            x: parent.width * 0.54
            y: tile.gap
            width: parent.width - x - tile.gap
            height: parent.height - tile.gap * 2
            radius: Math.max(4, tile.gap * 2)
            color: Appearance.colors.colLayer0
            opacity: 0.96
            Column {
                x: panel.pad
                y: panel.pad
                width: panel.width - panel.pad * 2
                spacing: panel.pad
                // Classic: a row of round buttons in one pill
                Rectangle {
                    visible: tile.styleName === "classic"
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property real dot: Math.round(parent.width / 9)
                    width: classicRow.width + dot * 0.6
                    height: dot * 1.6
                    radius: height / 2
                    color: Appearance.colors.colLayer2
                    Row {
                        id: classicRow
                        anchors.centerIn: parent
                        spacing: parent.dot * 0.35
                        Repeater {
                            model: 6
                            Rectangle {
                                required property int index
                                width: parent.parent.dot
                                height: width
                                radius: width / 2
                                color: index < 2 ? Appearance.colors.colPrimary : Appearance.colors.colLayer4
                            }
                        }
                    }
                }
                // Android: the grid of tiles, wide ones taking two cells
                Item {
                    id: androidGrid
                    visible: tile.styleName === "android"
                    readonly property int columns: Math.max(1, page.toggles.android.columns)
                    readonly property real spacing: Math.max(2, tile.gap * 0.7)
                    readonly property real cell: (width - spacing * (columns - 1)) / columns
                    // Placed in order, a row filling up to `columns` cells: [x, y, cells]
                    readonly property var placed: {
                        let col = 0, row = 0;
                        const out = [];
                        for (const t of page.toggles.android.toggles) {
                            const size = Math.min(t.size ?? 1, columns);
                            if (col + size > columns) { col = 0; row++; }
                            out.push([col, row, size]);
                            col += size;
                        }
                        return out;
                    }
                    width: parent.width
                    height: placed.length ? (Math.max(...placed.map(p => p[1])) + 1) * (cell * 0.75 + spacing) - spacing : 0
                    Repeater {
                        model: androidGrid.placed
                        Rectangle {
                            required property var modelData
                            required property int index
                            x: modelData[0] * (androidGrid.cell + androidGrid.spacing)
                            y: modelData[1] * (androidGrid.cell * 0.75 + androidGrid.spacing)
                            width: modelData[2] * androidGrid.cell + (modelData[2] - 1) * androidGrid.spacing
                            height: androidGrid.cell * 0.75
                            radius: Math.max(2, height * 0.3)
                            color: Appearance.colors.colLayer3
                            Rectangle { // The icon's squircle: accent on the first ones, as if on
                                anchors { left: parent.left; leftMargin: height * 0.35; verticalCenter: parent.verticalCenter }
                                width: parent.height * 0.5
                                height: width
                                radius: width * 0.3
                                color: index < 2 ? Appearance.colors.colPrimary : Appearance.colors.colLayer4
                            }
                        }
                    }
                }
                // Notifications under them
                Repeater {
                    model: 2
                    Rectangle {
                        width: parent.width
                        height: Math.round(panel.height * 0.16)
                        radius: Math.max(2, tile.gap)
                        color: Appearance.colors.colLayer2
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "dashboard_customize"
        title: Translation.tr("Quick toggles")
        spacing: 10
        Item { // The two side by side in the middle, each the size of a bar shape tile (a third of the row)
            id: styleRow
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 6
            readonly property real spacing: 20
            readonly property real tileWidth: (width - spacing * 2) / 3
            implicitHeight: styleTiles.implicitHeight
            RowLayout {
                id: styleTiles
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: styleRow.spacing
                StyleTile { styleName: "classic"; name: Translation.tr("Classic"); Layout.fillWidth: false; Layout.preferredWidth: styleRow.tileWidth }
                StyleTile { styleName: "android"; name: Translation.tr("Android"); Layout.fillWidth: false; Layout.preferredWidth: styleRow.tileWidth }
            }
        }
        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Columns")
            visible: page.toggles.style === "android"
            option: "sidebar.quickToggles.android.columns"
            from: 2
            to: 8
            stepSize: 1
        }
    }
    ContentSection {
        icon: "side_navigation"
        title: Translation.tr("Contents")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "monitoring"
            text: Translation.tr("Resource monitor")
            option: "sidebar.resourceMonitor.enable"
        }
        ConfigSpinBox {
            icon: "update"
            text: Translation.tr("Update every")
            visible: Config.options.sidebar.resourceMonitor.enable
            option: "resources.updateInterval"
            suffix: "ms"
            from: 500
            to: 10000
            stepSize: 500
        }
        ConfigSwitch {
            buttonIcon: "tune"
            text: Translation.tr("Quick sliders")
            option: "sidebar.quickSliders.enable"
        }
        ContentSubsection {
            title: Translation.tr("Sliders")
            visible: Config.options.sidebar.quickSliders.enable
            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Volume")
                option: "sidebar.quickSliders.showVolume"
            }
            ConfigSwitch {
                buttonIcon: "brightness_6"
                text: Translation.tr("Brightness")
                option: "sidebar.quickSliders.showBrightness"
            }
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Microphone")
                option: "sidebar.quickSliders.showMic"
            }
        }
        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr("Keep the sidebar loaded")
            option: "sidebar.keepRightSidebarLoaded"
            tooltip: Translation.tr("Opens faster, uses a little more memory")
        }
    }
    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")
        spacing: 10
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Pop-ups stay for")
            option: "notifications.timeout"
            factor: 0.001 // Stored in milliseconds
            suffix: Translation.tr("seconds")
            from: 1
            to: 30
            stepSize: 1
        }
    }
}
