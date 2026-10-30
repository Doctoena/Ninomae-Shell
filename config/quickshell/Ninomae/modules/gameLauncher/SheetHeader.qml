import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * Header of the details page's panels and sheets (screenshots, achievements, news, art browser):
 * a tinted icon badge, title and subtitle on the left (with showBack, the badge is a back button);
 * on the right, `extras` (filters and the like), then the children (SheetIconButtons) in one group,
 * then the close button on its own.
 */
Item {
    id: root
    property string icon
    property bool iconFilled: false
    property string title
    property string subtitle
    property bool showBack: false
    property string backTip: ""
    default property alias actions: actionRow.data
    property alias extras: extraRow.data
    signal closeRequested()
    signal backRequested()

    anchors { top: parent.top; topMargin: 20; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 16 }
    height: 40

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Rectangle {
            id: badge
            width: 40; height: 40; radius: Appearance.rounding.container
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, root.showBack && backMa.containsMouse ? 0.7 : 0.82)
            Behavior on color { ColorAnimation { duration: 120 } }
            MaterialSymbol {
                anchors.centerIn: parent; iconSize: 20; color: Appearance.colors.colPrimary
                text: root.showBack ? "arrow_back" : root.icon
                fill: root.iconFilled && !root.showBack ? 1 : 0
            }
            MouseArea {
                id: backMa
                anchors.fill: parent
                enabled: root.showBack
                hoverEnabled: true
                cursorShape: root.showBack ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.backRequested()
            }
            StyledToolTip { text: root.backTip; visible: root.showBack && root.backTip !== "" && backMa.containsMouse }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            StyledText {
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: root.subtitle
                visible: text !== ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
    Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 10
        Row {
            id: extraRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
        }
        Rectangle { // The actions, as one group (nothing drawn while none are shown)
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool any: actionRow.implicitWidth > 0
            width: any ? actionRow.implicitWidth + 6 : 0
            height: 36
            radius: Appearance.rounding.container
            color: any ? Appearance.colors.colLayer2 : "transparent" // A step up from the panel, so it stands out over the backdrop
            Row {
                id: actionRow
                anchors.centerIn: parent
                spacing: 2
            }
        }
        SheetIconButton {
            anchors.verticalCenter: parent.verticalCenter
            grouped: false
            iconName: "close"
            tip: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
    }
}
