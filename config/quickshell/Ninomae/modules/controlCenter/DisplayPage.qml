pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Display: each screen's brightness, night light, and anti-flashbang
ColumnLayout {
    id: page
    spacing: 14
    readonly property var night: Config.options.light.night
    readonly property string subtitle: Translation.tr("Brightness and night light")

    ContentSection {
        title: Translation.tr("Brightness")
        Repeater {
            model: Brightness.monitors
            delegate: SliderRow {
                id: screenRow
                required property var modelData
                text: modelData.screen?.model || modelData.screen?.name || Translation.tr("Screen")
                description: modelData.isDdc ? Translation.tr("%1 · external screen").arg(modelData.screen?.name ?? "")
                    : modelData.screen?.name ?? ""
                enabled: modelData.ready
                level: modelData.brightness
                onMoved: value => screenRow.modelData.setBrightness(value)
            }
        }
    }
    ContentSection {
        title: Translation.tr("Night light")
        SwitchRow {
            text: Translation.tr("Night light")
            description: Hyprsunset.active ? Translation.tr("On. Warmer colours, easier on the eyes at night")
                : page.night.automatic ? Translation.tr("Off. Comes on at %1").arg(page.night.from) : Translation.tr("Off")
            current: Hyprsunset.active
            on: Hyprsunset.active
            onSwitched: on => Hyprsunset.toggle(on)
        }
        SliderRow {
            text: Translation.tr("Warmth (K)")
            description: Translation.tr("Lower is warmer")
            from: 6500
            to: 1200
            factor: 1
            level: page.night.colorTemperature
            onMoved: value => Config.options.light.night.colorTemperature = Math.round(value)
        }
        ConfigSwitch {
            text: Translation.tr("Automatic")
            description: Translation.tr("From %1 to %2").arg(page.night.from).arg(page.night.to)
            option: "light.night.automatic"
        }
    }
    ContentSection {
        title: Translation.tr("Anti-flashbang")
        ConfigSwitch {
            text: Translation.tr("Dim bright windows")
            description: Translation.tr("Experimental. Dims a window that's far brighter than the rest")
            option: "light.antiFlashbang.enable"
        }
    }
}
