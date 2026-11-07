import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    ContentSection {
        id: layoutSection
        title: Translation.tr("Shape")
        spacing: 10
        readonly property var bar: Config.options.bar
        SettingsCard {
            RowLayout { // The three shapes share the card's width
                Layout.fillWidth: true
                spacing: 20
                uniformCellSizes: true
                BarShapeTile { shape: 0; name: Translation.tr("Hug") }
                BarShapeTile { shape: 1; name: Translation.tr("Float") }
                BarShapeTile { shape: 2; name: Translation.tr("Square") }
            }
        }
        ConfigChoiceRow {
            text: Translation.tr("Position")
            description: Translation.tr("Along the top or the bottom of the screen. Its drawers open from there")
            option: "bar.bottom"
            options: [
                { displayName: Translation.tr("Top"), icon: "arrow_upward", value: false },
                { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: true }
            ]
        }
        ConfigSwitch {
            text: Translation.tr("Bar background")
            option: "bar.showBackground"
            description: Translation.tr("Off: the bar's items sit straight on the wallpaper")
        }
        ConfigSwitch {
            text: Translation.tr("Shadow under the bar")
            description: Translation.tr("A soft shadow under the floating bar")
            visible: layoutSection.bar.cornerStyle === 1 && layoutSection.bar.showBackground // Only the floating bar has one
            option: "bar.floatStyleShadow"
        }
    }
    ContentSection {
        title: Translation.tr("On the bar")
        spacing: 10
        ConfigSpinBox {
            text: Translation.tr("Workspaces shown")
            description: Translation.tr("How many workspace dots the bar has")
            option: "bar.workspaces.shown"
            from: 1
            to: 20
            stepSize: 1
        }
        ConfigSwitch {
            text: Translation.tr("Unread notification count")
            description: Translation.tr("A number on the bell while notifications wait")
            option: "bar.indicators.notifications.showUnreadCount"
        }
        ConfigSwitch {
            text: Translation.tr("Battery")
            description: Translation.tr("The charge level, with the time left when you point at it")
            visible: Battery.available
            option: "bar.indicators.battery.show"
        }
    }
    ContentSection {
        title: Translation.tr("System tray")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Show new tray icons on the bar")
            option: "bar.tray.invertPinnedItems"
            tooltip: Translation.tr("Off: they start hidden behind the ‹ arrow, and you pin the ones you want")
        }
        ConfigSwitch {
            text: Translation.tr("Hide idle tray icons")
            description: Translation.tr("Icons the app marks as passive, with nothing to show right now")
            option: "bar.tray.filterPassive"
            tooltip: Translation.tr("Icons the app marks as passive (nothing to show right now)")
        }
        ConfigSwitch {
            text: Translation.tr("Monochrome icons")
            description: Translation.tr("In one colour, to match the rest of the shell")
            option: "bar.tray.monochromeIcons"
        }
        ConfigSwitch {
            text: Translation.tr("Show item IDs in tooltips")
            description: Translation.tr("Each icon's ID when you point at it, for writing tray rules")
            option: "bar.tray.showItemId"
        }
    }
    WeatherSection {}
    ContentSection {
        title: Translation.tr("Dock")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Show the dock")
            option: "dock.enable"
            tooltip: Translation.tr("Running and pinned apps along the bottom of the screen")
        }
        ConfigSwitch {
            text: Translation.tr("Keep it open at login")
            description: Translation.tr("Off: it stays hidden until you call it up")
            visible: Config.options.dock.enable
            option: "dock.pinnedOnStartup"
        }
        ConfigSwitch {
            text: Translation.tr("Show it on hover")
            description: Translation.tr("Point at the bottom edge of the screen to bring it up")
            visible: Config.options.dock.enable
            option: "dock.hoverToReveal"
        }
        ConfigSpinBox {
            text: Translation.tr("Hover area height")
            description: Translation.tr("How close to the edge the pointer has to be")
            visible: Config.options.dock.enable && Config.options.dock.hoverToReveal
            option: "dock.hoverRegionHeight"
            suffix: "px"
            from: 1
            to: 50
            stepSize: 1
        }
        ConfigSpinBox {
            text: Translation.tr("Height")
            description: Translation.tr("How tall the dock is")
            visible: Config.options.dock.enable
            option: "dock.height"
            suffix: "px"
            from: 40
            to: 120
            stepSize: 5
        }
        ConfigSwitch {
            text: Translation.tr("Monochrome icons")
            description: Translation.tr("In one colour, to match the rest of the shell")
            visible: Config.options.dock.enable
            option: "dock.monochromeIcons"
        }
    }
}
