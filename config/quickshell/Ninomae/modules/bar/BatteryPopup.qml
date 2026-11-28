import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
// The bar battery's drawer (B3), in one well like the sidebar's machine: the charge as a big ring (its state's icon
// inside, red when low) with the percentage, the state and the time left or to full beside it; the last 12 hours as a
// graph in a box tinted the ring's colour, the watts on it; then what's known as stat pieces (plugged in or out for
// how long, voltage, the chemistry, or the health once the firmware reports wear)
BarDrawerPopup {
    id: root
    // Unix seconds in whole minutes: with second precision (lock screen) the graph doesn't redraw each second
    readonly property real now: Math.floor(DateTime.clock.date.getTime() / 60000) * 60
    readonly property bool low: Battery.isLowAndUnplugged
    readonly property color ringColor: low ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property color stateColor: low ? Appearance.colors.colError
        : Battery.isPluggedIn ? Appearance.colors.colPrimary : Appearance.colors.colSubtextGlass
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
    readonly property string timeText: {
        if (Battery.isFullyCharged) return "";
        const t = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
        if (!(t > 0)) return "";
        return Battery.isCharging ? Translation.tr("%1 until full").arg(Battery.formatTime(t))
                                  : Translation.tr("%1 left").arg(Battery.formatTime(t));
    }
    readonly property string sinceText: {
        if (!(Battery.pluggedSince > 0)) return "";
        const elapsed = root.now - Battery.pluggedSince;
        return elapsed < 60 ? Translation.tr("Just now") : Battery.formatTime(elapsed);
    }
    // The pieces: what's known of them
    readonly property var pieces: [
        { value: sinceText, label: Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("Unplugged") },
        { value: Battery.voltage > 0 ? Battery.voltage.toFixed(1) + " V" : "", label: Translation.tr("Voltage") },
        Battery.healthPercent < 99.5 ? { value: Battery.healthPercent.toFixed(0) + "%", label: Translation.tr("Health") }
            : { value: techShort, label: Translation.tr("Chemistry") }
    ].filter(p => p.value !== "")

    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 300
        implicitHeight: well.implicitHeight + 6 // Bottom breathing room
        Item {
            id: well
            anchors { left: parent.left; right: parent.right; top: parent.top }
            implicitHeight: wellCol.implicitHeight + 20
            GlassWell {
                anchors.fill: parent
            }
            ColumnLayout {
                id: wellCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 10

                // ═══════ Now: the charge as a ring, the percentage, the state and the time beside it ═══════
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    UsageRing {
                        size: 72
                        stroke: 6
                        fraction: Battery.percentage
                        colour: root.ringColor
                        icon: root.stateIcon
                        iconSize: 28
                        iconFill: 1
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                id: figure
                                text: Battery.percent + "%"
                                font.pixelSize: 34
                                font.weight: Font.DemiBold
                                font.family: Appearance.font.family.numbers
                                font.variableAxes: ({}) // Not Roboto Flex's tuning
                                color: root.low ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignBaseline
                                elide: Text.ElideRight
                                text: root.stateText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: root.stateColor
                            }
                        }
                        StyledText {
                            visible: text !== ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.timeText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtextGlass
                        }
                    }
                }

                // ═══════ The last 12 hours, in a box tinted the ring's colour, the watts on it ═══════
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 112
                    radius: 12
                    color: ColorUtils.transparentize(root.ringColor, 0.94)
                    LineGraph {
                        // Inset: clear of the watts, the time axis and the box's round corners
                        anchors { fill: parent; topMargin: 34; leftMargin: 10; rightMargin: 10; bottomMargin: 22 }
                        guides: false
                        // The log plus a live point for now; the sample from before the span starts at the left edge
                        points: {
                            const span = Battery.historySpan, from = root.now - span;
                            return Battery.history.concat([{ t: root.now, v: Battery.percentage }])
                                .map(s => Qt.point(Math.max(0, (s.t - from) / span), s.v));
                        }
                        color: root.ringColor
                        emptyText: Translation.tr("No history yet")
                    }
                    StyledText {
                        visible: Battery.energyRate > 0.01
                        anchors { left: parent.left; top: parent.top; leftMargin: 12; topMargin: 8 }
                        text: Battery.energyRate.toFixed(1) + " W"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        font.variableAxes: ({})
                        color: root.ringColor
                    }
                    StyledText {
                        visible: Battery.energyRate > 0.01
                        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 12 }
                        text: Battery.isCharging ? Translation.tr("Charge rate") : Translation.tr("Draw")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtextGlass
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

                // ═══════ Plugged in or out for how long, voltage, chemistry or health, as pieces ═══════
                RowLayout {
                    visible: root.pieces.length > 0
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.pieces
                        StatPiece {
                            required property var modelData
                            value: modelData.value
                            label: modelData.label
                        }
                    }
                }
            }
        }
    }
}
