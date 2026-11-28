pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Widgets

// A window, popup or picture a click would take. Outlined faintly (outlineOpacity); a picture in the tertiary colour
// with a Picture tag in its corner. The one under the cursor is lit: an accent rim and tint (a picture's tag says a
// click takes it). Glass: the name labels are the selector's dark unblurred glass with a fine rim
Item {
    id: root
    required property var clientDimensions
    property bool isPicture: false
    property bool targeted: false
    property real outlineOpacity: 1
    property string name: ""
    property string iconName: "" // A window's: its class, looked up as an app icon
    property real radius: Appearance.rounding.verysmall
    property bool showLabel: Config.options.regionSelector.targetRegions.showLabel // Every window's name in its corner
    readonly property color colAccent: isPicture ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
    readonly property color colCard: Appearance.colors.colGlassUnblurred
    readonly property string iconSource: iconName !== "" ? Quickshell.iconPath(AppSearch.guessIcon(iconName), "image-missing") : ""
    z: 2
    visible: opacity > 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    x: clientDimensions.at[0]
    y: clientDimensions.at[1]
    width: clientDimensions.size[0]
    height: clientDimensions.size[1]

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.targeted ? ColorUtils.transparentize(root.colAccent, 0.92) : ColorUtils.transparentize(root.colAccent, 1)
        border.width: root.targeted ? 2 : root.isPicture ? 1.5 : 1
        border.color: root.targeted ? root.colAccent
            : root.isPicture ? ColorUtils.transparentize(root.colAccent, 1 - root.outlineOpacity)
            : ColorUtils.transparentize("white", 1 - root.outlineOpacity * 0.8)
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    }

    // A picture's tag, in its corner
    Rectangle {
        visible: root.isPicture && root.width >= implicitWidth + 16 && root.height >= 38
        x: 8; y: 8
        implicitWidth: tagText.implicitWidth + 14
        implicitHeight: 22
        radius: 7
        color: ColorUtils.transparentize(root.colAccent, root.targeted ? 0 : 0.15)
        StyledText {
            id: tagText
            anchors.centerIn: parent
            text: root.targeted ? Translation.tr("Click to take this picture") : Translation.tr("Picture")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.m3colors.m3onTertiary
        }
    }

    // Every window's name in its corner (Settings: regionSelector.targetRegions.showLabel)
    Rectangle {
        visible: root.showLabel && !root.isPicture
        x: 10; y: 10
        radius: 8
        color: root.colCard
        border { width: 1; color: Appearance.colors.colGlassFieldRim }
        implicitWidth: labelRow.implicitWidth + 20
        implicitHeight: labelRow.implicitHeight + 10
        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: 6
            IconImage {
                visible: root.iconName !== ""
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Appearance.font.pixelSize.larger
                source: root.iconSource
            }
            StyledText {
                text: root.name
                color: Appearance.colors.colOnLayer0
            }
        }
    }
}
