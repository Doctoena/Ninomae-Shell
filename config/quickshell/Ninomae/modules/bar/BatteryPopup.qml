import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
BarDrawerPopup { // Slides out of the bar like the launcher (was StyledPopup)
    id: root
    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    // Unix seconds in whole minutes: with second precision (lock screen) the graph doesn't redraw each second
    readonly property real now: Math.floor(DateTime.clock.date.getTime() / 60000) * 60
    readonly property color accentColor: {
        if (Battery.isLowAndUnplugged) return Appearance.colors.colError;
        if (Battery.isCharging) return Appearance.colors.colPrimary;
        return Appearance.colors.colOnSurfaceVariant;
    }
    readonly property color graphColor: Battery.isLowAndUnplugged ? Appearance.colors.colError : Appearance.colors.colPrimary
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
        if (!(Battery.pluggedSince > 0)) return "--";
        const elapsed = root.now - Battery.pluggedSince;
        return elapsed < 60 ? Translation.tr("Just now") : root.formatTime(elapsed);
    }

    // Same structure as the clock popup: hero on the drawer, a sidebar-style card, stat tiles, footer chips
    Item { // Fixed-width wrapper: the drawer sizes itself from this (a layout ignores a set implicitWidth)
        implicitWidth: 284
        implicitHeight: mainCol.implicitHeight + 6 // Bottom breathing room
        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 12

            // ═══════ Hero: state · time, percentage ═══════
            PopupHero {
                icon: root.stateIcon
                text: root.timeText ? `${root.stateText} · ${root.timeText}` : root.stateText
                accent: root.accentColor
                headline: Battery.percent + "%"
            }

            // ═══════ Charge history: the last 12 hours, like the sidebar's usage graphs ═══════
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: historyCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    id: historyCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    spacing: 6
                        LineGraph {
                            id: graph
                            Layout.fillWidth: true
                            // The log plus a live point for now; the sample from before the span starts at the left edge
                            points: {
                                const span = Battery.historySpan, from = root.now - span;
                                return Battery.history.concat([{ t: root.now, v: Battery.percentage }])
                                    .map(s => Qt.point(Math.max(0, (s.t - from) / span), s.v));
                            }
                            color: root.graphColor
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
            }

            // ═══════ Stats ═══════
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                StatTile {
                    icon: "bolt"
                    value: Battery.energyRate > 0.01 ? Battery.energyRate.toFixed(1) + " W" : "--"
                    label: Battery.isCharging ? Translation.tr("Charging rate") : Translation.tr("Power draw")
                }
                StatTile {
                    icon: Battery.isPluggedIn ? "power" : "power_off"
                    value: root.sinceText
                    label: Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("Unplugged")
                }
            }

            // ═══════ Footer chips: chemistry, voltage, and health only when the firmware reports wear ═══════
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                InfoChip { visible: root.techShort !== ""; icon: "memory"; text: root.techShort }
                InfoChip { visible: Battery.voltage > 0; icon: "electric_meter"; text: Battery.voltage.toFixed(1) + " V" }
                InfoChip {
                    visible: Battery.healthPercent < 99.5
                    icon: "health_and_safety"
                    text: Translation.tr("Health %1%").arg(Battery.healthPercent.toFixed(0))
                }
            }
        }
    }
}
