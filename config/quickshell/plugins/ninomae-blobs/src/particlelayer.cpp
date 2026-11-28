#include "particlelayer.hpp"

#include <QFile>
#include <QImage>
#include <QPainter>
#include <QPainterPath>
#include <QtMath>
#include <rhi/qrhi.h>
#include <rhi/qshader.h>

#include <array>
#include <cmath>
#include <memory>
#include <vector>

namespace {

constexpr int kFloats = 24;  // Per primitive, as GameParticles.qml writes them
constexpr int kCell = 128;   // Atlas cell, in pixels
constexpr int kCols = 4, kRows = 2;
constexpr float kSpan = 1.25f; // A sprite cell holds ±1.25 × the particle's size

// A vertex: where it is, where that is in the primitive's own frame, then what the fragment shader needs
struct Vertex {
    float x, y;       // Content coordinates
    float lx, ly;     // The primitive's own frame (per kind, see particle.frag)
    float kind, p0, p1, p2;
    float c0[4], c1[4], c2[4];
};

QShader loadShader(const QString &name) {
    QFile f(name);
    return f.open(QIODevice::ReadOnly) ? QShader::fromSerialized(f.readAll()) : QShader();
}

// The shapes GameParticles.qml draws with paths (its _drawShape), drawn once at kCell px. Red is the shape in the
// particle's colour, green a dark stroke over it (a leaf's midrib), blue a white one (a bubble's highlight); each
// channel holds what that part adds in alpha, so the shader composites them as the Canvas did
QImage buildAtlas() {
    QImage atlas(kCell * kCols, kCell * kRows, QImage::Format_RGBA8888);
    atlas.fill(Qt::transparent);
    const float k = kCell / (2 * kSpan); // Pixels per unit of size
    auto channel = [&](int cell, auto draw) {
        QImage ch(kCell, kCell, QImage::Format_ARGB32_Premultiplied);
        std::array<QImage, 3> parts;
        for (int c = 0; c < 3; c++) {
            ch.fill(Qt::transparent);
            QPainter p(&ch);
            p.setRenderHint(QPainter::Antialiasing);
            p.translate(kCell / 2.0, kCell / 2.0);
            p.scale(k, k);
            draw(p, c);
            p.end();
            parts[c] = ch.copy();
        }
        const int ox = (cell % kCols) * kCell, oy = (cell / kCols) * kCell;
        for (int y = 0; y < kCell; y++) {
            uchar *row = atlas.scanLine(oy + y) + ox * 4;
            for (int x = 0; x < kCell; x++) {
                for (int c = 0; c < 3; c++) row[x * 4 + c] = qAlpha(parts[c].pixel(x, y));
                row[x * 4 + 3] = 255;
            }
        }
    };
    auto fillPath = [](QPainter &p, const QPainterPath &path, qreal alpha = 1) {
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(255, 255, 255, int(alpha * 255)));
        p.drawPath(path);
    };
    auto polygon = [](int n, auto radius, double start) {
        QPainterPath path;
        for (int j = 0; j < n; j++) {
            const double a = j * 2 * M_PI / n + start;
            const QPointF pt(std::cos(a) * radius(j), std::sin(a) * radius(j));
            j == 0 ? path.moveTo(pt) : path.lineTo(pt);
        }
        path.closeSubpath();
        return path;
    };
    // 0 diamond
    channel(0, [&](QPainter &p, int c) {
        if (c) return;
        QPainterPath path;
        path.moveTo(0, -1); path.lineTo(0.6, 0); path.lineTo(0, 1); path.lineTo(-0.6, 0); path.closeSubpath();
        fillPath(p, path);
    });
    // 1 petal, its tip notched
    channel(1, [&](QPainter &p, int c) {
        if (c) return;
        QPainterPath path;
        path.moveTo(0, 0.55);
        path.cubicTo(0.75, 0.2, 0.55, -0.45, 0.14, -0.55);
        path.lineTo(0, -0.4); path.lineTo(-0.14, -0.55);
        path.cubicTo(-0.55, -0.45, -0.75, 0.2, 0, 0.55);
        path.closeSubpath();
        fillPath(p, path);
    });
    // 2 hex
    channel(2, [&](QPainter &p, int c) { if (!c) fillPath(p, polygon(6, [](int) { return 1.0; }, -M_PI / 6)); });
    // 3 five-point star
    channel(3, [&](QPainter &p, int c) { if (!c) fillPath(p, polygon(10, [](int j) { return j % 2 ? 0.4 : 1.0; }, -M_PI / 2)); });
    // 4 snowflake: six arms with two branches each
    channel(4, [&](QPainter &p, int c) {
        if (c) return;
        p.setPen(QPen(Qt::white, 0.12, Qt::SolidLine, Qt::RoundCap));
        for (int j = 0; j < 6; j++) {
            const double a = j * M_PI / 3, ca = std::cos(a), sa = std::sin(a);
            p.drawLine(QPointF(0, 0), QPointF(ca, sa));
            const QPointF b(ca * 0.55, sa * 0.55);
            p.drawLine(b, b + QPointF(std::cos(a + 0.6), std::sin(a + 0.6)) * 0.32);
            p.drawLine(b, b + QPointF(std::cos(a - 0.6), std::sin(a - 0.6)) * 0.32);
        }
    });
    // 5 four-point sparkle
    channel(5, [&](QPainter &p, int c) { if (!c) fillPath(p, polygon(8, [](int j) { return j % 2 ? 0.22 : 1.0; }, -M_PI / 2)); });
    // 6 bubble: a faint fill, a thin rim, a white highlight
    channel(6, [&](QPainter &p, int c) {
        if (c == 0) {
            p.setPen(Qt::NoPen);
            p.setBrush(QColor(255, 255, 255, int(0.12 * 255)));
            p.drawEllipse(QPointF(0, 0), 1.0, 1.0);
            p.setBrush(Qt::NoBrush);
            p.setPen(QPen(Qt::white, 0.13));
            p.drawEllipse(QPointF(0, 0), 1.0, 1.0);
        } else if (c == 2) {
            p.setPen(Qt::NoPen);
            p.setBrush(QColor(255, 255, 255, int(0.85 * 255)));
            p.drawEllipse(QPointF(-0.35, -0.35), 0.2, 0.2);
        }
    });
    // 7 leaf, with a dark midrib over it
    channel(7, [&](QPainter &p, int c) {
        if (c == 0) {
            QPainterPath path;
            path.moveTo(0, -1);
            path.quadTo(0.75, -0.2, 0, 0.8);
            path.quadTo(-0.75, -0.2, 0, -1);
            path.closeSubpath();
            fillPath(p, path);
        } else if (c == 1) {
            p.setPen(QPen(QColor(255, 255, 255, int(0.6 * 0.45 * 255)), 0.07, Qt::SolidLine, Qt::RoundCap));
            p.drawLine(QPointF(0, -0.85), QPointF(0, 1.05));
        }
    });
    return atlas;
}

class ParticleRenderer : public QQuickRhiItemRenderer {
public:
    void initialize(QRhiCommandBuffer *cb) override {
        if (m_pipelines[0]) return;
        QRhi *r = rhi();
        m_ubuf.reset(r->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, 64));
        m_ubuf->create();
        m_vbuf.reset(r->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::VertexBuffer, sizeof(Vertex) * 6 * 256));
        m_vbuf->create();

        const QImage atlas = buildAtlas();
        m_atlas.reset(r->newTexture(QRhiTexture::RGBA8, atlas.size(), 1,
                                    QRhiTexture::MipMapped | QRhiTexture::UsedWithGenerateMips));
        m_atlas->create();
        m_sampler.reset(r->newSampler(QRhiSampler::Linear, QRhiSampler::Linear, QRhiSampler::Linear,
                                      QRhiSampler::ClampToEdge, QRhiSampler::ClampToEdge));
        m_sampler->create();
        QRhiResourceUpdateBatch *u = r->nextResourceUpdateBatch();
        u->uploadTexture(m_atlas.get(), atlas);
        u->generateMips(m_atlas.get());
        cb->resourceUpdate(u);

        m_srb.reset(r->newShaderResourceBindings());
        m_srb->setBindings({
            QRhiShaderResourceBinding::uniformBuffer(0, QRhiShaderResourceBinding::VertexStage, m_ubuf.get()),
            QRhiShaderResourceBinding::sampledTexture(1, QRhiShaderResourceBinding::FragmentStage, m_atlas.get(), m_sampler.get()),
        });
        m_srb->create();

        const QShader vs = loadShader(QStringLiteral(":/shaders/particle.vert.qsb"));
        const QShader fs = loadShader(QStringLiteral(":/shaders/particle.frag.qsb"));
        QRhiVertexInputLayout layout;
        layout.setBindings({ { sizeof(Vertex) } });
        layout.setAttributes({
            { 0, 0, QRhiVertexInputAttribute::Float4, 0 },
            { 0, 1, QRhiVertexInputAttribute::Float4, 4 * sizeof(float) },
            { 0, 2, QRhiVertexInputAttribute::Float4, 8 * sizeof(float) },
            { 0, 3, QRhiVertexInputAttribute::Float4, 12 * sizeof(float) },
            { 0, 4, QRhiVertexInputAttribute::Float4, 16 * sizeof(float) },
        });
        // Premultiplied: source-over, lighter (add), screen (s + d - s·d)
        const QRhiGraphicsPipeline::BlendFactor dst[3] = {
            QRhiGraphicsPipeline::OneMinusSrcAlpha, QRhiGraphicsPipeline::One, QRhiGraphicsPipeline::OneMinusSrcColor };
        const QRhiGraphicsPipeline::BlendFactor dstAlpha[3] = {
            QRhiGraphicsPipeline::OneMinusSrcAlpha, QRhiGraphicsPipeline::One, QRhiGraphicsPipeline::OneMinusSrcAlpha };
        for (int i = 0; i < 3; i++) {
            auto *ps = r->newGraphicsPipeline();
            QRhiGraphicsPipeline::TargetBlend blend;
            blend.enable = true;
            blend.srcColor = QRhiGraphicsPipeline::One;
            blend.dstColor = dst[i];
            blend.srcAlpha = QRhiGraphicsPipeline::One;
            blend.dstAlpha = dstAlpha[i];
            ps->setTargetBlends({ blend });
            ps->setShaderStages({ { QRhiShaderStage::Vertex, vs }, { QRhiShaderStage::Fragment, fs } });
            ps->setVertexInputLayout(layout);
            ps->setShaderResourceBindings(m_srb.get());
            ps->setRenderPassDescriptor(renderTarget()->renderPassDescriptor());
            ps->create();
            m_pipelines[i].reset(ps);
        }
    }

    void synchronize(QQuickRhiItem *item) override {
        auto *layer = static_cast<ParticleLayer *>(item);
        if (layer->serial != m_serial) {
            m_serial = layer->serial;
            m_frame = layer->frame;
            m_dirty = true;
        }
        m_width = float(layer->width() * layer->coordScale());
        m_height = float(layer->height() * layer->coordScale());
    }

    void render(QRhiCommandBuffer *cb) override {
        QRhi *r = rhi();
        QRhiResourceUpdateBatch *u = r->nextResourceUpdateBatch();
        QMatrix4x4 mvp = r->clipSpaceCorrMatrix();
        mvp.ortho(0, m_width, m_height, 0, -1, 1);
        u->updateDynamicBuffer(m_ubuf.get(), 0, 64, mvp.constData());

        if (m_dirty) {
            m_dirty = false;
            buildVertices();
            const quint32 bytes = quint32(m_vertices.size() * sizeof(Vertex));
            if (bytes > m_vbuf->size()) {
                m_vbuf.reset(r->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::VertexBuffer, bytes * 2));
                m_vbuf->create();
            }
            if (bytes) u->updateDynamicBuffer(m_vbuf.get(), 0, bytes, m_vertices.data());
        }

        cb->beginPass(renderTarget(), Qt::transparent, { 1.0f, 0 }, u);
        const QSize px = renderTarget()->pixelSize();
        int first = 0;
        for (const auto &run : m_runs) { // Consecutive primitives with the same blend, in the order they came
            cb->setGraphicsPipeline(m_pipelines[run.blend].get());
            cb->setViewport({ 0, 0, float(px.width()), float(px.height()) });
            cb->setShaderResources();
            const QRhiCommandBuffer::VertexInput input(m_vbuf.get(), 0);
            cb->setVertexInput(0, 1, &input);
            cb->draw(quint32(run.count), 1, quint32(first));
            first += run.count;
        }
        cb->endPass();
    }

private:
    struct Run { int blend; int count; };

    void quad(const Vertex &tmpl, const std::array<QPointF, 4> &pos, const std::array<QPointF, 4> &local) {
        const int order[6] = { 0, 1, 2, 0, 2, 3 };
        for (int i : order) {
            Vertex v = tmpl;
            v.x = float(pos[i].x()); v.y = float(pos[i].y());
            v.lx = float(local[i].x()); v.ly = float(local[i].y());
            m_vertices.push_back(v);
        }
    }

    // A rectangle around (cx, cy) along the axes (ux, uy), ±hx and ±hy, and the same corners in the primitive's frame
    void box(const Vertex &tmpl, QPointF c, QPointF ux, QPointF uy, double hx, double hy,
             QPointF l0, QPointF l1) {
        quad(tmpl,
             { c - ux * hx - uy * hy, c + ux * hx - uy * hy, c + ux * hx + uy * hy, c - ux * hx + uy * hy },
             { l0, QPointF(l1.x(), l0.y()), l1, QPointF(l0.x(), l1.y()) });
    }

    void buildVertices() {
        m_vertices.clear();
        m_runs.clear();
        const auto *f = reinterpret_cast<const float *>(m_frame.constData());
        const qsizetype n = m_frame.size() / qsizetype(kFloats * sizeof(float));
        for (qsizetype i = 0; i < n; i++, f += kFloats) {
            const int kind = int(f[0]), blend = qBound(0, int(f[1]), 2);
            const size_t before = m_vertices.size();
            Vertex t {};
            t.kind = float(kind);
            std::copy(f + 8, f + 12, t.c0);
            std::copy(f + 12, f + 16, t.c1);
            std::copy(f + 16, f + 20, t.c2);
            if (kind == 0) { // Sprite: x, y, size, rotation, x scale, cell
                const double s = f[4] * kSpan, rot = f[5], fx = f[6];
                const int cell = int(f[7]);
                t.p0 = float(cell % kCols) / kCols; t.p1 = float(cell / kCols) / kRows;
                const QPointF ux(std::cos(rot), std::sin(rot)), uy(-std::sin(rot), std::cos(rot));
                box(t, QPointF(f[2], f[3]), ux * fx, uy, s, s, QPointF(0, 0), QPointF(1, 1));
            } else if (kind == 1) { // Radial: x, y, radius x, radius y, profile; local in radii, with a pixel spare
                const double rx = std::max(0.01f, f[4]), ry = std::max(0.01f, f[5]);
                t.p0 = f[6];
                const double ex = (rx + 1) / rx, ey = (ry + 1) / ry;
                box(t, QPointF(f[2], f[3]), QPointF(1, 0), QPointF(0, 1), rx + 1, ry + 1,
                    QPointF(-ex, -ey), QPointF(ex, ey));
            } else if (kind == 2) { // Line: x1, y1, x2, y2, width, where colour 1 sits; local in pixels along it
                const QPointF a(f[2], f[3]), b(f[4], f[5]);
                const double len = std::hypot(b.x() - a.x(), b.y() - a.y());
                const QPointF u = len > 1e-4 ? (b - a) / len : QPointF(1, 0), nrm(-u.y(), u.x());
                const double hw = f[6] / 2, e = std::max(hw, 0.5) + 1;
                t.p0 = float(len); t.p1 = float(hw); t.p2 = f[7];
                box(t, (a + b) / 2, u, nrm, len / 2 + e, e, QPointF(-e, -e), QPointF(len + e, e));
            } else if (kind == 5) { // Polyline segment: like a line, plus where the previous point is, in its frame
                const QPointF a(f[2], f[3]), b(f[4], f[5]);
                const double len = std::hypot(b.x() - a.x(), b.y() - a.y());
                const QPointF u = len > 1e-4 ? (b - a) / len : QPointF(1, 0), nrm(-u.y(), u.x());
                const double hw = f[6] / 2, e = std::max(hw, 0.5) + 1;
                t.p0 = float(len); t.p1 = float(hw); t.p2 = f[7];
                const QPointF back = QPointF(f[12], f[13]) - a;
                t.c1[0] = float(back.x() * u.x() + back.y() * u.y());
                t.c1[1] = float(back.x() * nrm.x() + back.y() * nrm.y());
                t.c1[2] = f[14];
                box(t, (a + b) / 2, u, nrm, len / 2 + e, e, QPointF(-e, -e), QPointF(len + e, e));
            } else if (kind == 3) { // Ring: x, y, radius, y scale, line width; local in the unsquashed ring
                const double rad = f[4], ys = std::max(0.01f, f[5]), hw = f[6] / 2, e = rad + hw + 1.5 / ys;
                t.p0 = float(rad); t.p1 = float(hw);
                box(t, QPointF(f[2], f[3]), QPointF(1, 0), QPointF(0, ys), e, e, QPointF(-e, -e), QPointF(e, e));
            } else if (kind == 4) { // Rect: centre, width, height, rotation; local in pixels from the centre
                const double hx = f[4] / 2, hy = f[5] / 2, rot = f[6];
                t.p0 = float(hx); t.p1 = float(hy);
                const QPointF ux(std::cos(rot), std::sin(rot)), uy(-std::sin(rot), std::cos(rot));
                box(t, QPointF(f[2], f[3]), ux, uy, hx + 1, hy + 1, QPointF(-hx - 1, -hy - 1), QPointF(hx + 1, hy + 1));
            }
            const int added = int(m_vertices.size() - before);
            if (!added) continue;
            if (!m_runs.empty() && m_runs.back().blend == blend) m_runs.back().count += added;
            else m_runs.push_back({ blend, added });
        }
    }

    std::unique_ptr<QRhiBuffer> m_ubuf, m_vbuf;
    std::unique_ptr<QRhiTexture> m_atlas;
    std::unique_ptr<QRhiSampler> m_sampler;
    std::unique_ptr<QRhiShaderResourceBindings> m_srb;
    std::unique_ptr<QRhiGraphicsPipeline> m_pipelines[3];
    QByteArray m_frame;
    quint64 m_serial = 0;
    bool m_dirty = false;
    float m_width = 1, m_height = 1;
    std::vector<Vertex> m_vertices;
    std::vector<Run> m_runs;
};

} // namespace

ParticleLayer::ParticleLayer(QQuickItem *parent) : QQuickRhiItem(parent) {
    setAlphaBlending(true); // Composited over the art, with what it draws see-through around it
}

void ParticleLayer::submit(const QByteArray &primitives) {
    frame = primitives;
    serial++;
    update();
}

void ParticleLayer::setCoordScale(qreal s) {
    if (qFuzzyCompare(s, m_coordScale)) return;
    m_coordScale = s;
    emit coordScaleChanged();
    update();
}

QQuickRhiItemRenderer *ParticleLayer::createRenderer() { return new ParticleRenderer(); }
