pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Display: a card per screen with its brightness, night light, and anti-flashbang
ColumnLayout {
    id: page
    spacing: 10
    readonly property var night: Config.options.light.night
    readonly property string subtitle: Translation.tr("Brightness and night light")

    // Two screens sit side by side, one takes the width
    GridLayout {
        Layout.fillWidth: true
        columns: Brightness.monitors.length > 1 ? 2 : 1
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: Brightness.monitors
            delegate: HeroCard {
                id: screenCard
                required property var modelData
                Layout.preferredWidth: 1
                symbol: modelData.isDdc ? "desktop_windows" : "laptop"
                title: modelData.screen?.model || modelData.screen?.name || Translation.tr("Screen")
                detail: modelData.screen?.name ?? ""
                value: Math.round(modelData.brightness * 100)
                unit: "%"
                SlimSlider {
                    Layout.fillWidth: true
                    enabled: screenCard.modelData.ready
                    level: screenCard.modelData.brightness
                    onMoved: screenCard.modelData.setBrightness(value)
                }
            }
        }
    }

    // Night light: its warmth large with the switch beside it, then the slider and the schedule
    HeroCard {
        Layout.topMargin: 8
        symbol: "nightlight"
        active: Hyprsunset.active
        title: Translation.tr("Night light")
        detail: Hyprsunset.active ? Translation.tr("On · warmer colours, easier on the eyes at night")
            : page.night.automatic ? Translation.tr("Off · comes on at %1").arg(page.night.from) : Translation.tr("Off")
        value: Math.round(page.night.colorTemperature)
        unit: "K"
        dimmed: !Hyprsunset.active
        actions: StyledSwitch {
            checked: Hyprsunset.active
            onClicked: Hyprsunset.toggle(checked)
        }
        SlimSlider {
            Layout.fillWidth: true
            from: 6500
            to: 1200
            level: page.night.colorTemperature
            onMoved: Config.options.light.night.colorTemperature = value
        }
        ToggleRow {
            Layout.topMargin: 10
            icon: "night_sight_auto"
            title: Translation.tr("Automatic")
            detail: Translation.tr("%1 to %2").arg(page.night.from).arg(page.night.to)
            checked: page.night.automatic
            onToggled: checked => Config.options.light.night.automatic = checked
        }
    }

    WindowDialogSectionHeader {
        Layout.topMargin: 8
        text: Translation.tr("Anti-flashbang")
    }
    QuickDialogGroup {
        padding: 12
        ToggleRow {
            icon: "flash_off"
            title: Translation.tr("Dim bright windows")
            detail: Translation.tr("Experimental")
            checked: Config.options.light.antiFlashbang.enable
            onToggled: checked => Config.options.light.antiFlashbang.enable = checked
            tip: Translation.tr("Example use case: eroge on one workspace, dark Discord window on another")
        }
    }
}
