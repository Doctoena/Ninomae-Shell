import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
// The bar clock's drawer (N1d): a small clock face on the left, its hands in the accent, with the next six hours'
// weather sitting at their own hours round it and that stretch of the face lit; beside it the greeting, the time, the
// date and the weather now; then four facts on one line with dots between (wind, humidity, the next sunrise or sunset,
// and rain or UV), each naming itself when pointed at
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
    readonly property var nextSunEvent: (Weather.data.sunEvents ?? []).find(e => e.time > now) ?? null
    // The fourth stat shows what matters right now: rain on the way, else strong sun, else the rain outlook
    readonly property var rainHour: upcoming.find(h => h.pop >= 30) ?? null
    readonly property int maxPop: upcoming.reduce((m, h) => Math.max(m, h.pop), 0)
    readonly property var smartStat: {
        if (rainHour) return { icon: "umbrella", value: `${maxPop}%`, label: Translation.tr("Rain by %1").arg(clockTime(rainHour.time, true)), warning: false };
        const uv = Weather.data.uv ?? 0;
        if (Weather.data.isDay && uv >= 3) {
            const level = uv >= 11 ? Translation.tr("extreme") : uv >= 8 ? Translation.tr("very high") : uv >= 6 ? Translation.tr("high") : Translation.tr("moderate");
            return { icon: "light_mode", value: Translation.tr("UV %1").arg(uv), label: Translation.tr("UV · %1").arg(level), warning: uv >= 8 };
        }
        return { icon: "umbrella", value: `${maxPop}%`, label: Translation.tr("Rain, next 6h"), warning: false };
    }
    readonly property var stats: [
        { icon: "air", value: [Weather.data.wind || "--", Weather.data.windDir].filter(t => t).join(" "), label: Translation.tr("Wind · %1").arg(Weather.data.windDir), warning: false },
        { icon: "water_drop", value: Weather.data.humidity || "--", label: Translation.tr("Humidity"), warning: false },
        { icon: nextSunEvent?.sunrise ? "wb_twilight" : "nights_stay", value: nextSunEvent ? clockTime(nextSunEvent.time, false) : "--",
          label: nextSunEvent?.sunrise ? Translation.tr("Sunrise") : Translation.tr("Sunset"), warning: false },
        smartStat
    ]

    readonly property string skyIcon: Weather.data.icon || "cloud"

    // The content lives as long as the bar, so refresh on opening (skipped while the data is fresh)
    onWantedChanged: if (wanted) Weather.getData()

    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 320
        implicitHeight: mainCol.implicitHeight + 6 // Bottom breathing room
        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // ═══════ The clock face ═══════
                Item {
                    id: dial
                    implicitWidth: 150
                    implicitHeight: 150
                    readonly property real radius: width / 2
                    // Where an hour (with its minutes) sits round the face, from 12 at the top, clockwise
                    function angle(hours) { return (hours % 12) / 12 * Math.PI * 2 - Math.PI / 2; }
                    readonly property real nowAngle: angle(root.currentHour + root.now.getMinutes() / 60)
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
                    }
                    Canvas {
                        id: face
                        anchors.fill: parent
                        // Redrawn each minute, and when the hours or the accent change
                        readonly property var paintKey: [root.nowMs, root.upcoming.length, Weather.enabled, Appearance.colors.colPrimary, Appearance.colors.colLayer0]
                        onPaintKeyChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d");
                            c.reset();
                            const cx = width / 2, cy = height / 2, r = dial.radius;
                            const accent = Appearance.colors.colPrimary;
                            const tint = a => Qt.rgba(accent.r, accent.g, accent.b, a);
                            c.lineCap = "round";
                            if (Weather.enabled && root.upcoming.length > 0) { // The next six hours lit
                                const from = dial.nowAngle, to = from + Math.PI;
                                c.beginPath(); c.moveTo(cx, cy); c.arc(cx, cy, r - 2, from, to); c.closePath();
                                c.fillStyle = tint(0.07); c.fill();
                                c.beginPath(); c.arc(cx, cy, r - 3, from, to);
                                c.strokeStyle = tint(0.7); c.lineWidth = 2; c.stroke();
                            }
                            for (let i = 0; i < 12; i++) { // Hour dots, bigger at 12, 3, 6 and 9
                                const a = dial.angle(i), big = i % 3 === 0;
                                c.beginPath(); c.arc(cx + (r - 11) * Math.cos(a), cy + (r - 11) * Math.sin(a), big ? 2.4 : 1.5, 0, Math.PI * 2);
                                c.fillStyle = Qt.rgba(1, 1, 1, big ? 0.6 : 0.3); c.fill();
                            }
                            const hourAngle = dial.nowAngle, minuteAngle = root.now.getMinutes() / 60 * Math.PI * 2 - Math.PI / 2;
                            const hand = (a, length, width, colour) => {
                                c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + length * Math.cos(a), cy + length * Math.sin(a));
                                c.strokeStyle = colour; c.lineWidth = width; c.stroke();
                            };
                            hand(hourAngle, r * 0.4, 9, tint(0.25)); // Its glow
                            hand(hourAngle, r * 0.4, 3.75, accent);
                            hand(minuteAngle, r * 0.6, 1.65, "white");
                            c.beginPath(); c.arc(cx, cy, 3.75, 0, Math.PI * 2); c.fillStyle = accent; c.fill();
                            c.beginPath(); c.arc(cx, cy, 1.5, 0, Math.PI * 2); c.fillStyle = Appearance.colors.colLayer0; c.fill();
                        }
                    }
                    Repeater { // The next hours at their own places round the face
                        model: Weather.enabled ? root.upcoming : []
                        Column {
                            required property var modelData
                            readonly property real a: dial.angle(modelData.time.getHours())
                            x: dial.radius + dial.radius * 0.66 * Math.cos(a) - width / 2
                            y: dial.radius + dial.radius * 0.66 * Math.sin(a) - height / 2
                            spacing: -2
                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                iconSize: 16
                                fill: 1
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.temp
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({})
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }

                // ═══════ The greeting, the time, the date and the weather now ═══════
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: root.currentHour < 6 || root.currentHour >= 18 ? "dark_mode" : "light_mode"
                            iconSize: 13
                            fill: 1
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: root.greeting
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }
                    }
                    RowLayout {
                        spacing: 4
                        StyledText {
                            text: DateTime.timeNoAmPm // AM/PM goes beside it, small
                            font.family: Appearance.font.family.expressive
                            font.pixelSize: 40
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            visible: text !== ""
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 8
                            text: DateTime.amPm
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtextGlass
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Qt.locale().toString(root.now, "dddd, d MMM")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtextGlass
                    }
                    // The weather's hidden with weather off: it would only show stale or empty values
                    RowLayout {
                        visible: Weather.enabled
                        Layout.topMargin: 6
                        spacing: 6
                        MaterialSymbol {
                            text: root.skyIcon
                            iconSize: 22
                            fill: 1
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: root.tempNumber
                            font.pixelSize: 22
                            font.weight: Font.Light
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Weather.data.condition || Translation.tr("Unknown")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    StyledText {
                        visible: Weather.enabled
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: [Weather.data.high ? Translation.tr("H %1  L %2").arg(Weather.data.high).arg(Weather.data.low ?? "") : "",
                               Translation.tr("feels %1").arg(Weather.data.tempFeelsLike || "--")].filter(t => t).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtextGlass
                    }
                }
            }

            // ═══════ Wind, humidity, the next sunrise or sunset, and rain or UV: one line, dots between ═══════
            Rectangle {
                visible: Weather.enabled
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }
            RowLayout {
                visible: Weather.enabled
                Layout.alignment: Qt.AlignHCenter
                spacing: 7
                Repeater {
                    model: root.stats
                    RowLayout {
                        id: stat
                        required property var modelData
                        required property int index
                        spacing: 7
                        HoverHandler { id: statHover } // What it is, when pointed at
                        StyledToolTip {
                            extraVisibleCondition: statHover.hovered
                            text: stat.modelData.label
                        }
                        Rectangle { // The dot between facts
                            visible: stat.index > 0
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 3
                            implicitHeight: 3
                            radius: 1.5
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.4
                        }
                        MaterialSymbol {
                            text: stat.modelData.icon
                            iconSize: 15
                            color: stat.modelData.warning ? Appearance.colors.colError : Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.leftMargin: -3
                            text: stat.modelData.value
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: stat.modelData.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                        }
                    }
                }
            }
        }
    }
}
