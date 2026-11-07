import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.lock
ContentPage {
    id: page
    readonly property var lock: Config.options.lock
    readonly property var battery: Config.options.battery

    ContentSection {
        title: Translation.tr("Lock screen")
        spacing: 10
        // The look beside a little lock screen as yours looks, so a change shows right there; security under
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            // The wallpaper (blurred as set), the chips top right, the time bottom left, the password pill bottom
            // right. In a card as tall as the settings beside it, centred in it
            SettingsCard {
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.preferredWidth: 340
                spacing: 8
                ClippingRectangle {
                    id: lockPreview
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(width * 9 / 16)
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    StyledImage {
                        id: previewWallpaper
                        anchors.fill: parent
                        source: Config.wallpaperPath
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 560
                        asynchronous: true
                        visible: !page.lock.blur.enable
                    }
                    MultiEffect { // The blur, scaled down to the preview's size
                        anchors.fill: parent
                        visible: page.lock.blur.enable
                        source: previewWallpaper
                        blurEnabled: true
                        blurMax: 32
                        blur: Math.min(1, page.lock.blur.radius * (lockPreview.width / 1920) / 8)
                    }
                    Rectangle { // The lock screen's shade: light at the top, deeper at the foot
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.8) }
                            GradientStop { position: 0.5; color: "transparent" }
                            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.25) }
                        }
                    }
                    Row { // The chips, top right
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        spacing: 3
                        Repeater {
                            model: [18, 18, 10, 10, 10]
                            Rectangle {
                                required property int modelData
                                width: modelData; height: 10; radius: 3.5
                                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                            }
                        }
                    }
                    Column { // The time and the day, bottom left
                        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 10; bottomMargin: 8 }
                        spacing: -2
                        StyledText {
                            text: DateTime.time
                            font.family: Appearance.font.family.expressive
                            font.pixelSize: Math.round(lockPreview.height * 0.2)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM d")
                            font.pixelSize: 8
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    Rectangle { // The password pill, bottom right
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 10; bottomMargin: 12 }
                        width: parent.width * 0.36
                        height: Math.round(parent.height * 0.13)
                        radius: height / 3
                        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
                        Row { // Dots
                            visible: !page.lock.materialShapeChars
                            anchors.centerIn: parent
                            spacing: 5
                            Repeater {
                                model: 6
                                Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colOnLayer1 }
                            }
                        }
                        Loader { // Or the lock screen's own shapes
                            active: page.lock.materialShapeChars
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            sourceComponent: PasswordChars { length: 6 }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Locks by itself after 5 minutes. Super+L locks now")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            ContentSubsection { // The look: no name, the preview beside says it. Lined up with its top
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 0
                ConfigSwitch {
                    text: Translation.tr("Shapes instead of dots in the password")
                    description: Translation.tr("Each character shows as a small shape as you type")
                    option: "lock.materialShapeChars"
                }
                ConfigSwitch {
                    text: Translation.tr("Blur the wallpaper")
                    description: Translation.tr("The lock screen's wallpaper, softened behind the clock")
                    option: "lock.blur.enable"
                }
                ConfigSpinBox {
                    text: Translation.tr("Blur amount")
                    description: Translation.tr("How soft the wallpaper gets")
                    visible: page.lock.blur.enable
                    option: "lock.blur.radius"
                    suffix: "px"
                    from: 0
                    to: 200
                    stepSize: 10
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Security")
            ConfigSwitch {
                text: Translation.tr("Lock at login")
                option: "lock.launchOnStartup"
                tooltip: Translation.tr("For logins that skip the password, like auto-login")
            }
            ConfigSwitch {
                text: Translation.tr("Unlocking also unlocks the keyring")
                option: "lock.security.unlockKeyring"
                tooltip: Translation.tr("Where saved passwords and the game launcher's API keys are kept")
            }
            ConfigSwitch {
                text: Translation.tr("Ask for the password to power off")
                option: "lock.security.requirePasswordToPower"
                tooltip: Translation.tr("For the power buttons on the lock screen")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Battery")
        visible: Battery.available // Only on machines with one
        spacing: 10
        // The thresholds on one strip, 0 to 100 %: shut down and critical in red, low in amber, the rest the
        // accent, and where the battery is now
        SettingsCard {
            Item {
                id: batteryStrip
                Layout.fillWidth: true
                implicitHeight: 58
                readonly property real track: width
                readonly property real barY: 22
                function at(percent) { return Math.max(0, Math.min(1, percent / 100)) * track; }
                // A label under (or over) a point on the strip, kept inside it
                component Mark: StyledText {
                    required property real percent
                    property bool above: false
                    x: Math.min(batteryStrip.track - width, Math.max(0, batteryStrip.at(percent) - width / 2))
                    y: above ? 2 : batteryStrip.barY + 16
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Rectangle { // Up to critical
                    x: 0; y: batteryStrip.barY
                    width: Math.max(0, batteryStrip.at(page.battery.critical) - 1)
                    height: 10
                    topLeftRadius: 5; bottomLeftRadius: 5
                    color: Appearance.colors.colError
                }
                Rectangle { // Critical to low
                    x: batteryStrip.at(page.battery.critical) + 1; y: batteryStrip.barY
                    width: Math.max(0, batteryStrip.at(page.battery.low) - x - 1)
                    height: 10
                    color: Appearance.colors.colTertiary
                }
                Rectangle { // Low to full
                    x: batteryStrip.at(page.battery.low) + 1; y: batteryStrip.barY
                    width: Math.max(0, batteryStrip.track - x)
                    height: 10
                    topRightRadius: 5; bottomRightRadius: 5
                    color: Appearance.colors.colPrimary
                    opacity: 0.55
                }
                Rectangle { // Where it shuts down
                    visible: page.battery.automaticSuspend
                    x: batteryStrip.at(page.battery.suspend) - 1; y: batteryStrip.barY - 4
                    width: 2; height: 18
                    color: Appearance.colors.colOnLayer1
                }
                Rectangle { // Now
                    x: batteryStrip.at(Battery.percentage * 100) - width / 2; y: batteryStrip.barY - 6
                    width: 6; height: 22
                    radius: 3
                    color: Appearance.colors.colOnLayer0
                    border.width: 2
                    border.color: Appearance.colors.colLayer1
                }
                Mark { percent: page.battery.critical; text: Translation.tr("Critical %1 %").arg(page.battery.critical) }
                Mark { percent: page.battery.low; text: Translation.tr("Low %1 %").arg(page.battery.low) }
                Mark { visible: page.battery.automaticSuspend; above: true; percent: page.battery.suspend; text: Translation.tr("Shuts down %1 %").arg(page.battery.suspend) }
                Mark {
                    above: true
                    percent: Battery.percentage * 100
                    text: Translation.tr("Now %1 %").arg(Math.round(Battery.percentage * 100))
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Notifications")
            ConfigSpinBox {
                text: Translation.tr("Low battery warning at")
                description: Translation.tr("A notification when the battery drops to this")
                option: "battery.low"
                suffix: "%"
                from: 1
                to: 50
                stepSize: 1
            }
            ConfigSpinBox {
                text: Translation.tr("Critical battery warning at")
                description: Translation.tr("A louder warning when it's nearly empty")
                option: "battery.critical"
                suffix: "%"
                from: 1
                to: 25
                stepSize: 1
            }
            ConfigSpinBox {
                text: Translation.tr("Fully charged at")
                tooltip: Translation.tr("A notification to unplug when charging reaches this. 101 % turns it off")
                option: "battery.full"
                suffix: "%"
                from: 90
                to: 101
                stepSize: 1
            }
        }
        ContentSubsection {
            title: Translation.tr("When it runs out")
            ConfigSwitch {
                text: Translation.tr("Shut down when the battery is empty")
                option: "battery.automaticSuspend"
                tooltip: Translation.tr("With a notification first, so you can cancel it")
            }
            ConfigSpinBox {
                text: Translation.tr("Shut down at")
                description: Translation.tr("Where an empty battery shuts the laptop down, so it doesn't die mid-sleep")
                visible: page.battery.automaticSuspend
                option: "battery.suspend"
                suffix: "%"
                from: 1
                to: 60
                stepSize: 1
            }
        }
    }
}
