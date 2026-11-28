pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Display: each screen's brightness, night light (one card: its warmth and timer inside while it's on), anti-flashbang
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
                // The laptop's own screen by that name (its model is a part number), an external one by its model
                text: modelData.isDdc ? (modelData.screen?.model || modelData.screen?.name || Translation.tr("Screen"))
                    : Translation.tr("Built-in screen")
                description: modelData.isDdc ? Translation.tr("%1 · external screen").arg(modelData.screen?.name ?? "")
                    : [modelData.screen?.model, modelData.screen?.name].filter(s => s).join(" · ")
                leading: RowSquircle { symbol: screenRow.modelData.isDdc ? "desktop_windows" : "laptop" }
                enabled: modelData.ready
                level: modelData.brightness
                onMoved: value => screenRow.modelData.setBrightness(value)
            }
        }
    }
    ContentSection {
        title: Translation.tr("Night light")
        SettingsCard { // One card: the switch, and while it's on, a tint and its warmth and timer
            id: nightCard
            readonly property bool active: Hyprsunset.active
            leftPadding: 12
            rightPadding: 14
            verticalPadding: 12
            spacing: 12
            color: glass ? ColorUtils.transparentize(Appearance.colors.colPrimary, active ? 0.92 : 1) // On the well: tinted while on
                : active ? Qt.tint(Appearance.m3colors.m3surfaceContainer, ColorUtils.transparentize(Appearance.colors.colPrimary, 0.92))
                : Appearance.m3colors.m3surfaceContainer
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                RowSquircle {
                    accent: nightCard.active
                    symbol: "nightlight"
                }
                RowText {
                    text: Translation.tr("Night light")
                    description: nightCard.active ? (page.night.automatic ? Translation.tr("On until %1").arg(page.night.to) : Translation.tr("On"))
                        : page.night.automatic ? Translation.tr("Off. Comes on at %1").arg(page.night.from) : Translation.tr("Off")
                }
                StyledSwitch {
                    sizeScale: 0.7
                    checked: nightCard.active
                    onClicked: Hyprsunset.toggle(checked)
                }
            }
            RowLayout { // Warmth: the slider between its name and the figure
                visible: nightCard.active
                Layout.fillWidth: true
                Layout.leftMargin: 48
                spacing: 12
                StyledText {
                    text: Translation.tr("Warmth")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: nightCard.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
                }
                SlimSlider {
                    Layout.fillWidth: true
                    filledBar: true
                    ringColor: nightCard.color
                    from: 6500
                    to: 1200
                    wheelEnabled: false
                    level: page.night.colorTemperature
                    onMoved: Config.options.light.night.colorTemperature = Math.round(value)
                }
                NumberField {
                    plain: true
                    unit: "K"
                    value: page.night.colorTemperature
                    from: 1200
                    to: 6500
                    onAccepted: newValue => Config.options.light.night.colorTemperature = Math.round(newValue)
                }
            }
            RowLayout { // Automatic: on and off by the clock
                visible: nightCard.active
                Layout.fillWidth: true
                Layout.leftMargin: 48
                spacing: 12
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Automatic, %1 to %2").arg(page.night.from).arg(page.night.to)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: nightCard.glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
                }
                StyledSwitch {
                    sizeScale: 0.7
                    checked: page.night.automatic
                    onClicked: Config.set("light.night.automatic", checked)
                }
            }
        }
    }
    ContentSection {
        title: Translation.tr("Anti-flashbang")
        SwitchRow {
            text: Translation.tr("Dim bright windows")
            description: Translation.tr("Experimental. Dims a window that's far brighter than the rest")
            leading: RowSquircle { symbol: "flare" }
            on: Config.options.light.antiFlashbang.enable
            onSwitched: on => Config.set("light.antiFlashbang.enable", on)
        }
    }
}
