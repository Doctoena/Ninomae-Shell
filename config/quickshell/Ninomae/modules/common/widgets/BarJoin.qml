import QtQuick
import qs

/**
 * Tells the bar where a drawer is attached to it, so the bar can skip its border on that side
 * along that stretch (GlobalStates.barJoins, drawn in bar/BarContent.qml).
 * joinX/joinWidth are the drawer's own edges in screen coordinates; the gooey curve that blends
 * it into the bar flares out further than that (~16px at the bar's edge, measured 2026-11-22), so curveReach
 * is added on both sides. Too little and the border line runs over the start of each curve; too much and it stops
 * short, leaving a flat notch before each curve.
 */
QtObject {
    id: root
    property string name: "join-" + Math.floor(Math.random() * 1e9)
    property bool active: false
    property real joinX: 0
    property real joinWidth: 0
    property real curveReach: 16

    function sync() {
        if (active && joinWidth > 0)
            GlobalStates.setBarJoin(name, Math.round(joinX - curveReach), Math.round(joinWidth + curveReach * 2));
        else
            GlobalStates.clearBarJoin(name);
    }
    onActiveChanged: sync()
    onJoinXChanged: sync()
    onJoinWidthChanged: sync()
    onCurveReachChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: GlobalStates.clearBarJoin(name)
}
