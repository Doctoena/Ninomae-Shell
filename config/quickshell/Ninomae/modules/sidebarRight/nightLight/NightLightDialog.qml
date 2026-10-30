import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
WindowDialog {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    readonly property bool automatic: Config.options.light.night.automatic
    // Sized to what's there
    backgroundHeight: body.implicitHeight + 36

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: 12

        QuickDialogHeader {
            icon: "nightlight"
            title: Translation.tr("Night Light")
            subtitle: Hyprsunset.active ? Translation.tr("On · %1 K").arg(Math.round(Config.options.light.night.colorTemperature))
                : root.automatic ? Translation.tr("Off · comes on at %1").arg(Config.options.light.night.from)
                : Translation.tr("Off")
            showSwitch: true
            checked: Hyprsunset.active
            onSwitchToggled: checked => Hyprsunset.toggle(checked)
        }

        QuickDialogGroup {
            padding: 10
            SettingRow {
                icon: "night_sight_auto"
                title: Translation.tr("Automatic")
                detail: Translation.tr("%1 to %2").arg(Config.options.light.night.from).arg(Config.options.light.night.to)
                checked: root.automatic
                onToggled: checked => Config.options.light.night.automatic = checked
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                QuickDialogIcon { icon: "thermostat"; active: Hyprsunset.active }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.S
                    from: 6500
                    to: 1200
                    stopIndicatorValues: [5000, to]
                    value: Config.options.light.night.colorTemperature
                    onMoved: Config.options.light.night.colorTemperature = value
                    tooltipContent: `${Math.round(value)}K`
                }
            }
        }

        WindowDialogSectionHeader { text: Translation.tr("Anti-flashbang") }
        QuickDialogGroup {
            padding: 10
            SettingRow {
                icon: "flash_off"
                title: Translation.tr("Dim bright windows")
                detail: Translation.tr("Experimental")
                checked: Config.options.light.antiFlashbang.enable
                onToggled: checked => Config.options.light.antiFlashbang.enable = checked
                tip: Translation.tr("Example use case: eroge on one workspace, dark Discord window on another")
            }
        }

        WindowDialogSectionHeader {
            visible: !!root.brightnessMonitor
            text: Translation.tr("Brightness")
        }
        QuickDialogGroup {
            visible: !!root.brightnessMonitor
            padding: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                QuickDialogIcon { icon: "brightness_6"; active: true }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.S
                    value: root.brightnessMonitor?.brightness ?? 0
                    onMoved: root.brightnessMonitor?.setBrightness(value)
                }
                StyledText {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: Math.round((root.brightnessMonitor?.brightness ?? 0) * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        WindowDialogButtonRow {
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Done")
                primary: true
                onClicked: root.dismiss()
            }
        }
    }

    // A setting with an on/off switch: squircle icon (accent when on), title and a line under it
    component SettingRow: RowLayout {
        id: row
        property string icon
        property string title
        property string detail: ""
        property bool checked: false
        property string tip: "" // Shown while the pointer is over the row
        signal toggled(bool checked)
        Layout.fillWidth: true
        spacing: 12
        HoverHandler { id: rowHover }
        StyledToolTip {
            text: row.tip
            visible: row.tip !== "" && rowHover.hovered
        }
        QuickDialogIcon { icon: row.icon; active: row.checked }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: row.title
                font.weight: Font.Medium
                color: row.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
        StyledSwitch {
            checked: row.checked
            onClicked: row.toggled(checked)
        }
    }
}
