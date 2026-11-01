import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The crosshair overlay (services/Crosshair.qml in the shell): its colour, then each part (outline, inner lines,
 * outer lines, centre dot, circle) as a card you switch on from its title. The settings scroll on the left; the
 * live preview stays put on the right, so it's in view whatever you change. Which games it shows in is set per
 * game, with the crosshair button under Play on a game's page in the launcher.
 */
Item {
    id: page
    readonly property var opts: Config.options.crosshair

    // A number setting: `key` in the crosshair config, in pixels as drawn in games
    component Num: ConfigSpinBox {
        required property string key
        option: "crosshair." + key
        suffix: "px"
        stepSize: 1
    }
    component Opacity: Num {
        icon: "opacity"; text: Translation.tr("Opacity")
        suffix: "%"
        from: 10; to: 100; stepSize: 10
    }

    // The same width as the other pages' cards (ContentPage's maxWidth), centred under the header
    RowLayout {
        id: columns
        anchors { top: parent.top; bottom: parent.bottom; topMargin: 20 }
        width: Math.min(parent.width - 40, 1260)
        x: (parent.width - width) / 2
        spacing: 20
        ContentPage { // The settings, scrolling
            Layout.fillWidth: true
            Layout.fillHeight: true
            margin: 0
            ContentSection {
                icon: "palette"
                title: Translation.tr("Colour")
                spacing: 10
                ConfigSwitch {
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Accent colour")
                    tooltip: Translation.tr("Follows the wallpaper")
                    checked: page.opts.color === "accent"
                    // Off: carry on from the accent's colour in the picker
                    onCheckedChanged: page.opts.color = checked ? "accent" : (page.opts.color === "accent" ? Appearance.colors.colPrimary.toString() : page.opts.color)
                }
                ColorPicker {
                    Layout.fillWidth: true
                    visible: page.opts.color !== "accent"
                    color: page.opts.color === "accent" ? Appearance.colors.colPrimary : page.opts.color
                    onEdited: c => page.opts.color = c.toString()
                }
            }

            ContentSection {
                icon: "border_outer"
                title: Translation.tr("Outline")
                toggleOption: "crosshair.outline"
                spacing: 10
                Num { key: "outlineThickness"; icon: "line_weight"; text: Translation.tr("Thickness"); from: 1; to: 4 }
                Opacity { key: "outlineOpacity" }
            }

            ContentSection {
                icon: "add"
                title: Translation.tr("Inner lines")
                toggleOption: "crosshair.lines"
                spacing: 10
                Num { key: "length"; icon: "straighten"; text: Translation.tr("Length"); from: 1; to: 30 }
                Num { key: "verticalLength"; icon: "height"; text: Translation.tr("Vertical length"); tooltip: Translation.tr("0 uses the same length"); from: 0; to: 30 }
                Num { key: "thickness"; icon: "line_weight"; text: Translation.tr("Thickness"); from: 1; to: 10 }
                Num { key: "gap"; icon: "space_bar"; text: Translation.tr("Gap from the centre"); from: 0; to: 30 }
                Opacity { key: "lineOpacity" }
                ConfigSwitch {
                    buttonIcon: "vertical_align_top"
                    text: Translation.tr("Top line")
                    tooltip: Translation.tr("Off makes a T shape, for the outer lines too")
                    option: "crosshair.topLine"
                }
            }

            ContentSection {
                icon: "open_with"
                title: Translation.tr("Outer lines")
                toggleOption: "crosshair.outerLines"
                spacing: 10
                Num { key: "outerLength"; icon: "straighten"; text: Translation.tr("Length"); from: 1; to: 30 }
                Num { key: "outerThickness"; icon: "line_weight"; text: Translation.tr("Thickness"); from: 1; to: 10 }
                Num { key: "outerGap"; icon: "space_bar"; text: Translation.tr("Gap from the centre"); from: 0; to: 40 }
                Opacity { key: "outerOpacity" }
                ConfigSwitch { // Also here when the inner lines are off: it shapes these too
                    visible: !page.opts.lines
                    buttonIcon: "vertical_align_top"
                    text: Translation.tr("Top line")
                    tooltip: Translation.tr("Off makes a T shape")
                    option: "crosshair.topLine"
                }
            }

            ContentSection {
                icon: "fiber_manual_record"
                title: Translation.tr("Centre dot")
                toggleOption: "crosshair.dot"
                spacing: 10
                Num { key: "dotSize"; icon: "photo_size_select_small"; text: Translation.tr("Size"); from: 1; to: 10 }
                Opacity { key: "dotOpacity" }
            }

            ContentSection {
                icon: "radio_button_unchecked"
                title: Translation.tr("Circle")
                toggleOption: "crosshair.circle"
                spacing: 10
                Num { key: "circleRadius"; icon: "straighten"; text: Translation.tr("Size"); from: 3; to: 40 }
                Num { key: "circleThickness"; icon: "line_weight"; text: Translation.tr("Thickness"); from: 1; to: 6 }
                Opacity { key: "circleOpacity" }
            }
        }

        ColumnLayout { // The preview: fixed on the right, on dark and on light, at 3× (drawn 1:1 in games)
            Layout.fillWidth: false // A layout fills by default: the settings get the room
            // 320, down to 240 in a narrow (tiled) window, so the settings keep 420 for their labels
            Layout.preferredWidth: Math.max(240, Math.min(320, columns.width - columns.spacing - 420))
            Layout.fillHeight: true
            spacing: 0
            ContentSection {
                icon: "my_location"
                title: Translation.tr("Preview")
                spacing: 8
                Repeater {
                    model: ["#15141a", "#d9d6de"]
                    Rectangle {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 190
                        radius: Appearance.rounding.normal
                        color: modelData
                        clip: true
                        CrosshairShape {
                            anchors.centerIn: parent
                            width: implicitWidth; height: implicitHeight
                            scale: 3
                        }
                    }
                }
                RippleButtonWithIcon { // Shows the real one on screen
                    Layout.fillWidth: true
                    materialIcon: "visibility"
                    mainText: Translation.tr("Show on screen")
                    downAction: () => Quickshell.execDetached(["qs", "-c", "Ninomae", "ipc", "call", "crosshair", "test"])
                }
                StyledText { // When it shows in games
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Translation.tr("Shows in the games you turn it on for, with the crosshair button under Play on a game's page. Super+G shows or hides it.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
