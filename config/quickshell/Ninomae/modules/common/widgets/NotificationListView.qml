pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
StyledListView { // Scrollable window
    id: root
    property bool popup: false
    // A card that grows while a view transition is still moving the cards below it leaves them where its
    // old height put them, overlapping it, until something else changes the list. Cards ask for this when
    // they resize; once things settle, every card is re-placed. A spacing change forces that full layout
    // pass (forceLayout() only applies changes the view already knows about), and the nudge is undone
    // straight away, so only the pass runs. Debounced: a burst of resizes costs one pass
    property real spacingNudge: 0
    spacing: (root.popup ? 8 : 6) + spacingNudge
    function requestRelayout() {
        relayoutTimer.restart();
    }
    Timer {
        id: relayoutTimer
        interval: Appearance.animation.elementMove.duration + 50
        onTriggered: {
            root.spacingNudge = 0.001;
            root.spacingNudge = 0;
        }
    }
    topMargin: 4
    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        anchors.left: parent?.left
        anchors.right: parent?.right
        notificationGroup: popup ?
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
    }
}