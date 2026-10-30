// Gooey drawer background using Ninomae.Blobs (derived from caelestia-dots/shell's blob renderer,
// built by config/quickshell/plugins/ninomae-blobs/build.sh). SearchWidget loads this
// through a Loader and falls back to its plain Shape background if the module is missing.
import QtQuick
import Ninomae.Blobs
import qs.modules.common

Item {
    id: root

    // Geometry in this item's coordinates; the parent clips everything above y = barBottom
    property real barBottom      // y of the bar's bottom edge
    property real barHeight
    property real barRadius
    property real drawerX
    property real drawerY
    property real drawerWidth
    property real drawerHeight
    property real drawerRadius
    readonly property alias deformMatrix: drawerBlob.deformMatrix
    // The drawer blob reaches this far up under the bar (clipped), so the jelly
    // squash/stretch, which scales about its centre, can't pull it off the bar
    readonly property real topOverlap: 60
    // Defaults match the bar; large drawers over busy content (game launcher) can go more solid
    property color fillColor: Appearance.colors.colLayer0
    property real fillOpacity: 0.92
    // Stand-in bar extent. Defaults to a very wide bar (the real bar spans the screen); a drawer
    // hanging off a small shape (e.g. a pill) sets these to match that shape exactly
    property real smoothing: 20 // How far the gooey joins reach (caelestia's border smoothing)
    // Drawers near a screen edge pass where their window sits, so the stand-in bar stops where the
    // real (floating, round-ended) bar stops. Otherwise its edge shows past the bar's rounded corner
    // as a line running to the screen edge. screenWidth 0 = don't clamp (centred drawers).
    property real windowScreenX: 0
    property real screenWidth: 0
    readonly property real barGap: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
    property real barX: screenWidth > 0 ? Math.max(-400, barGap - windowScreenX) : -400
    property real barWidth: screenWidth > 0 ? Math.min(width + 400, screenWidth - barGap - windowScreenX) - barX : width + 800

    // No layer: rendering the blob into a texture every frame of a drawer's slide hung the Intel GPU
    // (i915 "GPU HANG" / "preemption time out" in the shell's render thread, as the sidebar opened).
    // Opacity applies to each shape on its own then, which is fine: the shader draws every pixel once
    // (by the shape that owns it), so where the drawer and the bar stand-in overlap nothing doubles up
    opacity: fillOpacity

    BlobGroup {
        id: group
        color: root.fillColor
        smoothing: root.smoothing
    }

    // Stand-in for the bar. Only the gooey bulge below its bottom edge is visible,
    // because the parent clips the rest; the real bar is drawn by Bar.qml.
    BlobRect {
        group: group
        x: root.barX
        y: root.barBottom - root.barHeight
        implicitWidth: root.barWidth
        implicitHeight: root.barHeight
        radius: root.barRadius
        deformScale: 0
    }

    BlobRect {
        id: drawerBlob
        group: group
        x: root.drawerX
        y: root.drawerY - root.topOverlap
        implicitWidth: root.drawerWidth
        implicitHeight: root.drawerHeight + root.topOverlap
        radius: root.drawerRadius
        deformScale: 0.1 / 10000 // caelestia's launcher deformAmount
    }
}
