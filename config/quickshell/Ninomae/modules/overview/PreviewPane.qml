import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick.Shapes
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

/**
 * Right-hand side of the launcher: a large preview of the selected result
 * (SearchItem), adapting to its kind: app, emoji, math, clipboard text/image, or action.
 */
Rectangle {
    id: root
    property Item item // The selected SearchItem
    readonly property bool hasItem: item !== null && item !== undefined
    readonly property bool isApp: hasItem && item.itemType == Translation.tr("App")
    readonly property bool isEmoji: hasItem && item.bigText !== ""
    // Emoji results also carry cliphistRawString, so exclude them here
    readonly property bool isClipboard: hasItem && item.cliphistRawString !== "" && !isEmoji
    readonly property bool isClipboardImage: isClipboard && Cliphist.entryIsImage(item.cliphistRawString)
    readonly property bool isMath: hasItem && item.materialSymbol === "calculate"

    radius: 20
    color: Appearance.colors.colLayer1
    clip: true

    // Cross-fade + small lift whenever the selection changes
    onItemChanged: swapAnim.restart()
    ParallelAnimation {
        id: swapAnim
        NumberAnimation { target: body; property: "opacity"; from: 0.25; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: body; property: "lift"; from: 8; to: 0; duration: 260; easing.type: Easing.OutCubic }
    }

    // Soft lavender glow behind the hero icon
    Shape {
        id: heroGlow
        anchors.horizontalCenter: parent.horizontalCenter
        y: body.y + heroBox.y + heroBox.height / 2 - height / 2
        width: 260
        height: 260
        visible: !root.isClipboardImage && !root.isClipboard
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: heroGlow.width / 2; centerY: heroGlow.height / 2
                focalX: centerX; focalY: centerY
                centerRadius: heroGlow.width // Stop 0.5 lands on the edge, as with the old effect
                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7) }
                GradientStop { position: 0.5; color: "transparent" }
            }
            PathRectangle { width: heroGlow.width; height: heroGlow.height }
        }
    }

    ColumnLayout {
        id: body
        property real lift: 0
        visible: root.hasItem
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: lift
            margins: 24
        }
        spacing: 10

        Item { // Hero: icon, emoji, symbol or clipboard image
            id: heroBox
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 6
            implicitWidth: heroLoader.implicitWidth
            implicitHeight: heroLoader.implicitHeight
            Loader {
                id: heroLoader
                anchors.centerIn: parent
                sourceComponent: root.isClipboardImage ? clipImage
                    : root.isEmoji ? emoji
                    : (root.hasItem && root.item.itemIcon !== "" && root.item.materialSymbol === "") ? appIcon
                    : symbol
            }
        }

        StyledText { // Title (math result shown large in monospace)
            Layout.fillWidth: true
            visible: !root.isClipboard
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.hasItem ? root.item.itemName : ""
            color: Appearance.colors.colOnLayer1
            font.pixelSize: root.isMath ? 30 : Appearance.font.pixelSize.huge
            font.family: root.isMath ? Appearance.font.family.monospace : Appearance.font.family.title
            font.weight: Font.DemiBold
        }

        StyledText { // Description / kind
            Layout.fillWidth: true
            visible: !root.isClipboard && text !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: !root.hasItem ? ""
                : root.isApp ? root.item.itemSubtitle
                : root.item.itemType
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText { // Clipboard text, shown in full (up to a point)
            Layout.fillWidth: true
            Layout.maximumHeight: 190
            visible: root.isClipboard && !root.isClipboardImage
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 9
            elide: Text.ElideRight
            text: root.isClipboard ? root.item.itemName : ""
            color: Appearance.colors.colOnLayer1
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RippleButton { // Primary action
            id: actionButton
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            implicitHeight: 40
            implicitWidth: actionRow.implicitWidth + 32
            buttonRadius: 12
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: if (root.hasItem) root.item.clicked()
            contentItem: Item {
                RowLayout {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 8
                    StyledText {
                        // Clipboard and emoji results have no action name; they copy
                        text: !root.hasItem ? ""
                            : root.item.itemClickActionName !== "" ? root.item.itemClickActionName
                            : (root.isClipboard || root.isEmoji) ? Translation.tr("Copy")
                            : Translation.tr("Open")
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                    }
                    StyledText {
                        text: "↵"
                        color: Appearance.colors.colOnPrimary
                        opacity: 0.7
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }

    Component {
        id: appIcon
        IconImage {
            implicitSize: 88
            source: Quickshell.iconPath(root.item?.itemIcon || "image-missing") // No lookup for an empty name
        }
    }
    Component {
        id: emoji
        StyledText {
            text: root.item?.bigText ?? ""
            font.pixelSize: 72
        }
    }
    Component {
        id: symbol
        MaterialSymbol {
            text: root.item?.materialSymbol || "search"
            iconSize: 64
            color: Appearance.colors.colPrimary
        }
    }
    Component {
        id: clipImage
        CliphistImage {
            entry: root.item?.cliphistRawString ?? ""
            maxWidth: root.width - 48
            maxHeight: root.height - 120
        }
    }
}
