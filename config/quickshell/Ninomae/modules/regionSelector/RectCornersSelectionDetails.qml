import qs.modules.common
import qs.modules.common.widgets
import QtQuick
Item {
    id: root
    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    required property color overlayColor
    property bool showAimLines: Config.options.regionSelector.rect.showAimLines
    // Overlay to darken screen
    // Base dark overlay around region
    Rectangle {
        id: darkenOverlay
        z: 1
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX - darkenOverlay.border.width
            topMargin: root.regionY - darkenOverlay.border.width
        }
        width: root.regionWidth + darkenOverlay.border.width * 2
        height: root.regionHeight + darkenOverlay.border.width * 2
        color: "transparent"
        border.color: root.overlayColor
        border.width: Math.max(root.width, root.height)
    }
    // Selection border
    Rectangle {
        id: selectionBorder
        z: 1
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX
            topMargin: root.regionY
        }
        width: root.regionWidth
        height: root.regionHeight
        color: "transparent"
        border.color: root.color
        border.width: 2
        radius: Appearance.rounding.verysmall
    }
    // Corner handles
    Repeater {
        model: [
            { cx: root.regionX, cy: root.regionY, sx: 1, sy: 1 },                              // top-left
            { cx: root.regionX + root.regionWidth, cy: root.regionY, sx: -1, sy: 1 },           // top-right
            { cx: root.regionX, cy: root.regionY + root.regionHeight, sx: 1, sy: -1 },          // bottom-left
            { cx: root.regionX + root.regionWidth, cy: root.regionY + root.regionHeight, sx: -1, sy: -1 }  // bottom-right
        ]
        Item {
            required property var modelData
            z: 2
            x: modelData.cx - (modelData.sx > 0 ? 0 : _handleSize)
            y: modelData.cy - (modelData.sy > 0 ? 0 : _handleSize)
            width: _handleSize
            height: _handleSize
            readonly property real _handleSize: 18
            readonly property real _handleThickness: 4
            // Horizontal arm
            Rectangle {
                width: parent._handleSize
                height: parent._handleThickness
                y: parent.modelData.sy > 0 ? 0 : parent.height - height
                color: root.color
                radius: 2
            }
            // Vertical arm
            Rectangle {
                width: parent._handleThickness
                height: parent._handleSize
                x: parent.modelData.sx > 0 ? 0 : parent.width - width
                color: root.color
                radius: 2
            }
        }
    }
    // Dimension badge
    Rectangle {
        z: 2
        visible: root.regionWidth > 0 && root.regionHeight > 0
        anchors {
            top: selectionBorder.bottom
            horizontalCenter: selectionBorder.horizontalCenter
            topMargin: 8
        }
        color: Appearance.colors.colLayer0
        radius: 8 // Squircle chip, like the rest of the shell's 24 px chips
        implicitWidth: dimText.implicitWidth + 16
        implicitHeight: 24
        StyledText {
            id: dimText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer0
            text: `${Math.round(root.regionWidth)} × ${Math.round(root.regionHeight)}`
        }
    }
    // Aim lines
    Rectangle { // Vertical
        visible: root.showAimLines
        opacity: 0.35
        z: 2
        x: root.mouseX
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: root.color
    }
    Rectangle { // Horizontal
        visible: root.showAimLines
        opacity: 0.35
        z: 2
        y: root.mouseY
        anchors {
            left: parent.left
            right: parent.right
        }
        height: 1
        color: root.color
    }
    // Mouse coordinate badge
    Rectangle {
        visible: root.showAimLines
        z: 3
        x: root.mouseX + 12
        y: root.mouseY + 12
        color: Appearance.colors.colLayer0
        radius: 8
        implicitWidth: coordText.implicitWidth + 14
        implicitHeight: 24
        StyledText {
            id: coordText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: `${Math.round(root.mouseX)}, ${Math.round(root.mouseY)}`
        }
    }
}
