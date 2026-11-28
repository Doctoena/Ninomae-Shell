import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
/**
 * A quick toggle, a capsule on the sidebar's controls well (AndroidQuickPanel, S2b): on, the bar's lit capsule with a
 * light along its top; off, a faint glass outline; a shade when pointed at. Wide: the icon on a round, solid accent
 * with a soft glow when on, the name over the state (the state in the accent when on), and a › that opens its page in
 * the control centre. Small: the icon alone, in the accent and filled when on. Clicking toggles; a right click also
 * opens the page (GroupButton's altAction), the › is the visible way. In edit mode: click turns it on or off,
 * right-click changes its size, drag moves it.
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

    bounce: false
    baseWidth: chooser.cellWidth
    baseHeight: chooser.cellHeight
    implicitWidth: baseWidth
    implicitHeight: baseHeight
    padding: 0
    // The capsule's own fill is drawn below; these are the shade over it when pointed at or pressed
    colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 1)
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.94)
    colBackgroundActive: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.88)
    colBackgroundToggled: colBackground
    colBackgroundToggledHover: colBackgroundHover
    colBackgroundToggledActive: colBackgroundActive
    property color colText: toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
    readonly property bool hasMenu: expandedSize && !!altAction

    opacity: appeared ? (leaving ? 0.45 : 1) : 0
    property bool appeared: false
    Component.onCompleted: appeared = true
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    onClicked: root.mainAction()

    background: Item {
        // Small ones fill a fixed cell: the capsule sits 3 px in from each side, so neighbours are 6 px apart
        anchors { fill: parent; leftMargin: root.expandedSize ? 0 : 3; rightMargin: root.expandedSize ? 0 : 3 }
        anchors.topMargin: root.expandedSize ? 0 : (parent.height - 38) / 2
        anchors.bottomMargin: anchors.topMargin
        LitCapsule {
            anchors.fill: parent
            opacity: root.toggled ? 1 : 0
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        }
        Rectangle { // Off: a faint glass outline; on and off: the shade when pointed at
            anchors.fill: parent
            radius: height / 2
            color: root.toggled ? root.color : Qt.tint(Qt.rgba(1, 1, 1, 0.03), root.color)
            border { width: 1; color: root.toggled ? "transparent" : Qt.rgba(1, 1, 1, 0.1) }
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
        EdgeLight {
            visible: root.toggled && root.expandedSize
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 24; rightMargin: 24 }
            strength: 0.35
        }
    }

    contentItem: RowLayout {
        id: contentItem
        spacing: 10
        anchors {
            fill: parent
            leftMargin: root.expandedSize ? 6 : 9
            rightMargin: root.hasMenu ? 4 : 9
        }
        Item { visible: !root.expandedSize; Layout.fillWidth: true } // A small one: the icon centred
        // Wide: the icon on a round, solid accent with a soft glow when on, a light tint when off
        Rectangle {
            visible: root.expandedSize
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 38
            implicitHeight: 38
            radius: width / 2
            color: root.toggled ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.92)
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            Rectangle { // The glow
                z: -1
                anchors.centerIn: parent
                width: parent.width + 6
                height: width
                radius: width / 2
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                opacity: root.toggled ? 1 : 0
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                iconSize: 19
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                text: root.buttonIcon
            }
        }
        // Small: the icon alone, in the accent and filled when on
        MaterialSymbol {
            visible: !root.expandedSize
            Layout.alignment: Qt.AlignVCenter
            fill: root.toggled ? 1 : 0
            iconSize: 18
            color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
            text: root.buttonIcon
        }
        ColumnLayout { // A wide one: its name over its state
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            visible: root.expandedSize
            spacing: -2
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer3
                elide: Text.ElideRight
                text: root.name
            }
            StyledText {
                visible: root.statusText !== ""
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colSubtextGlass
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
                    radius: 12
                    color: ColorUtils.transparentize(root.colText, menuArea.containsPress ? 0.85 : menuArea.containsMouse ? 0.92 : 1)
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    iconSize: 16
                    color: Appearance.colors.colSubtextGlass
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
