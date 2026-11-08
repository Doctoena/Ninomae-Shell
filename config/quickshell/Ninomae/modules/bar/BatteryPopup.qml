import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
// The bar battery's drawer, one card as the clock's weather card: the charge now (squircle, percentage, state, time
// left or to full, the watts), the last 12 hours as a graph, and a footer line (plugged in or out for how long,
// voltage, the chemistry, or the health once the firmware reports wear)
BarDrawerPopup {
    id: root
    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    // Unix seconds in whole minutes: with second precision (lock screen) the graph doesn't redraw each second
    readonly property real now: Math.floor(DateTime.clock.date.getTime() / 60000) * 60
    readonly property bool low: Battery.isLowAndUnplugged
    readonly property color accentColor: low ? Appearance.colors.colError
        : Battery.isCharging ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
    readonly property string stateText: {
        if (Battery.isFullyCharged) return Translation.tr("Fully charged");
        if (Battery.isCharging) return Translation.tr("Charging");
        if (Battery.isPluggedIn) return Translation.tr("Plugged in, not charging");
        return Translation.tr("On battery");
    }
    readonly property string stateIcon: {
        if (Battery.isFullyCharged) return "check_circle";
        if (Battery.isPluggedIn) return "power";
        return "battery_std";
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
        return Battery.isCharging ? Translation.tr("%1 until full").arg(root.formatTime(t))
                                  : Translation.tr("%1 left").arg(root.formatTime(t));
    }
    readonly property string sinceText: {
        if (!(Battery.pluggedSince > 0)) return "";
        const elapsed = root.now - Battery.pluggedSince;
        return elapsed < 60 ? Translation.tr("Just now") : root.formatTime(elapsed);
    }
    // The footer: what's known of it
    readonly property var footer: [
        { icon: Battery.isPluggedIn ? "power" : "power_off", text: sinceText },
        { icon: "electric_meter", text: Battery.voltage > 0 ? Battery.voltage.toFixed(1) + " V" : "" },
        Battery.healthPercent < 99.5 ? { icon: "health_and_safety", text: Translation.tr("Health %1%").arg(Battery.healthPercent.toFixed(0)) }
            : { icon: "memory", text: techShort }
    ].filter(f => f.text !== "")

    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 300
        implicitHeight: card.implicitHeight + 6 // Bottom breathing room
        Rectangle {
            id: card
            anchors { left: parent.left; right: parent.right; top: parent.top }
            implicitHeight: cardCol.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3
            ColumnLayout {
                id: cardCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 14 }
                spacing: 12

                // ═══════ Now: the squircle (accent plugged in, red when low), percentage and state, the watts ═══════
                DrawerNowRow {
                    icon: root.stateIcon
                    iconBackground: root.low ? Appearance.colors.colError : Battery.isPluggedIn ? Appearance.colors.colPrimary : Appearance.colors.colLayer4
                    iconColor: root.low ? Appearance.colors.colOnError : Battery.isPluggedIn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer4
                    value: Battery.percent + "%"
                    valueColor: root.low ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                    label: root.stateText
                    labelColor: root.accentColor
                    detail: root.timeText
                    sideTop: Battery.energyRate > 0.01 ? Battery.energyRate.toFixed(1) + " W" : ""
                    sideBottom: Battery.isCharging ? Translation.tr("Charge rate") : Translation.tr("Draw")
                }

                DrawerHairline {}

                // ═══════ The last 12 hours ═══════
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    LineGraph {
                        Layout.fillWidth: true
                        // The log plus a live point for now; the sample from before the span starts at the left edge
                        points: {
                            const span = Battery.historySpan, from = root.now - span;
                            return Battery.history.concat([{ t: root.now, v: Battery.percentage }])
                                .map(s => Qt.point(Math.max(0, (s.t - from) / span), s.v));
                        }
                        color: root.low ? Appearance.colors.colError : Appearance.colors.colPrimary
                        emptyText: Translation.tr("No history yet")
                    }
                    RowLayout { // Time axis
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1h ago").arg(Battery.historySpan / 3600)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Now")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                DrawerHairline { visible: root.footer.length > 0 }

                // ═══════ Footer: plugged in or out for how long, voltage, chemistry or health ═══════
                RowLayout {
                    visible: root.footer.length > 0
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: root.footer
                        Item { // Equal thirds, each centred
                            id: fact
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: factRow.implicitHeight
                            RowLayout {
                                id: factRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol { text: fact.modelData.icon; iconSize: 15; fill: 1; color: Appearance.colors.colPrimary }
                                StyledText {
                                    text: fact.modelData.text
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer3
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
