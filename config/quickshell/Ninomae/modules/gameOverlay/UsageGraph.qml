import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// One row of the in-game overlay's performance card: the value now, large in its colour, and its name; under it
// the temperature and the session's average and peak; its last few minutes as a graph on the right
// (history: samples, oldest first, 0–1). Warning: all of it red
Item {
    id: root
    property string label
    property string valueText
    property string detail
    property var history: []
    property color colour: Appearance.colors.colPrimary
    property bool warning: false
    readonly property color accent: warning ? Appearance.colors.colError : colour
    implicitHeight: 56
    ColumnLayout {
        id: figures
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 150
        spacing: 0
        RowLayout {
            spacing: 6
            StyledText {
                text: root.valueText
                font.family: Appearance.font.family.numbers
                font.pixelSize: 22
                font.weight: Font.Medium
                color: root.accent
            }
            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            elide: Text.ElideRight
            text: root.detail
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
    LineGraph {
        anchors { left: figures.right; leftMargin: 12; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 4 }
        // Whatever history there is spans the width, newest on the right; a single sample as a level line
        points: {
            const samples = root.history.length === 1 ? [root.history[0], root.history[0]] : root.history;
            const last = Math.max(1, samples.length - 1);
            return samples.map((v, i) => Qt.point(1 - (samples.length - 1 - i) / last, Math.min(1, v)));
        }
        color: root.accent
    }
}
