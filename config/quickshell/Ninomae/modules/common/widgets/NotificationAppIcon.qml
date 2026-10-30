import qs.modules.common
import qs.modules.common.functions
import "notification_utils.js" as NotificationUtils
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
// A notification's icon: its picture (with the app's icon in the corner), else the app's icon, else a
// symbol for what it's about, picked from the app's name, then the title and text
// (NotificationUtils.findSuitableMaterialSymbol), so notifications without an icon don't all look the same.
// `notify-send -i <icon>` arrives as an "image" (image://icon/<name>): that's shown as an icon, and an
// icon the theme doesn't have falls back to the symbol rather than a missing-image mark
Rectangle {
    id: root
    property string appIcon: ""
    property string appName: ""
    property string summary: ""
    property string body: ""
    property var urgency: NotificationUrgency.Normal
    readonly property bool isUrgent: urgency === NotificationUrgency.Critical
    property string image: ""
    property real imageRadius: Appearance.rounding.verysmall
    property real implicitSize: 38
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: implicitSize * materialIconScale
    property real appIconSize: implicitSize * appIconScale
    property real smallAppIconSize: implicitSize * smallAppIconScale

    // `notify-send -i` arrives as image://icon/<name or path>. A theme name is an icon (drawn inset, it has
    // its own transparent margin); a file (a game's icon on "Clip saved") is a square picture, so it fills
    // the squircle and takes its rounded corners, like other pictures
    readonly property bool imageIsIcon: image.startsWith("image://icon/")
    readonly property string iconArg: imageIsIcon ? image.substring(13) : ""
    readonly property string picture: !imageIsIcon ? image : iconArg.startsWith("/") ? "file://" + iconArg : ""
    // The theme icon to show: the app's, else the one passed as the image; only if the theme has it
    readonly property string iconName: appIcon !== "" ? appIcon : imageIsIcon && !iconArg.startsWith("/") ? iconArg : ""
    readonly property string iconSource: iconName !== "" ? Quickshell.iconPath(iconName, true) : ""

    width: implicitSize
    height: implicitSize
    radius: Appearance.rounding.verysmall
    color: isUrgent ? ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                    : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
    Loader {
        id: materialSymbolLoader
        active: root.picture === "" && root.iconSource === ""
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                const guessed = NotificationUtils.findSuitableMaterialSymbol(root.summary, root.appName, root.body);
                return root.isUrgent && guessed === "chat" ? "priority_high" : guessed;
            }
            anchors.fill: parent
            color: root.isUrgent ? Appearance.colors.colError : Appearance.colors.colPrimary
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: appIconLoader
        active: root.picture === "" && root.iconSource !== ""
        anchors.centerIn: parent
        sourceComponent: IconImage {
            implicitSize: root.appIconSize
            asynchronous: true
            source: root.iconSource
        }
    }
    Loader {
        id: notifImageLoader
        active: root.picture !== ""
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            ClippingRectangle { // Rounded without an offscreen layer per notification
                anchors.fill: parent
                radius: root.imageRadius
                color: "transparent"
                Image {
                    id: notifImage
                    anchors.fill: parent
                    readonly property int size: parent.width
                    source: root.picture
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    asynchronous: true
                    sourceSize.width: size
                    sourceSize.height: size
                }
            }
            Loader {
                id: notifImageAppIconLoader
                active: root.iconSource !== ""
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                sourceComponent: IconImage {
                    implicitSize: root.smallAppIconSize
                    asynchronous: true
                    source: root.iconSource
                }
            }
        }
    }
}
