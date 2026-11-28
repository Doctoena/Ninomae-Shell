#pragma once
// Ninomae.Particles: draws the game launcher's particles (modules/gameLauncher/GameParticles.qml) on the GPU.
// The particles still move in JavaScript; each frame it hands over a list of primitives (submit), drawn here into
// the item's own texture with the Canvas's blend modes (source-over, lighter, screen), so it looks the same as the
// Canvas did without rasterising and uploading the whole banner every frame. Each primitive is 24 floats:
//   [0] kind  [1] blend (0 over, 1 lighter, 2 screen)  [2..7] geometry  [8..11] colour 0  [12..15] colour 1
//   [16..19] colour 2  [20..23] unused. Colours are straight RGBA, 0..1; alpha already includes globalAlpha.
//   0 sprite  x, y, size, rotation, x scale (flip), atlas cell                         colour 0
//   1 radial  x, y, radius x, radius y, profile (0 fog, 1 glow, 2 bokeh, 3 disc)       colour 0
//   2 line    x1, y1, x2, y2, width, where colour 1 sits (0..1)                        colours 0, 1, 2
//   3 ring    x, y, radius, y scale, line width                                         colour 0
//   4 rect    centre x, centre y, width, height, rotation                               colour 0
//   5 polyline segment: as a line, [7] 1 when another segment follows (no end cap), colour 1 = the previous
//             point (x, y) and 1 when there is one: a stroke drawn once, its joints not lit twice   colour 0
// coordScale: the coordinates are this many times the item's size (the soft layer is drawn small and scaled up).
#include <QQuickRhiItem>
#include <QByteArray>
#include <QtQml/qqmlregistration.h>

class ParticleLayer : public QQuickRhiItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal coordScale READ coordScale WRITE setCoordScale NOTIFY coordScaleChanged)

public:
    explicit ParticleLayer(QQuickItem *parent = nullptr);
    Q_INVOKABLE void submit(const QByteArray &primitives);
    qreal coordScale() const { return m_coordScale; }
    void setCoordScale(qreal s);

    QByteArray frame;
    quint64 serial = 0;

signals:
    void coordScaleChanged();

protected:
    QQuickRhiItemRenderer *createRenderer() override;

private:
    qreal m_coordScale = 1;
};
