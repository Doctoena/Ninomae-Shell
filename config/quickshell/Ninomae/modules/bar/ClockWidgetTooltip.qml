import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
// The bar clock's drawer: the time as a header (the greeting, the day and the date beside it), then the weather as a
// banner tinted by the sky (night or day, clear, partly cloudy or grey) with the temperature big on it, and the next
// hours and four facts in a well under it
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

    // The sky for the banner, from the weather's icon: clear, partly cloudy, or grey (overcast, fog, rain, snow, storms)
    readonly property string skyIcon: Weather.data.icon || "cloud"
    readonly property string sky: skyIcon.startsWith("clear") ? "clear" : skyIcon.startsWith("partly") ? "partly" : "grey"
    readonly property bool night: !(Weather.data.isDay ?? true)
    readonly property var skyColours: night
        ? (sky === "grey" ? ["#24283a", "#3a3f55"] : sky === "partly" ? ["#1d2346", "#383a66"] : ["#171f4d", "#3a2d6b"])
        : (sky === "grey" ? ["#4d5870", "#7d889e"] : sky === "partly" ? ["#3a64b8", "#7d9fd6"] : ["#2f6fd6", "#79b2f0"])

    // The content lives as long as the bar, so refresh on opening (skipped while the data is fresh)
    onWantedChanged: if (wanted) Weather.getData()

    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 320
        implicitHeight: mainCol.implicitHeight + 6 // Bottom breathing room
        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 12

            // ═══════ The time; the greeting, the day and the date beside it ═══════
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6
                StyledText {
                    text: DateTime.timeNoAmPm // AM/PM goes beside it, small
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
                ColumnLayout { // The day and the date on lines of their own, so neither is cut off
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: Qt.locale().toString(root.now, "dddd")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: Qt.locale().toString(root.now, "d MMMM")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // ═══════ The sky: now, big ═══════ (the weather's hidden with weather off: it would only show stale or empty values)
            Rectangle {
                visible: Weather.enabled
                Layout.fillWidth: true
                implicitHeight: 118
                radius: Appearance.rounding.normal
                gradient: Gradient {
                    GradientStop { position: 0; color: root.skyColours[0] }
                    GradientStop { position: 1; color: root.skyColours[1] }
                }
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
                Repeater { // A clear (or partly) night: a few stars
                    model: root.night && root.sky !== "grey" ? [[0.12, 0.17], [0.36, 0.12], [0.62, 0.26], [0.84, 0.1], [0.9, 0.42], [0.5, 0.52], [0.24, 0.6]] : []
                    Rectangle {
                        required property var modelData
                        x: modelData[0] * parent.width; y: modelData[1] * parent.height
                        width: 2; height: 2; radius: 1
                        color: Qt.rgba(1, 1, 1, 0.7)
                    }
                }
                MaterialSymbol { // The sky's own icon, large on the right
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    text: root.skyIcon
                    iconSize: 56
                    fill: 1
                    color: Qt.rgba(1, 1, 1, 0.92)
                }
                Column {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 90 }
                    spacing: 1
                    StyledText {
                        text: root.tempNumber
                        font.pixelSize: 44
                        font.weight: Font.Light
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({})
                        color: "white"
                    }
                    Row {
                        spacing: 6
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.data.condition || Translation.tr("Unknown")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: "white"
                        }
                        Rectangle {
                            visible: !!Weather.data.high
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3; height: 3; radius: 1.5
                            color: Qt.rgba(1, 1, 1, 0.6)
                        }
                        StyledText {
                            visible: !!Weather.data.high
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("H %1  L %2").arg(Weather.data.high).arg(Weather.data.low ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Qt.rgba(1, 1, 1, 0.75)
                        }
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: [Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike || "--"), Weather.data.city ?? ""]
                            .filter(t => t).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Qt.rgba(1, 1, 1, 0.7)
                    }
                }
            }

            // ═══════ The next hours and four facts, in a well ═══════
            Item {
                visible: Weather.enabled
                Layout.fillWidth: true
                implicitHeight: wellCol.implicitHeight + 24
                GlassWell {
                    anchors.fill: parent
                }
                ColumnLayout {
                    id: wellCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 14
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
                    GridLayout { // Wind, humidity, the next sunrise or sunset, and rain or UV, straight on the well
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10
                        Repeater {
                            model: root.stats
                            RowLayout {
                                id: stat
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1 // Equal columns whatever the text length
                                spacing: 9
                                Rectangle { // The icon on a light squircle, the glyph in the accent (red as a warning)
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    radius: 10
                                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: stat.modelData.icon
                                        iconSize: 17
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
}
