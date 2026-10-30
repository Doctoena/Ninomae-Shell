import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
GroupButton {
    id: root
    // The Repeater fills index and modelData; chooser is the AndroidToggleDelegateChooser that made this tile
    required property int index
    required property var modelData
    required property var chooser
    readonly property int buttonIndex: chooser.startingIndex + index
    readonly property var buttonData: modelData
    readonly property int cellSize: modelData.size
    readonly property bool expandedSize: cellSize > 1
    required property string buttonIcon
    required property string name
    required property var mainAction
    property string statusText: toggled ? Translation.tr("Active") : Translation.tr("Inactive")
    readonly property real baseCellWidth: chooser.baseCellWidth
    readonly property real baseCellHeight: chooser.baseCellHeight
    readonly property real cellSpacing: chooser.spacing
    baseWidth: root.baseCellWidth * cellSize + cellSpacing * (cellSize - 1)
    baseHeight: root.baseCellHeight
    readonly property bool editMode: chooser.editMode
    enableImplicitWidthAnimation: !editMode && root.mouseArea.containsMouse
    enableImplicitHeightAnimation: !editMode && root.mouseArea.containsMouse
    Behavior on baseWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on baseHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    opacity: 0
    Component.onCompleted: {
        opacity = 1
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    signal openMenu()
    // Material 3 Expressive tiles: rounded rectangles that round off a little more while pressed. The
    // tile itself stays the neutral surface; being on shows in the accent (a solid squircle behind the
    // icon, the name in accent). Clicking the tile
    // toggles; tiles with a menu (Wi-Fi, Bluetooth, audio…) open it from the › on the right, or a
    // right click (GroupButton's altAction)
    padding: 8
    horizontalPadding: padding
    verticalPadding: padding
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.colors.colLayer2
    colBackgroundToggledHover: Appearance.colors.colLayer2Hover
    colBackgroundToggledActive: Appearance.colors.colLayer2Active
    buttonRadius: Appearance.rounding.normal
    buttonRadiusPressed: height / 2 // Morphs toward a pill while held
    property color colText: toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    property color colSubText: Appearance.colors.colSubtext
    readonly property bool hasMenu: expandedSize && !!altAction
    onClicked: root.mainAction()
    contentItem: RowLayout {
        id: contentItem
        spacing: 10
        anchors {
            centerIn: root.expandedSize ? undefined : parent
            fill: root.expandedSize ? parent : undefined
            leftMargin: root.horizontalPadding
            rightMargin: root.hasMenu ? 2 : root.horizontalPadding
        }
        // Icon: in a squircle on wide tiles (solid accent when on); just the glyph on small ones
        Rectangle {
            id: iconBackground
            Layout.alignment: root.expandedSize ? Qt.AlignVCenter : Qt.AlignCenter // Alone on small tiles: centred
            implicitWidth: 34
            implicitHeight: 34
            radius: root.toggled ? 11 : 17 // Squircle when on, circle when off
            color: !root.expandedSize ? "transparent"
                : root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                fill: root.toggled ? 1 : 0
                iconSize: root.expandedSize ? 20 : 24
                color: root.expandedSize && root.toggled ? Appearance.colors.colOnPrimary : root.colText
                text: root.buttonIcon
            }
        }
        // Name and state, on wide tiles
        Loader {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            visible: root.expandedSize
            active: visible
            sourceComponent: Column {
                spacing: 1
                StyledText {
                    anchors { left: parent.left; right: parent.right }
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.name
                }
                StyledText {
                    visible: root.statusText
                    anchors { left: parent.left; right: parent.right }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.colSubText
                    elide: Text.ElideRight
                    text: root.statusText
                }
            }
        }
        // Opens the tile's menu
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
                    width: 24; height: 32
                    radius: 8
                    color: ColorUtils.transparentize(root.colText, menuArea.containsPress ? 0.85 : menuArea.containsMouse ? 0.92 : 1)
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    iconSize: 18
                    color: root.colSubText
                }
            }
        }
    }
    MouseArea { // Blocking MouseArea for edit interactions
        id: editModeInteraction
        visible: root.editMode
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        function toggleEnabled() {
            const index = root.buttonIndex;
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonData.type;
            if (!toggleList.find(toggle => toggle.type === buttonType)) {
                toggleList.push({ type: buttonType, size: 1 });
            } else {
                toggleList.splice(index, 1);
            }
        }
        function toggleSize() {
            const index = root.buttonIndex;
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonData.type;
            if (!toggleList.find(toggle => toggle.type === buttonType)) return;
            toggleList[index].size = 3 - toggleList[index].size; // Alternate between 1 and 2
        }
        function movePositionBy(offset) {
            const index = root.buttonIndex;
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonData.type;
            const targetIndex = index + offset;
            if (!toggleList.find(toggle => toggle.type === buttonType)) return;
            if (targetIndex < 0 || targetIndex >= toggleList.length) return;
            const temp = toggleList[index];
            toggleList[index] = toggleList[targetIndex];
            toggleList[targetIndex] = temp;
        }
        onReleased: (event) => {
            if (event.button === Qt.LeftButton)
                toggleEnabled();
        }
        onPressed: (event) => {
            if (event.button === Qt.RightButton) toggleSize();
        }
        onPressAndHold: (event) => { // Also toggle size
            toggleSize();
        }
        onWheel: (event) => {
            const index = root.buttonIndex;
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonData.type;
            if (event.angleDelta.y < 0) { // Move to right
                movePositionBy(1);
            } else if (event.angleDelta.y > 0) { // Move to left
                movePositionBy(-1);
            }
            event.accepted = true;
        }
    }
}
