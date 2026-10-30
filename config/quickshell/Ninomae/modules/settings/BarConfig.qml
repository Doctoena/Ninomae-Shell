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
        icon: "tune"
        title: Translation.tr("Layout")
        spacing: 10
        readonly property var bar: Config.options.bar
        RowLayout { // The three shapes share the card's width
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 6
            spacing: 20
            uniformCellSizes: true
            ShapeTile { shape: 0; name: Translation.tr("Hug") }
            ShapeTile { shape: 1; name: Translation.tr("Float") }
            ShapeTile { shape: 2; name: Translation.tr("Square") }
        }
        ConfigChoiceRow {
            icon: "vertical_align_top"
            text: Translation.tr("Position")
            option: "bar.bottom"
            options: [
                { displayName: Translation.tr("Top"), icon: "arrow_upward", value: false },
                { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: true }
            ]
        }
        ConfigSwitch {
            buttonIcon: "rectangle"
            text: Translation.tr("Bar background")
            option: "bar.showBackground"
            tooltip: Translation.tr("Off: the bar's items sit straight on the wallpaper")
        }
        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Shadow under the bar")
            visible: layoutSection.bar.cornerStyle === 1 && layoutSection.bar.showBackground // Only the floating bar has one
            option: "bar.floatStyleShadow"
        }
    }
    ContentSection {
        icon: "view_week"
        title: Translation.tr("On the bar")
        spacing: 10
        ConfigSpinBox {
            icon: "workspaces"
            text: Translation.tr("Workspaces shown")
            option: "bar.workspaces.shown"
            from: 1
            to: 20
            stepSize: 1
        }
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Unread notification count")
            option: "bar.indicators.notifications.showUnreadCount"
        }
        ConfigSwitch {
            buttonIcon: "battery_android_full"
            text: Translation.tr("Battery")
            visible: Battery.available
            option: "bar.indicators.battery.show"
        }
    }
    ContentSection {
        icon: "shelf_auto_hide"
        title: Translation.tr("System tray")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr("Show new tray icons on the bar")
            option: "bar.tray.invertPinnedItems"
            tooltip: Translation.tr("Off: they start hidden behind the ‹ arrow, and you pin the ones you want")
        }
        ConfigSwitch {
            buttonIcon: "filter_alt"
            text: Translation.tr("Hide idle tray icons")
            option: "bar.tray.filterPassive"
            tooltip: Translation.tr("Icons the app marks as passive (nothing to show right now)")
        }
        ConfigSwitch {
            buttonIcon: "palette"
            text: Translation.tr("Monochrome icons")
            option: "bar.tray.monochromeIcons"
        }
        ConfigSwitch {
            buttonIcon: "info"
            text: Translation.tr("Show item IDs in tooltips")
            option: "bar.tray.showItemId"
        }
    }
    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Weather")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "cloud"
            text: Translation.tr("Weather in the clock drawer")
            option: "bar.weather.enable"
        }
        ConfigSwitch {
            buttonIcon: "my_location"
            text: Translation.tr("Use my location")
            visible: Config.options.bar.weather.enable
            option: "bar.weather.enableGPS"
        }
        SettingRow { // Where to get the weather for, without location
            visible: Config.options.bar.weather.enable && !Config.options.bar.weather.enableGPS
            icon: "location_city"
            text: Translation.tr("City")
            MaterialTextArea {
                Layout.preferredWidth: 260 // The row says what it is: no floating label
                text: WeatherLocation.city
                onTextChanged: if (text !== WeatherLocation.city) WeatherLocation.setCity(text)
            }
        }
        ConfigSwitch {
            buttonIcon: "thermometer"
            text: Translation.tr("Fahrenheit")
            visible: Config.options.bar.weather.enable
            option: "bar.weather.useUSCS"
        }
        ConfigSpinBox {
            icon: "update"
            text: Translation.tr("Update every")
            visible: Config.options.bar.weather.enable
            option: "bar.weather.fetchInterval"
            suffix: Translation.tr("minutes")
            from: 5
            to: 60
            stepSize: 5
        }
    }
    ContentSection {
        icon: "call_to_action"
        title: Translation.tr("Dock")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "call_to_action"
            text: Translation.tr("Show the dock")
            option: "dock.enable"
            tooltip: Translation.tr("Running and pinned apps along the bottom of the screen")
        }
        ConfigSwitch {
            buttonIcon: "push_pin"
            text: Translation.tr("Keep it open at login")
            visible: Config.options.dock.enable
            option: "dock.pinnedOnStartup"
        }
        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("Show it on hover")
            visible: Config.options.dock.enable
            option: "dock.hoverToReveal"
        }
        ConfigSpinBox {
            icon: "height"
            text: Translation.tr("Hover area height")
            visible: Config.options.dock.enable && Config.options.dock.hoverToReveal
            option: "dock.hoverRegionHeight"
            suffix: "px"
            from: 1
            to: 50
            stepSize: 1
        }
        ConfigSpinBox {
            icon: "straighten"
            text: Translation.tr("Height")
            visible: Config.options.dock.enable
            option: "dock.height"
            suffix: "px"
            from: 40
            to: 120
            stepSize: 5
        }
        ConfigSwitch {
            buttonIcon: "palette"
            text: Translation.tr("Monochrome icons")
            visible: Config.options.dock.enable
            option: "dock.monochromeIcons"
        }
    }
}
