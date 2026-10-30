import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell.Services.Notifications
// One of a notification's own actions. Beside the text (iconOnly) it's a square icon button with the
// label as a tooltip; labels without a known icon, or wrapped underneath, show as a text chip.
RippleButton {
    id: button
    property string urgency
    property bool iconOnly: false
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
    // Tinted like the picture badges on the left of each row, so the two ends of a row match
    readonly property color tint: critical ? Appearance.colors.colError : Appearance.colors.colPrimary
    colBackground: ColorUtils.transparentize(tint, 0.85)
    colBackgroundHover: ColorUtils.transparentize(tint, 0.72)
    colRipple: ColorUtils.transparentize(tint, 0.6)
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
                color: button.tint
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !button.showIconOnly
                text: buttonText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: button.tint
            }
        }
    }
    StyledToolTip {
        extraVisibleCondition: button.showIconOnly
        text: buttonText
    }
}
