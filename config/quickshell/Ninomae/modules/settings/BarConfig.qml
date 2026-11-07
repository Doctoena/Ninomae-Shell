import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    // A bar shape to pick, drawn on a little screen the way it'd look in the chosen position
    component ShapeTile: PreviewTile {
        id: tile
        required property int shape // bar.cornerStyle: 0 Hug, 1 Float, 2 Rect
        readonly property var bar: Config.options.bar
        readonly property real barHeight: Math.max(12, Math.round(width * 0.055)) // Scales with the tile
        readonly property real curve: Math.round(barHeight * 1.7) // Hug's corner curves, a bit bigger than life so they read
        chosen: bar.cornerStyle === shape
        onClicked: Config.set("bar.cornerStyle", shape)
        Rectangle { // The bar
            id: miniBar
            readonly property real inset: tile.shape === 1 ? Math.round(tile.barHeight * 0.45) : 0
            width: parent.width - inset * 2
            height: tile.barHeight
            x: (parent.width - width) / 2
            y: tile.bar.bottom ? parent.height - height - inset : inset
            radius: tile.shape === 1 ? height / 2 : 0
            color: Appearance.colors.colLayer0
            Row { // Workspaces on the left, status dots on the right
                readonly property real dot: Math.round(tile.barHeight * 0.4)
                anchors { left: parent.left; leftMargin: tile.barHeight * 0.6; verticalCenter: parent.verticalCenter }
                spacing: dot * 0.6
                Rectangle { width: parent.dot * 3; height: parent.dot; radius: height / 2; color: Appearance.colors.colPrimary }
                Repeater { model: 3; Rectangle { width: parent.dot; height: parent.dot; radius: height / 2; color: Appearance.colors.colSubtext } }
            }
            Row {
                readonly property real dot: Math.round(tile.barHeight * 0.4)
                anchors { right: parent.right; rightMargin: tile.barHeight * 0.6; verticalCenter: parent.verticalCenter }
                spacing: dot * 0.6
                Repeater { model: 3; Rectangle { width: parent.dot; height: parent.dot; radius: height / 2; color: Appearance.colors.colOnLayer0; opacity: 0.6 } }
            }
        }
        // Hug: the bar's corners curve into the screen
        RoundCorner {
            visible: tile.shape === 0
            implicitSize: tile.curve
            color: Appearance.colors.colLayer0
            corner: tile.bar.bottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft
            x: miniBar.x
            y: tile.bar.bottom ? miniBar.y - implicitSize : miniBar.y + miniBar.height
        }
        RoundCorner {
            visible: tile.shape === 0
            implicitSize: tile.curve
            color: Appearance.colors.colLayer0
            corner: tile.bar.bottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight
            x: miniBar.x + miniBar.width - implicitSize
            y: tile.bar.bottom ? miniBar.y - implicitSize : miniBar.y + miniBar.height
        }
    }
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
                ShapeTile { shape: 0; name: Translation.tr("Hug") }
                ShapeTile { shape: 1; name: Translation.tr("Float") }
                ShapeTile { shape: 2; name: Translation.tr("Square") }
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
    ContentSection {
        title: Translation.tr("Weather")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Weather in the clock drawer")
            description: Translation.tr("Today's forecast when you open the clock")
            option: "bar.weather.enable"
        }
        ConfigSwitch {
            text: Translation.tr("Use my location")
            description: Translation.tr("Find where you are instead of using a city name")
            visible: Config.options.bar.weather.enable
            option: "bar.weather.enableGPS"
        }
        SettingRow { // Where to get the weather for, without location
            visible: Config.options.bar.weather.enable && !Config.options.bar.weather.enableGPS
            text: Translation.tr("City")
            description: Translation.tr("Where the forecast is for")
            StyledTextArea {
                Layout.preferredWidth: 260 // The row says what it is: no floating label
                text: WeatherLocation.city
                onTextChanged: if (text !== WeatherLocation.city) WeatherLocation.setCity(text)
            }
        }
        ConfigSwitch {
            text: Translation.tr("Fahrenheit")
            description: Translation.tr("°F and miles per hour instead of °C and km/h")
            visible: Config.options.bar.weather.enable
            option: "bar.weather.useUSCS"
        }
        ConfigSpinBox {
            text: Translation.tr("Update every")
            description: Translation.tr("How often the forecast refreshes")
            visible: Config.options.bar.weather.enable
            option: "bar.weather.fetchInterval"
            suffix: Translation.tr("minutes")
            from: 5
            to: 60
            stepSize: 5
        }
    }
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
