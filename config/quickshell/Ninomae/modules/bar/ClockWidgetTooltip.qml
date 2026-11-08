import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
// The bar clock's drawer: the time as a header (greeting and date beside it), then the weather as one joined block,
// as the sidebar joins its cards: now and the next hours in one card, four stats under it
BarDrawerPopup {
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
    // The fetch holds 12 hours from when it ran; show the next 6 still ahead
    readonly property var upcoming: (Weather.data.hourly ?? []).filter(h => h.time > now).slice(0, 6)
    readonly property bool anyRain: upcoming.some(h => h.pop >= 20)
    readonly property var nextSunEvent: (Weather.data.sunEvents ?? []).find(e => e.time > now) ?? null
    // The fourth stat shows what matters right now: rain on the way, else strong sun, else the rain outlook
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
    readonly property var stats: [
        { icon: "air", value: Weather.data.wind || "--", label: Translation.tr("Wind · %1").arg(Weather.data.windDir), warning: false },
        { icon: "water_drop", value: Weather.data.humidity || "--", label: Translation.tr("Humidity"), warning: false },
        { icon: nextSunEvent?.sunrise ? "wb_twilight" : "nights_stay", value: nextSunEvent ? clockTime(nextSunEvent.time, false) : "--",
          label: nextSunEvent?.sunrise ? Translation.tr("Sunrise") : Translation.tr("Sunset"), warning: false },
        smartStat
    ]

    // The content lives as long as the bar, so refresh on opening (skipped while the data is fresh)
    onWantedChanged: if (wanted) Weather.getData()

    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 300
        implicitHeight: mainCol.implicitHeight + 6 // Bottom breathing room
        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 12

            // ═══════ The time; the greeting and date beside it ═══════
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6
                StyledText {
                    text: DateTime.time
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 46
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    visible: text !== ""
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 9
                    text: DateTime.amPm
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    spacing: 0
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 4
                        MaterialSymbol {
                            text: root.currentHour < 6 || root.currentHour >= 18 ? "dark_mode" : "light_mode"
                            iconSize: 14
                            fill: 1
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: root.greeting
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: Qt.locale().toString(root.now, "dddd d MMMM")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            // ═══════ The weather, joined ═══════ (hidden with weather off: it would only show stale or empty values)
            ColumnLayout {
                visible: Weather.enabled
                Layout.fillWidth: true
                spacing: 4
                Card { // Now, then the next hours
                    topLeftRadius: Appearance.rounding.normal
                    topRightRadius: Appearance.rounding.normal
                    implicitHeight: nowCol.implicitHeight + 24
                    ColumnLayout {
                        id: nowCol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 14 }
                        spacing: 12
                        DrawerNowRow { // The icon, temperature and condition, feels like and the place; today's high and low
                            icon: Weather.data.icon || "cloud"
                            value: root.tempNumber
                            label: Weather.data.condition || Translation.tr("Unknown")
                            detail: [Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike || "--"), Weather.data.city ?? ""]
                                .filter(t => t).join(" · ")
                            sideTop: Weather.data.high ? Translation.tr("H %1").arg(Weather.data.high) : ""
                            sideBottom: Translation.tr("L %1").arg(Weather.data.low ?? "")
                            sideBottomSize: Appearance.font.pixelSize.small
                        }
                        DrawerHairline { visible: root.upcoming.length > 0 } // Between now and the next hours
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
                                            color: Appearance.colors.colOnLayer3
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: hour.modelData.temp
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer3
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
                GridLayout { // Wind, humidity, the next sunrise or sunset, and rain or UV
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 4
                    rowSpacing: 4
                    Repeater {
                        model: root.stats
                        Card {
                            id: stat
                            required property var modelData
                            required property int index
                            Layout.preferredWidth: 1 // Equal columns whatever the text length
                            implicitHeight: 48
                            bottomLeftRadius: index === 2 ? Appearance.rounding.normal : Appearance.rounding.joined
                            bottomRightRadius: index === 3 ? Appearance.rounding.normal : Appearance.rounding.joined
                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                spacing: 10
                                Rectangle { // The icon on a neutral squircle, the glyph in the accent (red as a warning)
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    radius: 10
                                    color: Appearance.colors.colLayer4
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: stat.modelData.icon
                                        iconSize: 18
                                        fill: 1
                                        color: stat.modelData.warning ? Appearance.colors.colError : Appearance.colors.colPrimary
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -1
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: stat.modelData.value
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: Font.DemiBold
                                        color: stat.modelData.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: stat.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A piece of the joined weather block: slight corners, the block's outer ones set where it's used
    component Card: Rectangle {
        Layout.fillWidth: true
        color: Appearance.colors.colLayer3
        topLeftRadius: Appearance.rounding.joined
        topRightRadius: Appearance.rounding.joined
        bottomLeftRadius: Appearance.rounding.joined
        bottomRightRadius: Appearance.rounding.joined
    }
}
