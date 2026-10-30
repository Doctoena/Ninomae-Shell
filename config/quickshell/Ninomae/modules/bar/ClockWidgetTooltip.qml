import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
BarDrawerPopup { // Slides out of the bar like the launcher (was StyledPopup)
    id: root
    // Whole minutes: with second precision (lock screen, or the seconds option) nothing below re-runs each second
    readonly property real nowMs: Math.floor(DateTime.clock.date.getTime() / 60000) * 60000
    readonly property date now: new Date(nowMs)
    readonly property int currentHour: now.getHours()
    readonly property string greeting: {
        if (currentHour < 6) return Translation.tr("Good night");
        if (currentHour < 12) return Translation.tr("Good morning");
        if (currentHour < 18) return Translation.tr("Good afternoon");
        return Translation.tr("Good evening");
    }
    function clockTime(date, hourOnly) {
        return Qt.locale().toString(date, DateTime.is12Hour ? (hourOnly ? "h AP" : "h:mm AP") : (hourOnly ? "HH:00" : "HH:mm"));
    }

    // Weather
    readonly property string tempNumber: {
        const match = String(Weather.data.temp ?? "").match(/^(-?\d+)/);
        return match ? match[1] + "°" : "--°";
    }
    readonly property string feelsLine: {
        const feels = Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike || "--");
        return Weather.data.high ? `${feels} · ${Translation.tr("H %1  L %2").arg(Weather.data.high).arg(Weather.data.low)}` : feels;
    }
    // The fetch holds 12 hours from when it ran; show the next 6 still ahead
    readonly property var upcoming: (Weather.data.hourly ?? []).filter(h => h.time > now).slice(0, 6)
    readonly property bool anyRain: upcoming.some(h => h.pop >= 20)
    readonly property var nextSunEvent: (Weather.data.sunEvents ?? []).find(e => e.time > now) ?? null
    // The fourth tile shows what matters right now: rain on the way, else strong sun, else the rain outlook
    readonly property var rainHour: upcoming.find(h => h.pop >= 30) ?? null
    readonly property int maxPop: upcoming.reduce((m, h) => Math.max(m, h.pop), 0)
    readonly property var smartStat: {
        if (rainHour) return { icon: "umbrella", value: `${maxPop}%`, label: Translation.tr("Rain by %1").arg(clockTime(rainHour.time, true)), warning: false };
        const uv = Weather.data.uv ?? 0;
        if (Weather.data.isDay && uv >= 3) {
            const level = uv >= 11 ? Translation.tr("extreme") : uv >= 8 ? Translation.tr("very high") : uv >= 6 ? Translation.tr("high") : Translation.tr("moderate");
            return { icon: "light_mode", value: String(uv), label: Translation.tr("UV · %1").arg(level), warning: uv >= 8 };
        }
        return { icon: "umbrella", value: `${maxPop}%`, label: Translation.tr("Rain, next 6h"), warning: false };
    }

    // The content lives as long as the bar, so refresh on opening (skipped while the data is fresh)
    onWantedChanged: if (wanted) Weather.getData()

    // Same structure as the battery popup: hero on the drawer, a sidebar-style card, stat tiles, footer chips
    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 284
        implicitHeight: mainCol.implicitHeight + 6 // Bottom breathing room
        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 12

            // ═══════ Clock ═══════
            PopupHero {
                icon: root.currentHour < 6 || root.currentHour >= 18 ? "dark_mode" : "light_mode"
                text: root.greeting
                headline: DateTime.time
                suffix: DateTime.amPm
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.locale().toString(root.now, "dddd, MMMM d")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            // ═══════ Weather card: now, then the next hours ═══════ (hidden with weather off: it would only show stale or empty values)
            Rectangle {
                visible: Weather.enabled
                Layout.fillWidth: true
                implicitHeight: weatherCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    id: weatherCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    spacing: 12
                    RowLayout { // Accent squircle, temperature and condition, like a sidebar tile at a larger size
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            implicitWidth: 48; implicitHeight: 48
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colPrimary
                            MaterialSymbol { anchors.centerIn: parent; text: Weather.data.icon || "cloud"; iconSize: 26; fill: 1; color: Appearance.colors.colOnPrimary }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                spacing: 8
                                StyledText {
                                    text: root.tempNumber
                                    font.family: Appearance.font.family.expressive
                                    font.pixelSize: 30
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Weather.data.condition || Translation.tr("Unknown")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.feelsLine
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                    Rectangle { // Hairline between now and the forecast
                        visible: root.upcoming.length > 0
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colLayer3
                    }
                    RowLayout { // Next hours: time, icon, temperature, and rain chance when any hour has some
                        visible: root.upcoming.length > 0
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: root.upcoming
                            Item { // An Item, not a layout: a nested layout only stretches if a child does
                                id: hour
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1 // Equal columns
                                implicitHeight: hourCol.implicitHeight
                                ColumnLayout {
                                    id: hourCol
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 3
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.clockTime(hour.modelData.time, true)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: hour.modelData.icon
                                        iconSize: 20
                                        fill: 1
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: hour.modelData.temp
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        visible: root.anyRain
                                        Layout.alignment: Qt.AlignHCenter
                                        opacity: hour.modelData.pop >= 20 ? 1 : 0 // Keeps the columns level
                                        text: hour.modelData.pop + "%"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══════ Weather stats ═══════
            GridLayout {
                visible: Weather.enabled
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 6
                rowSpacing: 6
                StatTile {
                    icon: "air"
                    value: Weather.data.wind || "--"
                    label: Translation.tr("Wind · %1").arg(Weather.data.windDir)
                }
                StatTile { icon: "water_drop"; value: Weather.data.humidity || "--"; label: Translation.tr("Humidity") }
                StatTile {
                    icon: root.nextSunEvent?.sunrise ? "wb_twilight" : "nights_stay"
                    value: root.nextSunEvent ? root.clockTime(root.nextSunEvent.time, false) : "--"
                    label: root.nextSunEvent?.sunrise ? Translation.tr("Sunrise") : Translation.tr("Sunset")
                }
                StatTile {
                    icon: root.smartStat.icon
                    value: root.smartStat.value
                    label: root.smartStat.label
                    warning: root.smartStat.warning
                }
            }

            // ═══════ Footer chips: place, uptime ═══════
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                InfoChip { visible: Weather.enabled && !!Weather.data.city; icon: "location_on"; text: Weather.data.city ?? "" }
                InfoChip { icon: "timer"; text: Translation.tr("Up %1").arg(DateTime.uptime) }
            }
        }
    }
}
