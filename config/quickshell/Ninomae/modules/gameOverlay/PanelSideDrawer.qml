import qs.modules.common
import QtQuick

// A menu that grows out of the in-game overlay's side panel, on its right edge, on the shell's blob and the
// drawers' curves, so it joins the panel as the bar's drawers join the bar (as the game page's side menus,
// GameDetailsPanel's SideDrawer). Give it the panel's height (anchored to its side), the opener's centre
// (anchorY, in its coordinates) and the menu's size (paneW, paneH): the menu is centred on the opener and kept
// inside the panel's height
Item {
    id: sd
    property bool open: false
    property real anchorY: 0
    property real paneW: 300
    property real paneH: 0
    property color fillColor: Appearance.colors.colLayer0
    default property alias content: pane.data
    property real offset: open ? 0 : 1 // 0 = out, 1 = tucked in
    Behavior on offset {
        NumberAnimation {
            duration: sd.open ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: sd.open ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
        }
    }
    readonly property real _top: -(paneW + 60) * offset
    readonly property real _y: Math.min(0, _top)
    readonly property real _len: paneW + Math.max(0, _top) // Overshoot stretches
    readonly property real _shown: Math.max(0, _y + _len)
    readonly property real menuTop: Math.max(16, Math.min(anchorY - paneH / 2, height - paneH - 16))
    width: paneW + 40
    clip: true
    visible: offset < 1
    Item { // The blob, rotated -90° so its "bar" edge is the panel's right edge
        id: stage
        readonly property real along: sd.height
        readonly property real out: sd.width
        width: along; height: out
        x: (out - along) / 2; y: (along - out) / 2
        rotation: -90
        clip: true
        Loader {
            anchors.fill: parent
            active: sd.visible
            source: Qt.resolvedUrl("../overview/BlobDrawerBackground.qml")
            onLoaded: {
                item.barBottom = 0;
                item.barHeight = 40;
                item.barRadius = 0;
                item.fillColor = Qt.binding(() => sd.fillColor);
                item.fillOpacity = 1.0; // As the panel
                // Rotated: the stage's x runs up the screen
                item.drawerX = Qt.binding(() => stage.along - sd.menuTop - sd.paneH);
                item.drawerY = Qt.binding(() => sd._y);
                item.drawerWidth = Qt.binding(() => sd.paneH);
                item.drawerHeight = Qt.binding(() => sd._len);
                item.drawerRadius = Qt.binding(() => Math.min(Appearance.rounding.large, sd._shown / 2));
            }
        }
    }
    Item {
        id: pane
        x: sd._shown - width // Slides with the drawer
        y: sd.menuTop
        width: sd.paneW
        height: sd.paneH
        opacity: 1 - sd.offset
        MouseArea { anchors.fill: parent } // Clicks between its rows stay on it
    }
}
