import QtQuick
import Ninomae.Particles

// The particles on the GPU (Ninomae.Particles, plugins/ninomae-blobs): ParticleSim moves them and draws into the two
// layers every frame. GameParticles.qml loads this, configures sim, and falls back to its Canvases and its own
// JavaScript when the plugin isn't built. The soft layer (fog, glows) is drawn at a third of the size and scaled up
Item {
    id: layers
    readonly property alias sim: particleSim
    property bool running: false
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
    ParticleSim {
        id: particleSim
        soft: softLayer
        main: mainLayer
        running: layers.running
    }
}
