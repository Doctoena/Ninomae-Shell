import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell.Services.Notifications
// One of a notification's own actions. Beside the text (iconOnly) it's a square icon button with the
// label as a tooltip; labels without a known icon, or wrapped underneath, show as a text chip: the first (primary)
// on the accent squircle with a light along its top (red when urgent), the rest the glass's soft card.
RippleButton {
    id: button
    property string urgency
    property bool iconOnly: false
    property bool primary: false
    readonly property string iconName: {
        const t = (buttonText ?? "").toLowerCase();
        if (t === "open" || t === "view" || t === "show") return "arrow_outward";
        if (t.startsWith("reply")) return "reply";
        if (t.startsWith("mark") && t.includes("read")) return "done_all";
        if (t === "copy") return "content_copy";
        if (t === "dismiss" || t === "close") return "close";
        return "";
    }
    readonly property bool showIconOnly: iconOnly && iconName !== ""
    readonly property bool critical: urgency === NotificationUrgency.Critical.toString()
    implicitHeight: 28
    implicitWidth: showIconOnly ? implicitHeight : contentItem.implicitWidth + leftPadding + rightPadding
    leftPadding: showIconOnly ? 0 : iconName !== "" ? 8 : 12
    rightPadding: showIconOnly ? 0 : 12
    buttonRadius: showIconOnly ? 8 : 9 // Squircles, like the picture badges
    readonly property color tint: critical ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property color ink: primary ? (critical ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary)
        : showIconOnly ? tint : Appearance.colors.colOnLayer3
    colBackground: primary ? tint : Appearance.colors.colWellRowHover
    colBackgroundHover: primary ? ColorUtils.mix(tint, "white", 0.88) : Appearance.colors.colWellRowActive
    colRipple: primary ? ColorUtils.mix(tint, "white", 0.75) : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.8)
    EdgeLight { // The accent squircle's light along its top
        visible: button.primary
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6; topMargin: 1 }
        strength: 0.55
    }
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.iconName !== ""
                text: button.iconName
                iconSize: button.showIconOnly ? 17 : 15
                fill: 1
                color: button.primary ? button.ink : button.tint
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !button.showIconOnly
                text: buttonText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: button.ink
            }
        }
    }
    StyledToolTip {
        extraVisibleCondition: button.showIconOnly
        text: buttonText
    }
}
