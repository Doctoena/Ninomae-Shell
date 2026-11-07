import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    ContentSection {
        title: Translation.tr("Wallpaper & colours")
        Layout.fillWidth: true
        spacing: 10
        SettingsCard {
            WallpaperSelector {
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                StyledText {
                    text: Translation.tr("Colour scheme")
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                Timer {
                    id: colorSchemeApplyTimer
                    interval: 150
                    repeat: false
                    onTriggered: Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--noswitch"])
                }
                StyledComboBox {
                    value: Config.options.appearance.palette.type
                    fallbackText: Translation.tr("Auto")
                    options: [
                        { value: "auto", displayName: Translation.tr("Auto") },
                        { value: "scheme-content", displayName: Translation.tr("Content") },
                        { value: "scheme-expressive", displayName: Translation.tr("Expressive") },
                        { value: "scheme-fidelity", displayName: Translation.tr("Fidelity") },
                        { value: "scheme-fruit-salad", displayName: Translation.tr("Fruit Salad") },
                        { value: "scheme-monochrome", displayName: Translation.tr("Monochrome") },
                        { value: "scheme-neutral", displayName: Translation.tr("Neutral") },
                        { value: "scheme-rainbow", displayName: Translation.tr("Rainbow") },
                        { value: "scheme-tonal-spot", displayName: Translation.tr("Tonal Spot") }
                    ]
                    onSelected: newValue => {
                        Config.options.appearance.palette.type = newValue;
                        colorSchemeApplyTimer.restart();
                    }
                }
                Item { Layout.fillWidth: true }
                ConfigSelectionArray { // Light or dark: makes the colours again from the same wallpaper
                    Layout.fillWidth: false
                    currentValue: Appearance.m3colors.darkmode
                    onSelected: dark => Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--mode", dark ? "dark" : "light", "--noswitch"])
                    options: [
                        { displayName: Translation.tr("Light"), icon: "light_mode", value: false },
                        { displayName: Translation.tr("Dark"), icon: "dark_mode", value: true }
                    ]
                }
            }
        }
    }
    ContentSection {
        id: themingSection
        title: Translation.tr("App theming")
        spacing: 10
        readonly property var theming: Config.options.appearance.wallpaperTheming
        ConfigSwitch {
            text: Translation.tr("Colour everything from the wallpaper")
            option: "appearance.wallpaperTheming.enableAppsAndShell"
            tooltip: Translation.tr("The shell, window borders, GTK apps, Steam, Discord, VS Code, Zen and the login screen")
        }
        ContentSubsection {
            title: Translation.tr("Also colour")
            visible: themingSection.theming.enableAppsAndShell
            ConfigSwitch {
                text: Translation.tr("Qt apps")
                description: Translation.tr("KDE and other Qt programs take the wallpaper's colours too")
                option: "appearance.wallpaperTheming.enableQtApps"
            }
            ConfigSwitch {
                text: Translation.tr("The terminal")
                description: Translation.tr("kitty's colours follow the wallpaper")
                option: "appearance.wallpaperTheming.enableTerminal"
            }
            ConfigSwitch {
                text: Translation.tr("Keep the terminal dark")
                visible: themingSection.theming.enableTerminal
                option: "appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode"
                tooltip: Translation.tr("Dark terminal colours even with a light theme")
            }
        }
        ContentSubsection {
            title: Translation.tr("Shell")
            ConfigSwitch {
                text: Translation.tr("Smooth transition when colours change")
                description: Translation.tr("The new colours fade in from where you clicked")
                option: "appearance.themeTransition"
            }
            ConfigSwitch {
                text: Translation.tr("Tint backgrounds with the accent")
                description: Translation.tr("Panels and cards lean towards the accent instead of plain grey")
                option: "appearance.extraBackgroundTint"
            }
        }
        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 2
            materialIcon: "refresh"
            mainText: Translation.tr("Apply theming changes")
            onClicked: Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--noswitch"])
            StyledToolTip {
                text: Translation.tr("Makes the colours again from the current wallpaper")
            }
        }
    }
    ContentSection {
        title: Translation.tr("Windows")
        spacing: 10
        ContentSubsection {
            title: Translation.tr("Tiling layout")
            TilingLayoutPicker {}
        }
    }
}
