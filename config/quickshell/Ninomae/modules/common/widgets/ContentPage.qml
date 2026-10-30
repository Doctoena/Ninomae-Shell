import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

/**
 * A Settings page: its cards in one column that stretches with the window (up to maxWidth), centred.
 */
StyledFlickable {
    id: root
    property real margin: 20
    property real maxWidth: 1260
    property real bottomContentPadding: 24
    default property alias contentData: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + margin + bottomContentPadding
    implicitWidth: contentColumn.implicitWidth + margin * 2

    ColumnLayout {
        id: contentColumn
        y: root.margin
        x: (root.width - width) / 2
        width: Math.min(root.width - root.margin * 2, root.maxWidth)
        spacing: 14
    }
}
