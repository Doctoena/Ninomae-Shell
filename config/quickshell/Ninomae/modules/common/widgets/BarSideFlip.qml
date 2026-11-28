import QtQuick
import qs

/**
 * With the bar along the bottom (GlobalStates.barAtBottom), a bar drawer rises out of it instead of dropping:
 * put this on the drawer's stage to flip it (y = 0 stays the bar's edge, so the drawer code doesn't change),
 * and on the content inside to turn that back upright. Does nothing with the bar at the top.
 */
Scale {
    property real size // Height of the item it's on
    yScale: GlobalStates.barAtBottom ? -1 : 1
    origin.y: size / 2
}
