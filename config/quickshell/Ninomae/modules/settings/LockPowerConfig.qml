import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.lock
ContentPage {
    id: page
    readonly property var lock: Config.options.lock
    readonly property var battery: Config.options.battery

    ContentSection {
        icon: "lock"
        title: Translation.tr("Lock screen")
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 28
            // A little lock screen as yours looks: the wallpaper (blurred as set), the clock, the password.
            // Centred against the settings beside it
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 8
                Layout.preferredWidth: 340
                spacing: 8
                ClippingRectangle {
                    id: lockPreview
                    Layout.alignment: Qt.AlignHCenter // In the middle of its half, as the Display page's screen
                    Layout.preferredWidth: 340
                    Layout.preferredHeight: Math.round(340 * 9 / 16)
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
                    Rectangle { // A soft shade, as the lock screen dims the wallpaper
                        anchors.fill: parent
                        color: "black"
                        opacity: 0.25
                    }
                    StyledText { // The clock
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.18 }
                        text: DateTime.time
                        font.pixelSize: Math.round(lockPreview.height * 0.2)
                        font.weight: Font.DemiBold
                        color: "white"
                    }
                    Rectangle { // The password field
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.16 }
                        width: parent.width * 0.5
                        height: Math.round(parent.height * 0.15)
                        radius: height / 2
                        color: Appearance.colors.colLayer1
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
            ColumnLayout { // The settings
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 4
                ContentSubsection {
                    title: Translation.tr("Security")
                    ConfigSwitch {
                        buttonIcon: "login"
                        text: Translation.tr("Lock at login")
                        option: "lock.launchOnStartup"
                        tooltip: Translation.tr("For logins that skip the password, like auto-login")
                    }
                    ConfigSwitch {
                        buttonIcon: "key"
                        text: Translation.tr("Unlocking also unlocks the keyring")
                        option: "lock.security.unlockKeyring"
                        tooltip: Translation.tr("Where saved passwords and the game launcher's API keys are kept")
                    }
                    ConfigSwitch {
                        buttonIcon: "power_settings_new"
                        text: Translation.tr("Ask for the password to power off")
                        option: "lock.security.requirePasswordToPower"
                        tooltip: Translation.tr("For the power buttons on the lock screen")
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Look")
                    ConfigSwitch {
                        buttonIcon: "shapes"
                        text: Translation.tr("Shapes instead of dots in the password")
                        option: "lock.materialShapeChars"
                    }
                    ConfigSwitch {
                        buttonIcon: "blur_on"
                        text: Translation.tr("Blur the wallpaper")
                        option: "lock.blur.enable"
                    }
                    ConfigSpinBox {
                        icon: "blur_medium"
                        text: Translation.tr("Blur amount")
                        visible: page.lock.blur.enable
                        option: "lock.blur.radius"
                        suffix: "px"
                        from: 0
                        to: 200
                        stepSize: 10
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "battery_full"
        title: Translation.tr("Battery")
        visible: Battery.available // Only on machines with one
        spacing: 10
        // The thresholds on one strip, 0 to 100 %: shut down and critical in red, low in amber, the rest the
        // accent, and where the battery is now
        Item {
            id: batteryStrip
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
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
        ContentSubsection {
            title: Translation.tr("Warnings")
            ConfigSpinBox {
                icon: "battery_alert"
                text: Translation.tr("Low battery warning at")
                option: "battery.low"
                suffix: "%"
                from: 1
                to: 50
                stepSize: 1
            }
            ConfigSpinBox {
                icon: "battery_very_low"
                text: Translation.tr("Critical battery warning at")
                option: "battery.critical"
                suffix: "%"
                from: 1
                to: 25
                stepSize: 1
            }
        }
        ContentSubsection {
            title: Translation.tr("Charging")
            ConfigSpinBox {
                icon: "battery_full"
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
                buttonIcon: "power_settings_new"
                text: Translation.tr("Shut down when the battery is empty")
                option: "battery.automaticSuspend"
                tooltip: Translation.tr("With a notification first, so you can cancel it")
            }
            ConfigSpinBox {
                icon: "battery_0_bar"
                text: Translation.tr("Shut down at")
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
