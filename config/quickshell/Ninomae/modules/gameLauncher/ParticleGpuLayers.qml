import QtQuick
import Ninomae.Particles

// The particles' two layers on the GPU (Ninomae.Particles, plugins/ninomae-blobs): GameParticles.qml loads this,
// and falls back to its Canvases when the plugin isn't built. The soft one (fog, glows) is drawn at a third of
// the size and scaled up, as its Canvas was
Item {
    readonly property alias soft: softLayer
    readonly property alias main: mainLayer
    ParticleLayer {
        id: softLayer
        coordScale: 3
        width: Math.ceil(parent.width / 3); height: Math.ceil(parent.height / 3)
        scale: 3; transformOrigin: Item.TopLeft
    }
    ParticleLayer {
        id: mainLayer
        anchors.fill: parent
    }
}
