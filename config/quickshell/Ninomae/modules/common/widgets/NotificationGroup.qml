import qs.services
import qs.modules.common
import "notification_utils.js" as NotificationUtils
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
/**
 * A group of notifications from the same app.
 * A soft card; collapsed it shows the newest two (one in popups), expanded all of them.
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    readonly property bool compact: !popup // The sidebar packs cards tighter; popups keep the roomier layout
    // Collapsed, a popup is a heads-up: just the newest. The sidebar shows the newest two
    readonly property int collapsedRows: popup ? 1 : 2
    readonly property bool moreHidden: !expanded && notificationCount > collapsedRows
    readonly property var newestFirst: notifications.slice().reverse()
    // A view transition still moving the cards below won't notice this one grew (see NotificationListView)
    onImplicitHeightChanged: root.ListView.view?.requestRelayout?.()
    property real padding: compact ? 4 : 8 // Rows carry their own padding (and hover highlight)
    implicitHeight: background.implicitHeight
    property real dragConfirmThreshold: 70
    property real dismissOvershoot: 20
    property var qmlParent: root?.parent?.parent
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0
    readonly property bool isUrgent: notifications.some(n => n.urgency === NotificationUrgency.Critical.toString())
    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin;
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }
    hoverEnabled: true
    onContainsMouseChanged: {
        if (!root.popup) return;
        if (root.containsMouse) root.notifications.forEach(notif => {
            Notifications.cancelTimeout(notif.notificationId);
        });
        else root.notifications.forEach(notif => {
            Notifications.restartTimeout(notif.notificationId);
        });
    }
    SequentialAnimation {
        id: destroyAnimation
        property bool left: true
        running: false
        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    Notifications.discardNotification(notif.notificationId);
                });
            });
        }
    }
    function toggleExpanded() {
        root.expanded = !root.expanded;
    }
    DragManager {
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton)
                root.destroyWithAnimation();
        }
        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }
        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }
        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else
                dragManager.resetDrag();
        }
    }
    Rectangle {
        id: background
        anchors.left: parent.left
        width: parent.width
        radius: Appearance.rounding.large
        anchors.leftMargin: root.xOffset
        clip: true
        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        color: popup ? Appearance.colors.colLayer1 : Appearance.colors.colLayer2 // Soft card inside the popup drawer / sidebar
        // Sized by its rows (a fixed cap cut rows off once they got thumbnails). Animated both ways, and
        // clipped, so expanding reveals the extra rows as the card grows
        implicitHeight: contentCol.implicitHeight + padding * 2
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        ColumnLayout {
            id: contentCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: root.padding
            }
            spacing: 2
            // ── Header: app icon, name and time, plus the count / expand chip for groups ──
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 4
                Layout.topMargin: root.compact ? 2 : 4
                spacing: 6
                NotificationAppIcon {
                    implicitSize: 18
                    radius: 6
                    materialIconScale: 0.8
                    appIconScale: 0.9
                    image: ""
                    appIcon: notificationGroup?.appIcon || ""
                    appName: notificationGroup?.appName || ""
                    summary: notificationGroup?.notifications[root.notificationCount - 1]?.summary || ""
                    body: notificationGroup?.notifications[root.notificationCount - 1]?.body || ""
                    urgency: root.isUrgent ? NotificationUrgency.Critical : NotificationUrgency.Normal
                    color: "transparent"
                }
                StyledText {
                    elide: Text.ElideRight
                    Layout.fillWidth: false
                    Layout.maximumWidth: 240
                    text: notificationGroup?.appName || ""
                    textFormat: Text.PlainText
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                }
                StyledText {
                    readonly property string time: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                    visible: time !== ""
                    text: "· " + time
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                NotificationGroupExpandButton {
                    id: expandButton
                    visible: root.multipleNotifications
                    Layout.alignment: Qt.AlignVCenter
                    count: root.notificationCount
                    expanded: root.expanded
                    fontSize: Appearance.font.pixelSize.smallest
                    onClicked: { root.toggleExpanded() }
                    altAction: () => { root.toggleExpanded() }
                    StyledToolTip {
                        text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                    }
                }
            }
            // ── Notification items list ──
            StyledListView {
                id: notificationsColumn
                implicitHeight: contentHeight
                Layout.fillWidth: true
                spacing: 0
                interactive: false
                model: ScriptModel {
                    values: root.expanded ? root.newestFirst : root.newestFirst.slice(0, root.collapsedRows)
                }
                delegate: NotificationItem {
                    required property int index
                    required property var modelData
                    notificationObject: modelData
                    expanded: root.expanded
                    compact: root.compact
                    onlyNotification: (root.notificationCount === 1)
                    // One row showing: its time is the header's. Several: each has its own
                    showTime: root.notificationCount > 1 && (root.expanded || root.collapsedRows > 1)
                    // The last collapsed row fades when more are hidden below it (not a lone row in popups)
                    opacity: root.moreHidden && root.collapsedRows > 1 && index === root.collapsedRows - 1 ? 0.5 : 1
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                }
            }
        }
    }
}
