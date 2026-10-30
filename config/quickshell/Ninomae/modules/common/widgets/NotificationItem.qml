import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions
import "notification_utils.js" as NotificationUtils
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// One notification: picture (or the app's icon) on the left, title and body beside it, the app's
// own actions at the right edge (or wrapped underneath when there are many). Copy / dismiss appear
// on hover, so idle cards stay clean.
Item {
    id: root
    property var notificationObject
    property bool expanded: false
    property bool onlyNotification: false
    property bool compact: false // Sidebar: smaller picture, tighter padding, shorter collapsed body
    property bool showTime: !onlyNotification // A single notification's time is already in the group header
    property real dragConfirmThreshold: 70
    property real dismissOvershoot: 20
    property var qmlParent: root?.parent?.parent
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0
    readonly property bool isUrgent: notificationObject?.urgency === NotificationUrgency.Critical.toString()
    readonly property int actionCount: notificationObject?.actions?.length ?? 0
    // Always on the newest notification of a group; the older ones only once expanded
    readonly property bool showActions: actionCount > 0 && (expanded || onlyNotification || root.index === 0)
    readonly property bool actionsBelow: actionCount > 2 // Three or more don't fit beside the text
    readonly property bool actionsInline: showActions && !actionsBelow
    readonly property bool actionsWrapped: showActions && actionsBelow
    readonly property string bodyContent: processNotificationBody(notificationObject?.body ?? "", notificationObject?.appName || notificationObject?.summary).replace(/\n/g, "<br/>")
    // Collapsed group rows get one line in the sidebar (two in popups); a lone notification a few more
    readonly property int bodyLines: expanded ? 10 : onlyNotification ? (compact ? 3 : 10) : (compact ? 1 : 2)
    implicitHeight: background.implicitHeight

    function processNotificationBody(body, appName) {
        // No <img> tags: Qt would load them, and a remote one tells its server you're looking (tracking
        // pixel). App icons and image previews come from their own fields, not the body
        let processedBody = (body ?? "").replace(/<\s*img\b[^>]*>/gi, "")
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]
            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = processedBody.split('\n\n')
                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }
        return processedBody
    }
    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin;
        destroyAnimation.left = left;
        destroyAnimation.running = true;
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
            Notifications.discardNotification(notificationObject?.notificationId);
        }
    }
    DragManager {
        id: dragManager
        anchors.fill: root
        interactive: expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
            }
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
        width: parent.width
        anchors.left: parent.left
        anchors.leftMargin: root.xOffset
        radius: Appearance.rounding.normal
        // A soft highlight under the row being pointed at
        color: rowHover.hovered ? ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.95) : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        implicitHeight: row.implicitHeight + (root.compact ? 10 : 16)
        HoverHandler { id: rowHover }

        RowLayout {
            id: row
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; topMargin: root.compact ? 5 : 8 }
            spacing: root.compact ? 10 : 12

            // ── Picture: the notification's image (avatar, game art…), or the app's icon in a tinted badge ──
            NotificationAppIcon {
                Layout.alignment: Qt.AlignTop
                implicitSize: root.compact ? 28 : 36
                radius: root.compact ? 9 : 12 // Squircle, like the quick toggles' icons
                imageRadius: root.compact ? 9 : 12
                image: root.notificationObject?.image ?? ""
                appIcon: root.notificationObject?.appIcon ?? ""
                appName: root.notificationObject?.appName ?? ""
                summary: root.notificationObject?.summary ?? ""
                body: root.notificationObject?.body ?? ""
                urgency: root.isUrgent ? NotificationUrgency.Critical : NotificationUrgency.Normal
                color: root.isUrgent ? ColorUtils.transparentize(Appearance.colors.colError, 0.82)
                                     : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.compact ? 0 : 2

                // Title, with the time (or, on hover, copy / dismiss) at the end
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumHeight: root.compact ? 18 : 22
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.notificationObject?.summary || ""
                        textFormat: Text.PlainText // Plain text by spec; markup here would also load <img>
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.isUrgent ? Appearance.colors.colError : Appearance.colors.colOnSurface
                    }
                    Item { // Time and the hover buttons share this corner
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Math.max(timeText.visible ? timeText.implicitWidth : 0, hoverButtons.implicitWidth)
                        implicitHeight: hoverButtons.implicitHeight
                        StyledText {
                            id: timeText
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            visible: root.showTime
                            opacity: rowHover.hovered ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            text: NotificationUtils.getFriendlyNotifTimeString(root.notificationObject?.time)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            font.variableAxes: ({}) // Not Roboto Flex's tuning (its light wght would win over font.weight)
                            color: Appearance.colors.colSubtext
                        }
                        Row {
                            id: hoverButtons
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            opacity: rowHover.hovered ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            RowIconButton {
                                id: copyButton
                                compact: root.compact
                                iconName: copied ? "check" : "content_copy"
                                tooltipText: Translation.tr("Copy")
                                property bool copied: false
                                onClicked: {
                                    Quickshell.clipboardText = root.notificationObject?.body ?? "";
                                    copied = true;
                                    copiedReset.restart();
                                }
                                Timer { id: copiedReset; interval: 1500; onTriggered: copyButton.copied = false }
                            }
                            RowIconButton {
                                compact: root.compact
                                iconName: "close"
                                tooltipText: Translation.tr("Dismiss")
                                onClicked: root.destroyWithAnimation()
                            }
                        }
                    }
                }

                StyledText { // Body
                    Layout.fillWidth: true
                    visible: root.bodyContent !== ""
                    text: root.bodyContent
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: root.bodyLines
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                        GlobalStates.sidebarRightOpen = false
                    }
                    PointingHandLinkHover {}
                }

                Flow { // Many actions: wrapped underneath
                    Layout.fillWidth: true
                    Layout.topMargin: root.compact ? 4 : 6
                    visible: root.actionsWrapped
                    spacing: 6
                    Repeater {
                        model: root.actionsWrapped ? (root.notificationObject?.actions ?? []) : []
                        delegate: actionButton
                    }
                }
            }

            Row { // A few actions ("Open", "Reply"…): icon buttons at the right edge, centred on the row
                Layout.alignment: Qt.AlignVCenter
                visible: root.actionsInline
                spacing: 4
                Repeater {
                    model: root.actionsInline ? (root.notificationObject?.actions ?? []) : []
                    delegate: actionButton
                }
            }
        }
    }

    Component {
        id: actionButton
        NotificationActionButton {
            required property var modelData
            implicitHeight: root.compact ? 24 : 28
            iconOnly: !root.actionsBelow
            buttonText: modelData.text
            urgency: root.notificationObject?.urgency ?? ""
            onClicked: Notifications.attemptInvokeAction(root.notificationObject?.notificationId, modelData.identifier)
        }
    }

    // Small round icon button for the hover corner ("icon" is a reserved Button property, hence iconName)
    component RowIconButton: RippleButton {
        id: iconButton
        property string iconName
        property string tooltipText
        property bool compact: false
        implicitWidth: compact ? 22 : 26; implicitHeight: implicitWidth
        buttonRadius: implicitWidth / 2
        padding: 0
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.88)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.8)
        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: iconButton.iconName
                iconSize: 16
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
        StyledToolTip { text: iconButton.tooltipText }
    }
}
