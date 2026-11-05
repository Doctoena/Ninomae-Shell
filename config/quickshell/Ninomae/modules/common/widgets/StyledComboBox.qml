import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A dropdown in the shell's squircle style: a neutral squircle button, and a list of neutral rows on a raised
 * surface where the current option is the accent one (its name in accent, a check in an accent squircle),
 * as active items are everywhere else. options: [{ displayName, value }]. value picks the one shown (numbers match within
 * 0.001, so a scale of 1.0 finds 1); fallbackText shows when none matches, e.g. a scale Hyprland rounded.
 */
ComboBox {
    id: root
    property var options: []
    property var value // Not currentValue: ComboBox has its own (read-only)
    property string fallbackText: ""
    signal selected(var newValue)

    function matches(a, b) {
        return a === b || (typeof a === "number" && typeof b === "number" && Math.abs(a - b) < 0.001);
    }

    model: options
    textRole: "displayName"
    valueRole: "value"
    currentIndex: options.findIndex(o => matches(o.value, root.value))
    displayText: currentIndex >= 0 ? currentText : fallbackText
    // One width for every menu in a section (so they line up), wider when the text needs it
    property real minimumWidth: 160
    implicitWidth: Math.max(minimumWidth, contentItem.implicitWidth + 8)
    implicitHeight: 35 // Same as the spin boxes
    readonly property int rowHeight: 34 // A row of the list (2 px apart)

    indicator: MaterialSymbol {
        x: root.width - width - 12
        y: (root.availableHeight - height) / 2
        text: "expand_more"
        color: Appearance.colors.colPrimary
        iconSize: 18
        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    contentItem: StyledText {
        leftPadding: 14
        rightPadding: 34
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.displayText
        color: Appearance.colors.colOnLayer2
        font.pixelSize: Appearance.font.pixelSize.small
    }
    background: Rectangle { // The option buttons' surface: the spin boxes' colLayer2 barely shows on a card
        radius: Appearance.rounding.small
        color: root.down || root.popup.visible || root.hovered ? Appearance.m3colors.m3surfaceContainerHighest
            : Appearance.m3colors.m3surfaceContainerHigh
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
    popup: Popup {
        y: root.height + 4
        width: root.width
        // Opens upward when the list wouldn't fit below (a menu near the bottom of the screen)
        onAboutToShow: {
            const win = root.Window.window;
            const below = win ? win.height - root.mapToItem(null, 0, root.height).y : Infinity;
            // From the option count: the list may not have laid out its rows yet
            const h = Math.min(root.options.length * (root.rowHeight + 2), 300) + 2 * padding;
            y = below < h + 12 ? -h - 4 : root.height + 4;
        }
        padding: 5
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 120; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 }
        }
        background: Rectangle { // A step up from what it opens over, with a hairline edge
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
        }
        contentItem: ListView {
            clip: true
            spacing: 2
            implicitHeight: Math.min(contentHeight, 300)
            model: root.options
            delegate: Rectangle {
                id: popupItem
                required property var modelData
                required property int index
                readonly property bool current: root.currentIndex === index
                width: ListView.view.width
                height: root.rowHeight
                radius: Appearance.rounding.segment
                // Neutral; hovered a step up. The current one is the accent's: its name and its check
                color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerHighest, popupMouseArea.containsMouse ? 0 : 1) // Fades its own tint, not black
                Behavior on color { ColorAnimation { duration: 120 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 7
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: popupItem.modelData.displayName
                        elide: Text.ElideRight
                        color: popupItem.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: popupItem.current ? Font.DemiBold : Font.Normal
                    }
                    Rectangle { // The accent squircle, as an active item's
                        visible: popupItem.current
                        implicitWidth: 22; implicitHeight: 22
                        radius: Appearance.rounding.chip
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            color: Appearance.colors.colOnPrimary
                            iconSize: 15
                        }
                    }
                }
                MouseArea {
                    id: popupMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.popup.close();
                        root.selected(popupItem.modelData.value);
                    }
                }
            }
        }
    }
}
