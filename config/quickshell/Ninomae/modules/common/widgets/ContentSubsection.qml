import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// A smaller group inside a ContentSection: its name, then its rows (cards of their own)
ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    default property alias contentData: sectionContent.data
    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 6
    RowLayout {
        visible: root.title.length > 0
        Layout.leftMargin: 4
        ContentSubsectionLabel { text: root.title }
        InfoTip { tip: root.tooltip }
        Item { Layout.fillWidth: true }
    }
    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: 4
    }
}
