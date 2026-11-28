import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// The in-game overlay's "While you played": notifications since the game started (since, ms), newest first.
// The newest is featured as in the sidebar: tinted by its app icon's colour (IconColours), a halo, its text in
// full and its buttons named (Open, and the app's own). The older ones are a line each. A click on one with
// something to open (its app's default action, as a Discord message's, or the click command it brought) opens
// it and the overlay closes (activated). × or Clear dismisses them (from the sidebar too). Hidden when there
// are none
ColumnLayout {
    id: root
    property real since: 0
    readonly property var items: since > 0 ? Notifications.list.filter(n => n.time >= since && !isSteamTip(n)).reverse() : []
    readonly property var newest: items[0] ?? null
    // Steam's tip that comes with every game it starts ("Press Shift+Tab to begin"): nothing missed
    function isSteamTip(n) { return /^steam$/i.test(n.appName) && /Shift\+Tab/.test(`${n.summary} ${n.body}`); }
    signal activated()
    function hasDefault(n) { return n.actions.some(a => a.identifier === "default"); }
    function openable(n) { return hasDefault(n) || !!n.execArgv; }
    function open(n) {
        if (hasDefault(n)) Notifications.attemptInvokeAction(n.notificationId, "default");
        else {
            Quickshell.execDetached(n.execArgv);
            Notifications.discardNotification(n.notificationId);
        }
        root.activated();
    }
    function plain(text) { return (text ?? "").replace(/<[^>]*>/g, ""); }
    function ago(n) {
        const minutes = Math.floor((Date.now() - n.time) / 60000);
        return minutes < 1 ? Translation.tr("now") : minutes < 60 ? Translation.tr("%1 min").arg(minutes) : Translation.tr("%1 h").arg(Math.floor(minutes / 60));
    }
    visible: items.length > 0
    spacing: 4

    OverlayPanelHead {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        icon: "notifications"
        title: Translation.tr("While you played")
        detail: root.items.length === 1 ? Translation.tr("1 notification") : Translation.tr("%1 notifications").arg(root.items.length)
        OverlayChip {
            iconName: "clear_all"
            label: Translation.tr("Clear")
            onClicked: root.items.forEach(n => Notifications.discardNotification(n.notificationId))
        }
    }

    // ── The newest, featured ──
    Rectangle {
        id: featured
        readonly property var n: root.newest
        readonly property bool urgent: n?.urgency === NotificationUrgency.Critical.toString()
        readonly property string appIcon: n?.appIcon ?? ""
        onAppIconChanged: IconColours.request(appIcon)
        Component.onCompleted: IconColours.request(appIcon)
        readonly property color tint: urgent ? Appearance.colors.colError : IconColours.colourFor(appIcon)
        readonly property var namedActions: (n?.actions ?? []).filter(a => a.identifier !== "default" && a.text).slice(0, 2)
        Layout.fillWidth: true
        visible: n !== null
        implicitHeight: featuredColumn.implicitHeight + 28
        topLeftRadius: Appearance.rounding.normal
        topRightRadius: Appearance.rounding.normal
        bottomLeftRadius: root.items.length > 1 ? Appearance.rounding.joined : Appearance.rounding.normal
        bottomRightRadius: bottomLeftRadius
        color: ColorUtils.mix(Appearance.colors.colLayer3, tint, 0.86)
        border.width: 1.5
        border.color: ColorUtils.transparentize(tint, 0.6)
        clip: true
        MouseArea {
            anchors.fill: parent
            cursorShape: featured.n && root.openable(featured.n) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (featured.n && root.openable(featured.n)) root.open(featured.n)
        }
        Halo {
            colour: featured.tint
            strength: 0.42
            reach: 32 // Within the card's edge from the icon's centre, or it shows a straight cut
            centreX: featuredIcon.x + featuredIcon.width / 2
            centreY: featuredIcon.y + featuredIcon.height / 2
        }
        NotificationAppIcon {
            id: featuredIcon
            x: 14
            y: 14
            implicitSize: 40
            radius: Appearance.rounding.small
            appIcon: featured.n?.appIcon ?? ""
            appName: featured.n?.appName ?? ""
            summary: featured.n?.summary ?? ""
            body: featured.n?.body ?? ""
            image: featured.n?.image ?? ""
            urgency: featured.urgent ? NotificationUrgency.Critical : NotificationUrgency.Normal
        }
        ColumnLayout {
            id: featuredColumn
            anchors { left: featuredIcon.right; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 36; topMargin: 14 }
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.preferredWidth: Math.min(implicitWidth, 200) // Not from the row's width: that loops the layout
                    elide: Text.ElideRight
                    text: featured.n?.summary ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    id: featuredWhen
                    Layout.fillWidth: true
                    text: featured.n ? [featured.n.appName, root.ago(featured.n)].filter(t => t).join("  ·  ") : ""
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.plain(featured.n?.body)
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.1)
            }
            RowLayout { // Its buttons, named
                Layout.topMargin: 8
                visible: featured.n !== null && (root.openable(featured.n) || featured.namedActions.length > 0)
                spacing: 4
                RippleButton {
                    visible: featured.n !== null && root.openable(featured.n)
                    implicitHeight: 30
                    implicitWidth: openRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.segment
                    colBackground: ColorUtils.transparentize(featured.tint, 0.72)
                    colBackgroundHover: ColorUtils.transparentize(featured.tint, 0.6)
                    colRipple: ColorUtils.transparentize(featured.tint, 0.5)
                    onClicked: root.open(featured.n)
                    contentItem: Item {
                        RowLayout {
                            id: openRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                text: "open_in_new"
                                iconSize: 15
                                color: Appearance.colors.colOnLayer3
                            }
                            StyledText {
                                text: Translation.tr("Open")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer3
                            }
                        }
                    }
                }
                Repeater {
                    model: featured.namedActions
                    RippleButton {
                        required property var modelData
                        implicitHeight: 30
                        implicitWidth: actionText.implicitWidth + 24
                        buttonRadius: Appearance.rounding.segment
                        colBackground: Appearance.colors.colLayer4
                        colBackgroundHover: Appearance.colors.colLayer4Hover
                        colRipple: Appearance.colors.colLayer4Active
                        onClicked: Notifications.attemptInvokeAction(featured.n.notificationId, modelData.identifier)
                        contentItem: StyledText {
                            id: actionText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.text
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer3
                        }
                    }
                }
            }
        }
        DismissButton {
            anchors { right: parent.right; top: parent.top; margins: 8 }
            onClicked: Notifications.discardNotification(featured.n.notificationId)
        }
    }

    // ── The older ones, a line each ──
    Repeater {
        model: root.items.slice(1)
        Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool openable: root.openable(modelData)
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Appearance.rounding.joined
            bottomLeftRadius: index === root.items.length - 2 ? Appearance.rounding.normal : Appearance.rounding.joined
            bottomRightRadius: bottomLeftRadius
            color: openable && rowMouse.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.openable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (row.openable) root.open(row.modelData)
            }
            RowLayout {
                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 10
                NotificationAppIcon {
                    implicitSize: 24
                    radius: Appearance.rounding.chip - 1
                    appIcon: row.modelData.appIcon
                    appName: row.modelData.appName
                    summary: row.modelData.summary
                    body: row.modelData.body
                    image: row.modelData.image
                    urgency: row.modelData.urgency === NotificationUrgency.Critical.toString() ? NotificationUrgency.Critical : NotificationUrgency.Normal
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: `<b>${StringUtils.escapeHtml(row.modelData.summary)}</b>  ${StringUtils.escapeHtml(root.plain(row.modelData.body).split("\n")[0])}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    text: root.ago(row.modelData)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                DismissButton {
                    onClicked: Notifications.discardNotification(row.modelData.notificationId)
                }
            }
        }
    }

    component DismissButton: RippleButton {
        implicitWidth: 26
        implicitHeight: 26
        buttonRadius: Appearance.rounding.verysmall
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.8)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: "close"
            iconSize: 16
            color: Appearance.colors.colSubtext
        }
        StyledToolTip { text: Translation.tr("Dismiss") }
    }
}
