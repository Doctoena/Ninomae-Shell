import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
// The bar battery's drawer (M2), in one well: the bar's little battery grown big, the charge filling it in a lit
// gradient with a glow, the state's icon and the percentage on the fill (beside it when the fill is too short) and the
// time left or to full in the empty part; the last 12 hours as a graph in a box tinted the battery's colour, the state in
// the bar's lit capsule and the watts along its top; then what's known as one line with dots between (plugged in or out
// for how long, voltage, the chemistry, or the health once the firmware reports wear)
BarDrawerPopup {
    id: root
    // Unix seconds in whole minutes: with second precision (lock screen) the graph doesn't redraw each second
    readonly property real now: Math.floor(DateTime.clock.date.getTime() / 60000) * 60
    readonly property bool low: Battery.isLowAndUnplugged
    readonly property color accent: low ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property string stateText: {
        if (Battery.isFullyCharged) return Translation.tr("Fully charged");
        if (Battery.isCharging) return Translation.tr("Charging");
        if (Battery.isPluggedIn) return Translation.tr("Plugged in, not charging");
        return Translation.tr("On battery");
    }
    readonly property string stateIcon: {
        if (Battery.isFullyCharged) return "check";
        if (Battery.isCharging) return "bolt";
        if (Battery.isPluggedIn) return "power";
        return low ? "battery_alert" : "battery_std";
    }
    readonly property string techShort: {
        const tech = Battery.technology.toLowerCase();
        if (tech.includes("lithium-ion")) return "Li-ion";
        if (tech.includes("lithium-polymer")) return "Li-Po";
        return Battery.technology;
    }
    // The time left or to full, "1h 4m", and what it is ("until full", "left"); none when full or unknown
    readonly property real timeSeconds: Battery.isFullyCharged ? 0 : Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty
    readonly property string timeFigure: timeSeconds > 0 ? Battery.formatTime(timeSeconds) : ""
    readonly property string timeCaption: Battery.isCharging ? Translation.tr("until full") : Translation.tr("left")
    readonly property string sinceText: {
        if (!(Battery.pluggedSince > 0)) return "";
        const elapsed = root.now - Battery.pluggedSince;
        return elapsed < 60 ? Translation.tr("just now") : Battery.formatTime(elapsed);
    }
    // The facts line: what's known of them
    readonly property var facts: [
        { icon: Battery.isPluggedIn ? "power" : "power_off",
          text: sinceText === "" ? "" : (Battery.isPluggedIn ? Translation.tr("Plugged in %1") : Translation.tr("Unplugged %1")).arg(sinceText) },
        { icon: "electric_meter", text: Battery.voltage > 0 ? Battery.voltage.toFixed(1) + " V" : "" },
        Battery.healthPercent < 99.5 ? { icon: "monitor_heart", text: Translation.tr("%1% health").arg(Battery.healthPercent.toFixed(0)) }
            : { icon: "science", text: techShort }
    ].filter(f => f.text !== "")

    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 300
        implicitHeight: well.implicitHeight + 6 // Bottom breathing room
        Item {
            id: well
            anchors { left: parent.left; right: parent.right; top: parent.top }
            implicitHeight: wellCol.implicitHeight + 24
            GlassWell {
                anchors.fill: parent
            }
            ColumnLayout {
                id: wellCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10

                // ═══════ The battery: its rim, the charge filling it, the figure and the time ═══════
                Item {
                    id: battery
                    Layout.fillWidth: true
                    implicitHeight: 70
                    readonly property real innerWidth: rim.width - 10
                    readonly property real fillWidth: Math.max(rim.height * 0.6 - 10, innerWidth * Math.min(1, Battery.percentage))
                    // The figure on the fill while it's long enough, else beside it in the battery's colour
                    readonly property bool figureOnFill: fillWidth >= figure.implicitWidth + 28
                    // The time in the empty part, when there's room for it beside the fill (and the figure)
                    readonly property real emptyRoom: innerWidth - fillWidth - (figureOnFill ? 0 : figure.implicitWidth + 18)
                    readonly property bool timeInside: root.timeFigure !== "" && emptyRoom >= time.implicitWidth + 24

                    Rectangle {
                        id: rim
                        width: parent.width - 8
                        height: parent.height
                        radius: 20
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border { width: 1.5; color: ColorUtils.transparentize(root.accent, 0.55) }
                        EdgeLight {
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 24; rightMargin: 24 }
                            strength: 0.3
                        }
                        Rectangle { // The fill's glow
                            x: 2
                            y: 2
                            width: fill.width + 6
                            height: parent.height - 4
                            radius: parent.radius - 2
                            color: ColorUtils.transparentize(root.accent, 0.85)
                        }
                        Rectangle {
                            id: fill
                            x: 5
                            y: 5
                            width: battery.fillWidth
                            height: parent.height - 10
                            radius: parent.radius - 5
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: ColorUtils.transparentize(root.accent, 0.35) }
                                GradientStop { position: 1; color: root.accent }
                            }
                            Rectangle { // Its top light
                                x: 10
                                y: 1
                                width: Math.max(0, parent.width - 20)
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.55)
                            }
                        }
                        RowLayout {
                            id: figure
                            anchors {
                                left: parent.left
                                leftMargin: battery.figureOnFill ? 16 : fill.width + 14
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 4
                            readonly property color colour: battery.figureOnFill ? Appearance.colors.colOnPrimary : root.accent
                            MaterialSymbol {
                                text: root.stateIcon
                                fill: 1
                                iconSize: 24
                                color: figure.colour
                            }
                            StyledText {
                                text: Battery.percent + "%"
                                font.pixelSize: 29
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({}) // Not Roboto Flex's tuning
                                color: figure.colour
                            }
                        }
                        ColumnLayout {
                            id: time
                            visible: battery.timeInside
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: -2
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: root.timeFigure
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({})
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: root.timeCaption
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtextGlass
                            }
                        }
                    }
                    Rectangle { // The cap
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 5
                        height: 25
                        radius: 2.5
                        color: ColorUtils.transparentize(root.accent, 0.45)
                    }
                }

                // ═══════ The last 12 hours, the state and the watts along the top of its box ═══════
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 112
                    radius: 12
                    color: ColorUtils.transparentize(root.accent, 0.94)
                    LitCapsule {
                        id: stateCapsule
                        x: 8
                        y: 8
                        width: stateLabel.implicitWidth + 22
                        height: 24
                        colour: root.accent
                        StyledText {
                            id: stateLabel
                            anchors.centerIn: parent
                            // The time joins the state when the battery has no room for it
                            text: battery.timeInside || root.timeFigure === "" ? root.stateText
                                : `${root.stateText} · ${root.timeFigure} ${root.timeCaption}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.accent
                        }
                    }
                    RowLayout {
                        visible: Battery.energyRate > 0.01
                        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 12 }
                        spacing: 4
                        MaterialSymbol {
                            text: Battery.isCharging ? "bolt" : "trending_down"
                            iconSize: 15
                            color: root.accent
                        }
                        StyledText {
                            text: Battery.energyRate.toFixed(1) + " W"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({})
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    LineGraph {
                        // Inset: clear of the state, the time axis and the box's round corners
                        anchors { fill: parent; topMargin: 42; leftMargin: 10; rightMargin: 10; bottomMargin: 22 }
                        guides: false
                        // The log plus a live point for now; the sample from before the span starts at the left edge
                        points: {
                            const span = Battery.historySpan, from = root.now - span;
                            return Battery.history.concat([{ t: root.now, v: Battery.percentage }])
                                .map(s => Qt.point(Math.max(0, (s.t - from) / span), s.v));
                        }
                        color: root.accent
                        emptyText: Translation.tr("No history yet")
                    }
                    RowLayout { // Time axis
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 10; rightMargin: 10; bottomMargin: 5 }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1h ago").arg(Battery.historySpan / 3600)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtextGlass
                        }
                        StyledText {
                            text: Translation.tr("Now")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtextGlass
                        }
                    }
                }

                // ═══════ Plugged in or out for how long, voltage, chemistry or health: one line, dots between ═══════
                RowLayout {
                    visible: root.facts.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    Repeater {
                        model: root.facts
                        RowLayout {
                            required property var modelData
                            required property int index
                            spacing: 8
                            Rectangle { // The dot between facts
                                visible: index > 0
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 3
                                implicitHeight: 3
                                radius: 1.5
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.4
                            }
                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 15
                                color: root.accent
                            }
                            StyledText {
                                Layout.leftMargin: -4
                                text: modelData.text
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }
        }
    }
}
