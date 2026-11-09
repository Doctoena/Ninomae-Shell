import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
/**
 * A quick toggle tile, one piece of the joined block (AndroidQuickPanel). Wide: the icon on a squircle, the
 * name and state, and a › that opens its page in the control centre. Small: the squircle alone, with the name
 * beside it when the row leaves room. Being on shows in the accent: a solid squircle, the name in accent.
 * Clicking toggles; a right click also opens the page (GroupButton's altAction), the › is the visible way.
 * In edit mode: click turns it on or off, right-click changes its size, drag moves it (AndroidQuickPanel).
 */
GroupButton {
    id: root
    // The Repeater fills index and modelData; chooser is the AndroidToggleDelegateChooser that made this tile
    required property int index
    required property var modelData
    required property var chooser
    readonly property var buttonData: modelData
    readonly property bool expandedSize: modelData.size > 1
    required property string buttonIcon
    required property string name
    required property var mainAction
    property string statusText: toggled ? Translation.tr("On") : Translation.tr("Off")
    readonly property bool editMode: chooser.editMode
    readonly property var panel: chooser.panel

    // Dragged in edit mode: it follows the pointer, a little larger, over everything else; where it would land
    // shows as an accent line beside the tile there. Over the unused toggles it fades: let go to take it out
    readonly property bool dragging: editModeInteraction.dragging
    property real dragX: 0
    property real dragY: 0
    transform: Translate { x: root.dragX; y: root.dragY }
    scale: dragging ? 1.05 : 1
    Behavior on scale { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    z: dragging ? 10 : 0
    readonly property bool isDropTarget: !!panel && panel.dragType !== "" && panel.dragType !== buttonData.type
        && panel.dropType === buttonData.type
    readonly property bool leaving: dragging && !!panel && panel.dropUnused && !chooser.unused
    signal openMenu()

    // Its corners: round where it's a corner of the block, slight elsewhere. Held, every corner rounds off
    readonly property real outerRadius: Appearance.rounding.normal
    readonly property real innerRadius: Appearance.rounding.joined
    readonly property bool firstRow: chooser.rowIndex === 0 && !(panel?.joinedAbove && !chooser.unused)
    // The block's last row, unless the sliders join under it (then its bottom corners stay slight too)
    readonly property bool lastRow: chooser.rowIndex === chooser.rowCount - 1 && !(panel?.joinedBelow && !chooser.unused)
    readonly property bool firstInRow: index === 0
    readonly property bool lastInRow: index === chooser.rowLength - 1
    function corner(isOuter) { return root.down || isOuter ? root.outerRadius : root.innerRadius; }
    // Small tiles outside edit mode are pieces of one strip: square where they meet, the icon plain while off
    readonly property bool inStrip: !expandedSize && !chooser.editMode && !chooser.unused
    function edge(isOuter, meetsNeighbour) { return root.inStrip && meetsNeighbour && !root.down ? 0 : root.corner(isOuter); }

    bounce: false
    baseWidth: chooser.cellWidth
    baseHeight: chooser.cellHeight
    implicitWidth: baseWidth
    implicitHeight: baseHeight
    padding: 0
    colBackground: Appearance.colors.colLayer3
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colBackgroundActive: Appearance.colors.colLayer3Active
    colBackgroundToggled: Appearance.colors.colLayer3
    colBackgroundToggledHover: Appearance.colors.colLayer3Hover
    colBackgroundToggledActive: Appearance.colors.colLayer3Active
    property color colText: toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
    readonly property bool hasMenu: expandedSize && !!altAction
    // A small tile shows its name too when the whole name fits beside the icon (margins, icon, gap, a little air)
    readonly property bool showName: !expandedSize && nameMetrics.advanceWidth + 9 * 2 + 30 + 9 + 8 <= width
    TextMetrics {
        id: nameMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        text: root.name
    }

    opacity: appeared ? (leaving ? 0.45 : 1) : 0
    property bool appeared: false
    Component.onCompleted: appeared = true
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    onClicked: root.mainAction()

    background: Rectangle {
        topLeftRadius: root.edge(root.firstRow && root.firstInRow, !root.firstInRow)
        topRightRadius: root.edge(root.firstRow && root.lastInRow, !root.lastInRow)
        bottomLeftRadius: root.edge(root.lastRow && root.firstInRow, !root.firstInRow)
        bottomRightRadius: root.edge(root.lastRow && root.lastInRow, !root.lastInRow)
        color: root.color
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        Behavior on topLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on topRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    }

    contentItem: RowLayout {
        id: contentItem
        spacing: 9
        anchors {
            fill: parent
            leftMargin: 9
            rightMargin: root.hasMenu ? 2 : 9
        }
        Item { visible: !root.expandedSize; Layout.fillWidth: true } // A small tile: icon and name centred together
        // The icon on a squircle: solid accent when on, a neutral circle when off
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.expandedSize ? 32 : 30
            implicitHeight: implicitWidth
            radius: root.toggled ? implicitWidth * 0.32 : implicitWidth / 2
            color: root.toggled ? Appearance.colors.colPrimary : root.inStrip ? "transparent" : Appearance.colors.colLayer4
            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                fill: root.toggled ? 1 : 0
                iconSize: 18
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer4
                text: root.buttonIcon
            }
        }
        // Name and state on wide tiles, the name alone on a roomy small one
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: root.expandedSize
            visible: root.expandedSize || root.showName
            spacing: 0
            StyledText {
                Layout.fillWidth: root.expandedSize
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.colText
                elide: Text.ElideRight
                text: root.name
            }
            StyledText {
                visible: root.expandedSize && root.statusText !== ""
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                text: root.statusText
            }
        }
        Item { visible: !root.expandedSize; Layout.fillWidth: true }
        // Opens the tile's page
        Loader {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: true
            visible: root.hasMenu
            active: visible
            sourceComponent: MouseArea {
                id: menuArea
                implicitWidth: 24
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.altAction()
                Rectangle { // Hover highlight behind the ›
                    anchors.centerIn: parent
                    width: 24; height: 30
                    radius: 8
                    color: ColorUtils.transparentize(root.colText, menuArea.containsPress ? 0.85 : menuArea.containsMouse ? 0.92 : 1)
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    Rectangle { // Where a dragged tile would land: before or after this one
        visible: root.isDropTarget
        width: 3
        height: parent.height - 12
        radius: 2
        anchors.verticalCenter: parent.verticalCenter
        x: root.panel?.dropBefore ? -3.5 : parent.width + 0.5
        color: Appearance.colors.colPrimary
    }

    MouseArea { // Edit mode: click turns a toggle on or off, right-click changes its size, drag or scroll moves it
        id: editModeInteraction
        visible: root.editMode
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        // A press that moves past a few pixels is a drag; one that doesn't is a click
        property bool dragging: false
        property point pressPoint
        preventStealing: true
        function raise(on) { // Over the rows and blocks after it, up to the panel
            for (let p = root.parent; p && !p.isQuickPanel; p = p.parent) p.z = on ? 10 : 0;
        }
        onPressed: (event) => {
            if (event.button === Qt.RightButton) { root.panel?.toggleSize(root.buttonData.type); return; }
            pressPoint = mapToItem(root.panel, event.x, event.y);
        }
        onPositionChanged: (event) => {
            if (!(event.buttons & Qt.LeftButton) || !root.panel) return;
            const p = mapToItem(root.panel, event.x, event.y);
            if (!dragging && Math.hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 6) {
                dragging = true;
                raise(true);
            }
            if (!dragging) return;
            root.dragX = p.x - pressPoint.x;
            root.dragY = p.y - pressPoint.y;
            root.panel.updateDrag(root.buttonData.type, this, event.x, event.y);
        }
        onReleased: (event) => {
            if (event.button !== Qt.LeftButton) return;
            if (!dragging) { root.panel?.toggleEnabled(root.buttonData.type); return; }
            const type = root.buttonData.type;
            const at = mapToItem(root.panel, event.x, event.y);
            dragging = false;
            raise(false);
            root.dragX = 0;
            root.dragY = 0;
            root.panel.endDrag(type, root.panel, at.x, at.y);
        }
        onCanceled: {
            if (!dragging) return;
            dragging = false;
            raise(false);
            root.dragX = 0;
            root.dragY = 0;
            root.panel.endDrag("", root.panel, -1e6, -1e6);
        }
        onWheel: (event) => {
            if (event.angleDelta.y !== 0) root.panel?.moveBy(root.buttonData.type, event.angleDelta.y < 0 ? 1 : -1);
            event.accepted = true;
        }
    }
}
