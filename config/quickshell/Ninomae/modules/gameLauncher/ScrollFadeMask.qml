import QtQuick
import QtQuick.Effects

/**
 * Fades a scrolling list's own edges to nothing, for `layer.effect`, so its items slide out of view on glass.
 * SheetEdgeFade lays the sheet's colour over the edge instead, which on see-through glass shows as a darker
 * band. Each edge fades only while there's more to scroll to on that side (topActive / bottomActive).
 */
MultiEffect {
    id: root
    property real topFade: 20
    property real bottomFade: 28
    property bool topActive: false
    property bool bottomActive: false
    // 0..1: how far each edge has faded in, eased like SheetEdgeFade's opacity
    property real _top: topActive ? 1 : 0
    property real _bottom: bottomActive ? 1 : 0
    Behavior on _top { NumberAnimation { duration: 150 } }
    Behavior on _bottom { NumberAnimation { duration: 150 } }

    maskEnabled: true
    // Soft: the mask's alpha ramps the content's (a threshold of 0 let any alpha through in full, no fade)
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
    maskSource: mask

    Item {
        id: mask
        width: root.width
        height: root.height
        visible: false
        layer.enabled: true
        layer.smooth: true
        Rectangle {
            width: parent.width; height: root.topFade
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - root._top) }
                GradientStop { position: 1; color: "black" }
            }
        }
        Rectangle {
            y: root.topFade
            width: parent.width; height: Math.max(0, parent.height - root.topFade - root.bottomFade)
            color: "black"
        }
        Rectangle {
            y: parent.height - root.bottomFade
            width: parent.width; height: root.bottomFade
            gradient: Gradient {
                GradientStop { position: 0; color: "black" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1 - root._bottom) }
            }
        }
    }
}
