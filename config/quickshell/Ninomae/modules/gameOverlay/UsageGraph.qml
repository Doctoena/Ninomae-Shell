import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A live usage graph on the in-game overlay, on a neutral tile: name and temperature, the average and peak over
// what it shows, the value now, and the last couple of minutes under it (history: 0–1 samples, oldest first)
Rectangle {
    id: root
    property string label
    property real usage
    property real temp
    property var history: []
    property bool warning: false
    readonly property color accent: warning ? Appearance.colors.colError : Appearance.colors.colPrimary
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: root.temp > 0 ? `${root.label} · ${Math.round(root.temp)}°C` : root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            StyledText {
                visible: root.history.length > 1
                text: Translation.tr("avg %1%  ·  peak %2%")
                    .arg(Math.round(root.history.reduce((a, b) => a + b, 0) / Math.max(1, root.history.length) * 100))
                    .arg(Math.round(Math.max(0, ...root.history) * 100))
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: Math.round(root.usage * 100) + "%"
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.numbers
                color: root.accent
            }
    }
        LineGraph {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            // Whatever history there is spans the width, newest on the right
            points: {
                const samples = root.history, last = Math.max(1, samples.length - 1);
                return samples.map((v, i) => Qt.point(1 - (samples.length - 1 - i) / last, v));
            }
            color: root.accent
            emptyText: Translation.tr("Collecting…")
        }
    }
}
