import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// One slim row of the in-game overlay's Performance, on the neutral surface: its name, the value now (and the
// temperature under it), its last few minutes as a small graph (history: samples, oldest first, drawn against
// ceiling), and two lines at its end (the session's average and peak, or low). The rows' columns line up
Rectangle {
    id: root
    property string label
    property string valueText
    property real temp: 0
    property var history: []
    property real ceiling: 1
    property string sideText
    property bool warning: false
    readonly property color accent: warning ? Appearance.colors.colError : Appearance.colors.colPrimary
    implicitHeight: 48
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    RowLayout {
        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
        spacing: 10
        StyledText {
            Layout.preferredWidth: 30
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        ColumnLayout {
            Layout.preferredWidth: 58
            spacing: -4
            StyledText {
                text: root.valueText
                font.pixelSize: Appearance.font.pixelSize.larger
                font.family: Appearance.font.family.numbers
                font.weight: Font.DemiBold
                color: root.warning ? root.accent : Appearance.colors.colOnLayer2
            }
            StyledText {
                visible: root.temp > 0
                text: Math.round(root.temp) + "°C"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                color: root.temp >= 90 ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }
        LineGraph {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            // Whatever history there is spans the width, newest on the right; a single sample as a level line
            points: {
                const samples = root.history.length === 1 ? [root.history[0], root.history[0]] : root.history;
                const last = Math.max(1, samples.length - 1);
                return samples.map((v, i) => Qt.point(1 - (samples.length - 1 - i) / last, Math.min(1, v / root.ceiling)));
            }
            color: root.accent
        }
        StyledText {
            Layout.preferredWidth: 62
            text: root.sideText
            horizontalAlignment: Text.AlignRight
            lineHeight: 0.9
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colSubtext
        }
    }
}
