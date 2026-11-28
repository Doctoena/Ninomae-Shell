#include "particlesim.hpp"

#include <QColor>
#include <QDateTime>
#include <QRandomGenerator>

#include <algorithm>
#include <cmath>

// Line for line the JavaScript in GameParticles.qml (_update, _spawnAt, the spawners, _gpu* drawing), so a preset
// moves and looks the same either way. Shapes by number as there: 9 soft (fog), 12 bokeh, the rest drawn shapes

namespace {
constexpr int kSoft = 9, kBokeh = 12;
constexpr int kCap = 96;
constexpr double kTau = 6.2832;
double rnd() { return QRandomGenerator::global()->generateDouble(); }
int rndInt(int n) { return n > 0 ? int(rnd() * n) % n : 0; }

double num(const QVariantMap &m, const char *key, double fallback) {
    const auto it = m.find(QLatin1String(key));
    return it == m.end() || !it->isValid() ? fallback : it->toDouble();
}
bool flag(const QVariantMap &m, const char *key) {
    const auto it = m.find(QLatin1String(key));
    return it != m.end() && it->toBool();
}
} // namespace

ParticleSim::ParticleSim(QObject *parent) : QObject(parent) {
    for (int i = 0; i < 256; i++) {
        const double a = i * kTau / 256;
        m_sinL[i] = std::sin(a);
        m_cosL[i] = std::cos(a);
    }
    m_timer.setTimerType(Qt::PreciseTimer);
    m_timer.setInterval(16);
    connect(&m_timer, &QTimer::timeout, this, &ParticleSim::step);
    m_parts.reserve(kCap);
}

void ParticleSim::setFps(int fps) {
    const int interval = std::max(1, 1000 / std::max(1, fps));
    if (interval == m_timer.interval()) return;
    m_timer.setInterval(interval);
    emit fpsChanged();
}

void ParticleSim::setRunning(bool on) {
    if (on == m_timer.isActive()) return;
    if (on) { m_lastMs = 0; m_timer.start(); }
    else m_timer.stop();
    emit runningChanged();
}

void ParticleSim::configure(const QVariantMap &p, const QVariantList &palette, double sizeK) {
    Config c;
    const QString dir = p.value(QStringLiteral("dir")).toString();
    c.dir = dir == u"rise" ? 1 : dir == u"fall" ? 2 : dir == u"side" ? 3 : dir == u"radial" ? 4 : 0;
    c.szMin = num(p, "szMin", 1); c.szMax = num(p, "szMax", 3);
    c.spdMin = num(p, "spdMin", 1); c.spdMax = num(p, "spdMax", 5);
    c.fadeIn = num(p, "fadeIn", 0.5); c.fadeOut = num(p, "fadeOut", 0.04);
    c.aMin = num(p, "aMin", 0.4); c.aMax = num(p, "aMax", 1);
    c.glow = num(p, "glow", 0); c.drift = num(p, "drift", 0); c.wobble = num(p, "wobble", 0);
    c.gravity = num(p, "gravity", 0); c.accel = num(p, "accel", 0); c.slant = num(p, "slant", 0);
    c.yMin = num(p, "yMin", 0); c.pixelSnap = num(p, "pixelSnap", 0);
    c.noise = flag(p, "noise"); c.twinkle = flag(p, "twinkle"); c.blink = flag(p, "blink");
    c.additive = flag(p, "additive"); c.spin = flag(p, "spin"); c.flip = flag(p, "flip");
    c.anywhere = flag(p, "anywhere"); c.sizeSpeed = flag(p, "sizeSpeed"); c.streak = flag(p, "streak");
    c.splash = flag(p, "splash"); c.fast = flag(p, "fast");
    const auto range = [&](const char *key, Range fallback) {
        const QVariantList l = p.value(QLatin1String(key)).toList();
        return l.size() >= 2 ? Range { l[0].toDouble(), l[1].toDouble() } : fallback;
    };
    c.spinRange = range("spinRange", { 0.1, 0.5 });
    c.streakLen = num(p, "streakLen", 10); c.streakK = num(p, "streakK", 0); c.streakMax = num(p, "streakMax", 120);
    c.gust = num(p, "gust", 0); c.gustForce = num(p, "gustForce", 30);
    c.shapes.clear();
    for (const QVariant &s : p.value(QStringLiteral("shapes")).toList()) c.shapes.push_back(s.toInt());
    if (c.shapes.empty()) c.shapes.push_back(0);
    const auto perShape = [&](const char *key, auto &out, auto read) {
        const QVariantMap m = p.value(QLatin1String(key)).toMap();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const int s = it.key().toInt();
            if (s >= 0 && s < 13) out[s] = read(it.value());
        }
    };
    const auto readRange = [](const QVariant &v) { const QVariantList l = v.toList(); return Range { l.value(0).toDouble(), l.value(1).toDouble() }; };
    perShape("shapeSize", c.shapeSize, readRange);
    perShape("shapeAlpha", c.shapeAlpha, readRange);
    perShape("shapeGlow", c.shapeGlow, [](const QVariant &v) { return v.toDouble(); });
    const QVariantMap hot = p.value(QStringLiteral("hot")).toMap();
    if (!hot.isEmpty()) {
        c.hot = true;
        c.hotChance = num(hot, "chance", 0);
        c.hotGlow = num(hot, "glow", 2);
        const QColor hc(hot.value(QStringLiteral("color")).toString());
        c.hotColor = { hc.red(), hc.green(), hc.blue() };
    }
    c.bolt = flag(p, "bolt"); c.boltRate = num(p, "boltRate", 5); c.boltJitter = num(p, "boltJitter", 40);
    c.flash = num(p, "flash", 0);
    c.arcs = flag(p, "arcs"); c.arcRate = num(p, "arcRate", 0.8); c.arcDist = num(p, "arcDist", 200);
    c.pops = flag(p, "pops"); c.popRate = num(p, "popRate", 3);
    c.tracers = flag(p, "tracers"); c.tracerRate = num(p, "tracerRate", 1);
    c.tracerAngle = num(p, "tracerAngle", 0); c.tracerSpread = num(p, "tracerSpread", 0);
    c.tracerBoth = flag(p, "tracerBoth"); c.tracerW = num(p, "tracerW", 1.5);
    c.tracerSpd = range("tracerSpd", { 1500, 2000 }); c.tracerLen = range("tracerLen", { 100, 160 });
    if (p.contains(QStringLiteral("tracerColor"))) {
        const QColor tc(p.value(QStringLiteral("tracerColor")).toString());
        c.tracerColor = Rgb { tc.red(), tc.green(), tc.blue() };
    }
    c.drips = flag(p, "drips"); c.dripRate = num(p, "dripRate", 1.5);
    c.shootingStar = flag(p, "shootingStar"); c.shootingRate = num(p, "shootingRate", 4);
    c.connections = flag(p, "connections"); c.connDist = num(p, "connDist", 120);
    c.packets = flag(p, "packets"); c.packetRate = num(p, "packetRate", 0.4);
    c.flicker = num(p, "flicker", 0);
    m_cfg = c;
    m_sizeK = sizeK;
    setPalette(palette);
}

void ParticleSim::setPalette(const QVariantList &palette) {
    m_palette.clear();
    for (const QVariant &v : palette) {
        const QVariantMap m = v.toMap();
        m_palette.push_back({ m.value(QStringLiteral("r")).toInt(), m.value(QStringLiteral("g")).toInt(), m.value(QStringLiteral("b")).toInt() });
    }
    if (m_palette.empty()) return;
    for (Particle &p : m_parts)
        if (p.ci != 255) p.c = m_palette[size_t(p.ci) % m_palette.size()];
}

ParticleSim::Rgb ParticleSim::paletteAt(int i) const {
    return m_palette.empty() ? Rgb {} : m_palette[size_t(i) % m_palette.size()];
}
ParticleSim::Rgb ParticleSim::randomColour() const {
    return m_palette.empty() ? Rgb { 255, 255, 255 } : m_palette[size_t(rndInt(int(m_palette.size())))];
}
double ParticleSim::w() const { return m_main ? m_main->width() : 0; }
double ParticleSim::h() const { return m_main ? m_main->height() : 0; }

double ParticleSim::fsin(double a) const {
    return m_sinL[size_t(std::lround(std::fmod(std::fmod(a, kTau) + kTau, kTau) * 40.7437)) % 256];
}
double ParticleSim::fcos(double a) const {
    return m_cosL[size_t(std::lround(std::fmod(std::fmod(a, kTau) + kTau, kTau) * 40.7437)) % 256];
}
double ParticleSim::noise2d(double x, double y) const {
    return fsin(x * 0.7 + y * 0.3) * 0.3 + fsin(x * 0.3 - y * 0.7 + 1.5) * 0.3
         + fsin(x * 1.1 + y * 0.9 + 3.0) * 0.15 + fsin(x * 0.5 - y * 1.3 + 5.0) * 0.1;
}

void ParticleSim::setPointer(double x, double y, bool inside) {
    m_ptrX = x; m_ptrY = y; m_ptrInside = inside;
}

void ParticleSim::clear() {
    m_bolts.clear(); m_sparkBursts.clear(); m_ripples.clear(); m_drips.clear(); m_tracers.clear();
    m_packets.clear(); m_links.clear(); m_shooting.reset();
    m_flash = 0;
    m_light = 1; m_stutters = 0; m_flickerT = 0; m_stutterT = 0;
    m_boltT = m_arcT = m_popT = m_dripT = m_tracerT = m_packetT = m_shootT = 0;
}

void ParticleSim::restart() {
    // The old particles fade out as plain dots
    m_fadeOut.clear();
    if (m_ready) {
        for (const Particle &p : m_parts) {
            if (p.shape == kSoft || p.sz > 20) continue;
            m_fadeOut.push_back({ p.x, p.y, std::min(p.sz, 6.0), p.al * p.tm, 1.5, p.c });
        }
        if (m_fadeOut.size() > 40) m_fadeOut.erase(m_fadeOut.begin(), m_fadeOut.end() - 40);
    }
    m_parts.clear();
    clear();
    m_time = 0; m_lastMs = 0;
    m_wph = m_wx = m_wy = 0; m_gTimer = 0; m_gStr = 0;
    m_ready = false;
    if (w() > 0 && h() > 0) {
        for (int i = 0; i < std::min(m_target, kCap); i++) {
            m_parts.emplace_back();
            spawnAt(m_parts.back(), true);
        }
    }
    m_ready = true;
}

void ParticleSim::spawnAt(Particle &p, bool scatter) {
    const Config &cfg = m_cfg;
    const double W = w(), H = h();
    if (W <= 0 || H <= 0) return;
    const int shape = cfg.shapes[size_t(rndInt(int(cfg.shapes.size())))];
    p.shape = shape;
    const double depth = 0.3 + rnd() * 0.7;
    p.dp = depth;
    const Range sr = cfg.shapeSize[size_t(shape)].value_or(Range { cfg.szMin, cfg.szMax });
    const double sizeT = rnd();
    p.sz = (sr.lo + sizeT * (sr.hi - sr.lo)) * (0.5 + depth * 0.5) * m_sizeK;
    if (cfg.pixelSnap > 0) p.sz = std::max(1.0, std::round(p.sz / cfg.pixelSnap)) * cfg.pixelSnap;
    double spd = (cfg.spdMin + (cfg.sizeSpeed ? sizeT : rnd()) * (cfg.spdMax - cfg.spdMin)) * (0.4 + depth * 0.6);
    if (shape == kSoft) spd *= 0.6;
    p.ph = rnd() * kTau;
    p.ag = scatter && !cfg.anywhere ? rnd() * 2 : 0;
    const Range ar = cfg.shapeAlpha[size_t(shape)].value_or(Range { cfg.aMin, cfg.aMax });
    p.mx = ar.lo + rnd() * (ar.hi - ar.lo);
    p.al = scatter && !(cfg.anywhere && m_ready) ? p.mx * (0.3 + rnd() * 0.7) : 0;
    p.fr = cfg.fadeOut * (1 + rnd());
    p.rt = rnd() * kTau;
    p.tm = 1;
    p.gw = cfg.shapeGlow[size_t(shape)].value_or(cfg.glow);
    if (cfg.hot && rnd() < cfg.hotChance) {
        p.ci = 255; p.c = cfg.hotColor; p.gw = cfg.hotGlow;
    } else {
        p.ci = m_palette.empty() ? 0 : rndInt(int(m_palette.size()));
        p.c = paletteAt(p.ci);
    }
    p.sp = cfg.spin ? (cfg.spinRange.lo + rnd() * (cfg.spinRange.hi - cfg.spinRange.lo)) * (rnd() < 0.5 ? -1 : 1) : 0;
    const double pad = p.sz * 2 + 4;
    if (cfg.anywhere) scatter = true;
    switch (cfg.dir) {
    case 1: // rise
        p.x = rnd() * W; p.y = scatter ? rnd() * H : H + pad;
        p.vx = 0; p.vy = -spd;
        break;
    case 2: { // fall
        const double slant = cfg.slant;
        p.x = rnd() * (W + H * slant) - H * slant;
        p.y = scatter ? rnd() * H : -pad - rnd() * 40;
        p.vx = spd * slant; p.vy = spd;
        break;
    }
    case 3: // side
        p.x = scatter ? rnd() * W : -pad;
        p.y = H * (cfg.yMin + rnd() * (1 - cfg.yMin));
        p.vx = spd; p.vy = 0;
        break;
    case 4: { // radial
        const double a = rnd() * kTau, r0 = 8 + rnd() * std::min(W, H) * (scatter ? 0.5 : 0.08);
        p.x = W / 2 + std::cos(a) * r0; p.y = H / 2 + std::sin(a) * r0;
        const double sp2 = scatter ? spd * (1 + r0 / 40) : spd;
        p.vx = std::cos(a) * sp2; p.vy = std::sin(a) * sp2;
        break;
    }
    default: // float
        p.x = rnd() * W; p.y = rnd() * H; p.vx = 0; p.vy = 0;
    }
    p.gy = H * (0.62 + depth * 0.36);
}

bool ParticleSim::every(double &timer, double rate, double dt) {
    timer += dt;
    if (timer >= rate) { timer = -rate * (rnd() * 0.6 - 0.3); return true; }
    return false;
}

std::vector<ParticleSim::Point> ParticleSim::genBolt(double x1, double y1, double x2, double y2, int depth, double jitter) {
    if (depth <= 0) return { { x1, y1 }, { x2, y2 } };
    const double mx = (x1 + x2) / 2 + (rnd() - 0.5) * jitter, my = (y1 + y2) / 2 + (rnd() - 0.5) * jitter;
    std::vector<Point> left = genBolt(x1, y1, mx, my, depth - 1, jitter * 0.55);
    const std::vector<Point> right = genBolt(mx, my, x2, y2, depth - 1, jitter * 0.55);
    left.insert(left.end(), right.begin() + 1, right.end());
    return left;
}

void ParticleSim::spawnBolt() {
    const double W = w(), H = h(), jitter = m_cfg.boltJitter;
    const double x1 = W * 0.15 + rnd() * W * 0.7, y1 = -10;
    const double x2 = x1 + (rnd() - 0.5) * W * 0.3, y2 = H * 0.6 + rnd() * H * 0.35;
    Bolt b { genBolt(x1, y1, x2, y2, 5, jitter), {}, 0.45, 0.45, 2.2 };
    if (rnd() < 0.7 && b.pts.size() > 4) {
        const Point bp = b.pts[2 + size_t(rndInt(int(b.pts.size()) - 4))];
        b.branch = genBolt(bp.x, bp.y, bp.x + (rnd() - 0.5) * jitter * 3, bp.y + H * (0.1 + rnd() * 0.2), 3, jitter * 0.5);
    }
    m_bolts.push_back(std::move(b));
    if (m_cfg.flash > 0) m_flash = m_cfg.flash;
}

void ParticleSim::spawnArc() {
    const int n = int(m_parts.size());
    if (n < 2) return;
    const int i = rndInt(n);
    const double maxD = m_cfg.arcDist;
    int best = -1; double bestD = maxD * maxD;
    for (int j = 0; j < n; j++) {
        if (j == i || m_parts[size_t(j)].al < 0.2) continue;
        const double dx = m_parts[size_t(j)].x - m_parts[size_t(i)].x, dy = m_parts[size_t(j)].y - m_parts[size_t(i)].y;
        const double d = dx * dx + dy * dy;
        if (d < bestD && d > 400) { bestD = d; best = j; }
    }
    if (best < 0) return;
    Particle &a = m_parts[size_t(i)], &b = m_parts[size_t(best)];
    m_bolts.push_back({ genBolt(a.x, a.y, b.x, b.y, 4, std::sqrt(bestD) * 0.35), {}, 0.22, 0.22, 1.3 });
    if (m_bolts.size() > 6) m_bolts.erase(m_bolts.begin(), m_bolts.end() - 6);
    a.tm = 1; b.tm = 1;
}

void ParticleSim::spawnSparkBurst(double x, double y, Rgb c) {
    const int count = 5 + rndInt(5);
    std::vector<Spark> sparks;
    for (int i = 0; i < count; i++) {
        const double a = rnd() * kTau, spd = 25 + rnd() * 55;
        sparks.push_back({ x, y, std::cos(a) * spd, std::sin(a) * spd - 15, 0.8 + rnd() * 0.2, 0.3 + rnd() * 0.35, 0.8 + rnd() * 1.4, c });
    }
    m_sparkBursts.push_back(std::move(sparks));
    if (m_sparkBursts.size() > 6) m_sparkBursts.erase(m_sparkBursts.begin(), m_sparkBursts.end() - 6);
}

void ParticleSim::spawnRipple(double x, double y, double maxR) {
    m_ripples.push_back({ x, y, 0, maxR, 0.45, 0.45 });
    if (m_ripples.size() > 24) m_ripples.erase(m_ripples.begin(), m_ripples.end() - 24);
}

void ParticleSim::spawnTracer() {
    const Config &cfg = m_cfg;
    const double W = w(), H = h();
    double a = cfg.tracerAngle + (rnd() - 0.5) * 2 * cfg.tracerSpread;
    if (cfg.tracerBoth && rnd() < 0.5) a += M_PI;
    const double dx = std::cos(a), dy = std::sin(a);
    const double px = W * (0.1 + rnd() * 0.8), py = H * (0.15 + rnd() * 0.7);
    const double back = std::abs(dx) > 0.01 ? (dx > 0 ? px : W - px) / std::abs(dx) : H;
    const double spd = cfg.tracerSpd.lo + rnd() * (cfg.tracerSpd.hi - cfg.tracerSpd.lo);
    const double len = cfg.tracerLen.lo + rnd() * (cfg.tracerLen.hi - cfg.tracerLen.lo);
    const Rgb c = cfg.tracerColor.value_or(randomColour());
    const double travel = back + W + len;
    m_tracers.push_back({ px - dx * (back + 20), py - dy * (back + 20), dx, dy, spd, len, travel / spd,
                          cfg.tracerW * (0.7 + rnd() * 0.6), c });
    if (m_tracers.size() > 6) m_tracers.erase(m_tracers.begin());
}

void ParticleSim::step() {
    if (!m_ready || !m_main || !m_soft || w() <= 0) return;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (m_lastMs == 0) m_lastMs = now;
    const double dt = std::min((now - m_lastMs) / 1000.0, 0.1);
    m_lastMs = now;
    m_time += dt;
    update(dt);
    emitSoft();
    emitMain();
}

void ParticleSim::update(double dt) {
    const Config &cfg = m_cfg;
    const double W = w(), H = h(), t = m_time;

    // Wind and gusts
    m_wph += dt * 0.3;
    m_wx = fsin(m_wph * 0.7) * 6;
    m_wy = fcos(m_wph * 0.5) * 2;
    if (cfg.gust > 0) {
        m_gTimer += dt;
        if (m_gTimer >= cfg.gust) {
            m_gTimer -= cfg.gust * (0.7 + rnd() * 0.6);
            const double ga = rnd() * kTau;
            m_gx = std::cos(ga) * cfg.gustForce;
            m_gy = std::sin(ga) * cfg.gustForce * 0.3;
            m_gStr = 1;
        }
        if (m_gStr > 0) { m_gStr -= dt * 1.2; if (m_gStr < 0) m_gStr = 0; }
    }
    const double gs = m_gStr * m_gStr * (3 - 2 * m_gStr);
    const double gx = m_gx * gs, gy = m_gy * gs;

    // Timed effects
    if (cfg.shootingStar && every(m_shootT, cfg.shootingRate, dt) && !m_shooting) {
        const double life = 0.6 + rnd() * 0.4;
        m_shooting = Shooting { rnd() * W * 0.7, rnd() * H * 0.35, 0.25 + rnd() * 0.4, 380 + rnd() * 220, life, life,
                                40 + rnd() * 50, m_palette.empty() ? Rgb { 255, 255, 255 } : m_palette[0] };
    }
    if (m_shooting) {
        m_shooting->life -= dt;
        m_shooting->x += std::cos(m_shooting->a) * m_shooting->spd * dt;
        m_shooting->y += std::sin(m_shooting->a) * m_shooting->spd * dt;
        if (m_shooting->life <= 0) m_shooting.reset();
    }
    if (cfg.bolt && every(m_boltT, cfg.boltRate, dt) && m_bolts.size() < 2) spawnBolt();
    if (cfg.arcs && every(m_arcT, cfg.arcRate, dt)) spawnArc();
    if (cfg.pops && !m_parts.empty() && every(m_popT, cfg.popRate, dt)) {
        const Particle &p = m_parts[size_t(rndInt(int(m_parts.size())))];
        if (p.al > 0.3) spawnSparkBurst(p.x, p.y, p.c);
    }
    if (cfg.tracers && every(m_tracerT, cfg.tracerRate, dt)) {
        spawnTracer();
        if (cfg.tracerColor && rnd() < 0.5) { // Fire comes in short bursts
            const Tracer last = m_tracers.back();
            spawnTracer();
            Tracer &nt = m_tracers.back();
            nt.x = last.x - last.dx * 60; nt.y = last.y - last.dy * 60 + (rnd() - 0.5) * 20;
            nt.dx = last.dx; nt.dy = last.dy; nt.life = last.life + 60 / nt.spd;
        }
    }
    if (cfg.drips && every(m_dripT, cfg.dripRate, dt) && m_drips.size() < 4) {
        const double d = 0.4 + rnd() * 0.6;
        m_drips.push_back({ W * (0.1 + rnd() * 0.8), -6, 0, d, H * (0.65 + d * 0.33), randomColour() });
    }
    if (cfg.packets && m_links.size() >= 4 && every(m_packetT, cfg.packetRate, dt) && m_packets.size() < 8) {
        const size_t li = size_t(rndInt(int(m_links.size() / 4))) * 4;
        const bool fwd = rnd() < 0.5;
        m_packets.push_back({ fwd ? m_links[li] : m_links[li + 2], fwd ? m_links[li + 1] : m_links[li + 3],
                              fwd ? m_links[li + 2] : m_links[li], fwd ? m_links[li + 3] : m_links[li + 1],
                              0, 0.5 + rnd() * 0.5, randomColour() });
    }

    // Advance the effects
    std::erase_if(m_bolts, [dt](Bolt &b) { b.life -= dt; return b.life <= 0; });
    std::erase_if(m_sparkBursts, [dt](std::vector<Spark> &sb) {
        bool alive = false;
        for (Spark &s : sb) {
            s.x += s.vx * dt; s.y += s.vy * dt; s.vy += 40 * dt; s.vx *= (1 - dt * 1.5);
            s.life -= dt; s.al = std::max(0.0, s.life * 2.5);
            if (s.life > 0) alive = true;
        }
        return !alive;
    });
    std::erase_if(m_ripples, [dt](Ripple &r) { r.life -= dt; r.r += r.maxR * dt * 2.6; return r.life <= 0; });
    std::vector<Drip> landed;
    std::erase_if(m_drips, [&](Drip &d) {
        d.vy += 700 * dt; d.y += d.vy * dt;
        if (d.y >= d.ground) { landed.push_back(d); return true; }
        return false;
    });
    for (const Drip &d : landed) { spawnRipple(d.x, d.ground, 10 + d.d * 14); spawnSparkBurst(d.x, d.ground, d.c); }
    std::erase_if(m_tracers, [dt](Tracer &tr) { tr.x += tr.dx * tr.spd * dt; tr.y += tr.dy * tr.spd * dt; tr.life -= dt; return tr.life <= 0; });
    std::erase_if(m_packets, [dt](Packet &p) { p.t += dt / p.dur; return p.t >= 1; });
    if (m_flash > 0) { m_flash -= dt * 0.9; if (m_flash < 0) m_flash = 0; }

    // A failing light: now and then two or three quick dips, then steady again
    if (cfg.flicker > 0) {
        if (m_stutters == 0 && every(m_flickerT, cfg.flicker, dt)) { m_stutters = 2 + rndInt(3); m_stutterT = 0; }
        if (m_stutters > 0) {
            m_stutterT -= dt;
            if (m_stutterT <= 0) {
                const bool dim = m_light > 0.6;
                m_light = dim ? 0.15 + rnd() * 0.25 : 1;
                m_stutterT = dim ? 0.04 + rnd() * 0.08 : 0.05 + rnd() * 0.15;
                if (!dim) m_stutters--;
            }
        }
    }
    // Parallax: ease toward the pointer's offset from the middle (back to rest when it leaves)
    {
        const double tx = m_parallax && m_ptrInside && W > 0 ? (m_ptrX / W - 0.5) * 2 : 0;
        const double ty = m_parallax && m_ptrInside && H > 0 ? (m_ptrY / H - 0.5) * 2 : 0;
        const double k = std::min(1.0, dt * 3);
        m_parX += (tx - m_parX) * k; m_parY += (ty - m_parY) * k;
    }

    // Particles
    const double fadeInRate = cfg.fadeIn, drift = cfg.drift;
    std::vector<Particle> &kept = m_kept;
    kept.clear();
    for (Particle &p : m_parts) {
        p.ag += dt;
        const double d = p.dp, wsc = d * dt;
        if (cfg.dir == 1 || cfg.dir == 2) {
            p.x += p.vx * dt + m_wx * wsc + gx * wsc;
            p.y += p.vy * dt + m_wy * wsc * 0.3 + gy * wsc;
            if (cfg.noise && drift > 0) {
                p.x += noise2d(p.x * 0.01, t * 0.3 + p.ph) * drift * dt;
                p.y += noise2d(p.y * 0.01 + 100, t * 0.35 + p.ph * 1.3) * drift * dt * 0.4;
            } else if (drift > 0) {
                p.x += fsin(p.ph + t * 0.5) * drift * dt;
            }
            if (cfg.wobble > 0) p.x += fcos(p.ph + t * (2 + d * 2)) * cfg.wobble * dt;
            if (cfg.gravity != 0) p.vy += cfg.gravity * dt;
        } else if (cfg.dir == 3) {
            p.x += p.vx * dt + gx * wsc;
            p.y += m_wy * wsc * 0.3 + gy * wsc;
            if (cfg.noise && drift > 0) p.y += noise2d(p.y * 0.01, t * 0.4 + p.ph) * drift * dt;
            else if (drift > 0) p.y += fsin(p.ph + t * 0.4) * drift * dt;
        } else if (cfg.dir == 4) {
            const double f = 1 + cfg.accel * dt;
            p.vx *= f; p.vy *= f;
            p.x += p.vx * dt; p.y += p.vy * dt;
        } else {
            if (cfg.noise && drift > 0) {
                p.x += noise2d(p.x * 0.008 + p.ph, t * 0.25) * drift * dt + m_wx * wsc * 0.3 + gx * wsc;
                p.y += noise2d(p.y * 0.008 + p.ph * 1.3 + 50, t * 0.2) * drift * dt * 0.6 + m_wy * wsc * 0.3 + gy * wsc;
            } else {
                p.x += fsin(p.ph + t * 0.3) * drift * dt + m_wx * wsc * 0.3 + gx * wsc;
                p.y += fcos(p.ph * 1.3 + t * 0.2) * drift * dt * 0.6 + m_wy * wsc * 0.3 + gy * wsc;
            }
        }
        if (p.sp != 0) p.rt += p.sp * dt * (1 + gs * 2);

        double tMul = 1;
        if (cfg.twinkle) {
            tMul = 0.35 + 0.65 * std::abs(fsin(p.ph * 2 + t * (1.2 + d)));
            if (cfg.pixelSnap > 0) tMul = std::round(tMul * 3) / 3 + 0.05;
        }
        if (cfg.blink) {
            const double b = 0.5 + 0.5 * fsin(p.ph * 0.5 + t * (0.6 + d * 0.5));
            tMul = 0.12 + 0.88 * b * b;
        }
        if (cfg.arcs && p.tm > tMul) tMul = std::max(tMul, p.tm - dt * 3);
        p.tm = tMul;

        if (p.al < p.mx && p.ag < 4) {
            p.al += fadeInRate * dt * p.mx;
            if (p.al > p.mx) p.al = p.mx;
        } else {
            p.al -= p.fr * dt;
        }

        if (cfg.splash && p.y >= p.gy) {
            if (p.al > 0.15 && m_ripples.size() < 24 && rnd() < 0.6) spawnRipple(p.x, p.gy, 4 + d * 10);
            continue;
        }
        const double m = p.sz * 1.5 + 60;
        if (p.al > 0.005 && p.x > -m - 200 && p.x < W + m && p.y > -m - 60 && p.y < H + m) kept.push_back(p);
    }
    m_parts.swap(kept);

    const int target = std::min(m_target, kCap);
    const int perFrame = cfg.fast ? 8 : 3;
    for (int spawned = 0; int(m_parts.size()) < target && spawned < perFrame; spawned++) {
        m_parts.emplace_back();
        spawnAt(m_parts.back(), false);
    }
    if (int(m_parts.size()) > target) m_parts.resize(size_t(target));

    std::erase_if(m_fadeOut, [dt](FadeDot &f) { f.al -= f.fr * dt; return f.al <= 0.01; });
}

// ── Drawing: primitives for the layers, 24 floats each (particlelayer.hpp) ──
namespace {
struct Emitter {
    std::vector<float> &b;
    float *slot(int kind, int blend) {
        b.resize(b.size() + 24, 0.f);
        float *o = b.data() + b.size() - 24;
        o[0] = float(kind); o[1] = float(blend);
        return o;
    }
    static void col(float *o, double r, double g, double bl, double a) {
        o[0] = float(r / 255); o[1] = float(g / 255); o[2] = float(bl / 255); o[3] = float(a);
    }
    void sprite(int blend, int cell, double x, double y, double sz, double rot, double fx, int r, int g, int bl, double a) {
        float *o = slot(0, blend);
        o[2] = float(x); o[3] = float(y); o[4] = float(sz); o[5] = float(rot); o[6] = float(fx); o[7] = float(cell);
        col(o + 8, r, g, bl, a);
    }
    void radial(int blend, int profile, double x, double y, double rx, double ry, int r, int g, int bl, double a) {
        float *o = slot(1, blend);
        o[2] = float(x); o[3] = float(y); o[4] = float(rx); o[5] = float(ry); o[6] = float(profile);
        col(o + 8, r, g, bl, a);
    }
    void line(int blend, double x1, double y1, double x2, double y2, double width, int r, int g, int bl, double a) {
        float *o = slot(2, blend);
        o[2] = float(x1); o[3] = float(y1); o[4] = float(x2); o[5] = float(y2); o[6] = float(width); o[7] = 0.5f;
        col(o + 8, r, g, bl, a); col(o + 12, r, g, bl, a); col(o + 16, r, g, bl, a);
    }
    struct C { double r, g, b, a; };
    void gradLine(int blend, double x1, double y1, double x2, double y2, double width, double mid, C c0, C c1, C c2) {
        float *o = slot(2, blend);
        o[2] = float(x1); o[3] = float(y1); o[4] = float(x2); o[5] = float(y2); o[6] = float(width); o[7] = float(mid);
        col(o + 8, c0.r, c0.g, c0.b, c0.a); col(o + 12, c1.r, c1.g, c1.b, c1.a); col(o + 16, c2.r, c2.g, c2.b, c2.a);
    }
    void ring(int blend, double x, double y, double rad, double ys, double width, int r, int g, int bl, double a) {
        float *o = slot(3, blend);
        o[2] = float(x); o[3] = float(y); o[4] = float(rad); o[5] = float(ys); o[6] = float(width);
        col(o + 8, r, g, bl, a);
    }
    void rect(int blend, double cx, double cy, double width, double height, double rot, int r, int g, int bl, double a) {
        float *o = slot(4, blend);
        o[2] = float(cx); o[3] = float(cy); o[4] = float(width); o[5] = float(height); o[6] = float(rot);
        col(o + 8, r, g, bl, a);
    }
    template<typename P>
    void polyline(int blend, const std::vector<P> &pts, double width, int r, int g, int bl, double a) {
        for (size_t i = 1; i < pts.size(); i++) {
            float *o = slot(5, blend);
            const P &p = pts[i - 1], &q = pts[i], &prev = pts[i > 1 ? i - 2 : 0];
            o[2] = float(p.x); o[3] = float(p.y); o[4] = float(q.x); o[5] = float(q.y); o[6] = float(width);
            o[7] = i < pts.size() - 1 ? 1.f : 0.f;
            col(o + 8, r, g, bl, a);
            o[12] = float(prev.x); o[13] = float(prev.y); o[14] = i > 1 ? 1.f : 0.f;
        }
    }
};
// Shapes drawn from the layer's atlas, by its cells; diamond, petal and leaf flip
int cellOf(int shape) {
    switch (shape) { case 1: return 0; case 2: return 1; case 3: return 2; case 4: return 3; case 5: return 4;
                     case 6: return 5; case 8: return 6; case 11: return 7; default: return -1; }
}
QByteArray bytes(const std::vector<float> &v) {
    return QByteArray(reinterpret_cast<const char *>(v.data()), qsizetype(v.size() * sizeof(float)));
}
} // namespace

// Parallax: nearer particles shift further with the pointer (up to 16 px)
double ParticleSim::shiftX(const Particle &p) const { return -m_parX * 16 * (p.dp - 0.3) / 0.7; }
double ParticleSim::shiftY(const Particle &p) const { return -m_parY * 9 * (p.dp - 0.3) / 0.7; }
// Depth: the furthest particles of a shape (not streaks, fog or bokeh) drawn out of focus
bool ParticleSim::blurred(const Particle &p) const {
    return m_depth && p.dp < 0.6 && !m_cfg.streak && p.shape != kSoft && p.shape != kBokeh && p.shape != 10;
}

void ParticleSim::emitSoft() {
    m_buf.clear();
    Emitter e { m_buf };
    const double snap = m_cfg.pixelSnap;
    for (const Particle &p : m_parts) { // Fog banks and dust clouds, squashed into banks
        if (p.shape != kSoft) continue;
        const double a = p.al * p.tm * m_light;
        if (a < 0.005) continue;
        e.radial(0, 0, p.x + shiftX(p), p.y + shiftY(p), p.sz * 1.5, p.sz * 0.75, p.c.r, p.c.g, p.c.b, std::min(1.0, a * 2.5));
    }
    const int glowBlend = m_cfg.additive ? 1 : 2;
    for (const Particle &p : m_parts) { // Glow halos under the particles
        if (p.gw <= 0 || p.shape == kSoft) continue;
        const double a = p.al * p.tm * (0.5 + p.dp * 0.5) * m_light * (blurred(p) ? 0.5 : 1);
        if (a < 0.1) continue;
        double x = p.x + shiftX(p), y = p.y + shiftY(p);
        if (snap > 0) { x = std::round(x / snap) * snap; y = std::round(y / snap) * snap; }
        const double r = p.sz * p.gw + 2;
        e.radial(glowBlend, 1, x, y, r, r, p.c.r, p.c.g, p.c.b, std::min(1.0, a * 0.95));
    }
    m_soft->submit(bytes(m_buf));
}

void ParticleSim::emitMain() {
    m_buf.clear();
    Emitter e { m_buf };
    const Config &cfg = m_cfg;
    const int base = cfg.additive ? 1 : 0;
    const double W = w(), H = h();
    const Rgb p0 = m_palette.empty() ? Rgb {} : m_palette[0];

    for (const FadeDot &f : m_fadeOut) e.radial(base, 3, f.x, f.y, f.sz, f.sz, f.c.r, f.c.g, f.c.b, f.al);

    for (const Bolt &b : m_bolts) { // Lightning and arcs
        const double ba = b.life / b.maxLife, flick = ba * (0.7 + 0.3 * rnd());
        const Rgb rc = m_palette.empty() ? Rgb { 200, 200, 255 } : p0;
        e.polyline(1, b.pts, b.w * 3.5, rc.r, rc.g, rc.b, flick * 0.35);
        e.polyline(1, b.pts, b.w * ba + 0.4, 255, 255, 255, flick);
        if (b.branch.size() > 1) e.polyline(1, b.branch, b.w * 0.5, 255, 255, 255, flick * 0.55);
    }
    if (!m_ripples.empty()) { // Splashes, flattened onto a ground plane
        const Rgb rc = m_palette.empty() ? Rgb { 190, 205, 225 } : p0;
        for (const Ripple &r : m_ripples) {
            const double life = r.life / r.maxLife;
            e.ring(base, r.x, r.y, std::max(0.5, r.r), 0.28, 0.6 + life * 0.8, rc.r, rc.g, rc.b, life * 0.5);
        }
    }
    for (const Drip &d : m_drips)
        e.line(base, d.x, d.y, d.x, d.y - std::min(22.0, d.vy * 0.03), 1.6 * d.d, d.c.r, d.c.g, d.c.b, 0.75);
    if (m_shooting) {
        const Shooting &ss = *m_shooting;
        const double life = ss.life / ss.max;
        const double fade = std::min(1.0, life * 3) * std::min(1.0, (1 - life) * 6);
        const double tx = ss.x - std::cos(ss.a) * ss.len, ty = ss.y - std::sin(ss.a) * ss.len;
        e.gradLine(base, ss.x, ss.y, tx, ty, 1.8, 0.25, { 255, 255, 255, fade }, { double(ss.c.r), double(ss.c.g), double(ss.c.b), 0.6 * fade },
                   { double(ss.c.r), double(ss.c.g), double(ss.c.b), 0 });
        e.radial(base, 1, ss.x, ss.y, 10, 10, ss.c.r, ss.c.g, ss.c.b, fade);
    }
    for (const Tracer &tr : m_tracers)
        e.gradLine(1, tr.x, tr.y, tr.x - tr.dx * tr.len, tr.y - tr.dy * tr.len, tr.w, 0.15, { 255, 255, 255, 0.95 * 0.9 },
                   { double(tr.c.r), double(tr.c.g), double(tr.c.b), 0.8 * 0.9 }, { double(tr.c.r), double(tr.c.g), double(tr.c.b), 0 });

    if (cfg.connections) { // Close pairs through a spatial grid, each neighbouring pair once, at most 100
        const double cD = cfg.connDist, cDSq = cD * cD;
        const int cols = int(std::ceil(W / cD)) + 1, rows = int(std::ceil(H / cD)) + 1;
        std::vector<std::vector<int>> &grid = m_grid;
        if (grid.size() < size_t(cols * rows)) grid.resize(size_t(cols * rows));
        for (auto &cell : grid) cell.clear();
        for (int i = 0; i < int(m_parts.size()); i++) {
            const Particle &p = m_parts[size_t(i)];
            if (p.al < 0.05) continue;
            const int gc = int(std::floor(p.x / cD)), gr = int(std::floor(p.y / cD));
            if (gc >= 0 && gc < cols && gr >= 0 && gr < rows) grid[size_t(gr * cols + gc)].push_back(i);
        }
        m_links.clear();
        int drawn = 0;
        for (int cy = 0; cy < rows && drawn < 100; cy++) {
            for (int cx = 0; cx < cols && drawn < 100; cx++) {
                const auto &cell = grid[size_t(cy * cols + cx)];
                if (cell.empty()) continue;
                for (int ni = 0; ni < 5 && drawn < 100; ni++) {
                    int nx = cx, ny = cy;
                    if (ni == 1) nx++; else if (ni == 2) ny++; else if (ni == 3) { nx++; ny++; } else if (ni == 4) { nx--; ny++; }
                    if (nx < 0 || nx >= cols || ny >= rows) continue;
                    const auto &nb = ni == 0 ? cell : grid[size_t(ny * cols + nx)];
                    for (size_t ai = 0; ai < cell.size() && drawn < 100; ai++) {
                        const Particle &p1 = m_parts[size_t(cell[ai])];
                        for (size_t bi = ni == 0 ? ai + 1 : 0; bi < nb.size() && drawn < 100; bi++) {
                            const Particle &p2 = m_parts[size_t(nb[bi])];
                            const double dx = p1.x - p2.x, dy = p1.y - p2.y, dSq = dx * dx + dy * dy;
                            if (dSq >= cDSq) continue;
                            const double a = (1 - std::sqrt(dSq) / cD) * std::min(p1.al, p2.al) * 0.75;
                            if (a < 0.01) continue;
                            e.line(base, p1.x, p1.y, p2.x, p2.y, 1, p1.c.r, p1.c.g, p1.c.b, a);
                            if (a > 0.08) m_links.insert(m_links.end(), { p1.x, p1.y, p2.x, p2.y });
                            drawn++;
                        }
                    }
                }
            }
        }
    }
    for (const Packet &p : m_packets) { // Data packets along the links
        const double ee = p.t < 0.5 ? 2 * p.t * p.t : 1 - 2 * (1 - p.t) * (1 - p.t);
        const double x = p.x1 + (p.x2 - p.x1) * ee, y = p.y1 + (p.y2 - p.y1) * ee;
        const double e0 = std::max(0.0, ee - 0.18);
        const double x0 = p.x1 + (p.x2 - p.x1) * e0, y0 = p.y1 + (p.y2 - p.y1) * e0;
        const double a = std::sin(p.t * M_PI);
        e.line(1, x0, y0, x, y, 1.6, p.c.r, p.c.g, p.c.b, a * 0.8);
        e.radial(1, 3, x, y, 1.6, 1.6, 255, 255, 255, a);
        e.radial(1, 1, x, y, 9, 9, p.c.r, p.c.g, p.c.b, a * 0.8);
    }

    // The particles
    const double streakLen = cfg.streakLen * m_sizeK;
    const double windAng = (m_wx + m_gx * m_gStr) * 0.004;
    const double snap = cfg.pixelSnap;
    for (const Particle &p : m_parts) {
        if (p.shape == kSoft) continue;
        const double a = p.al * p.tm * (0.5 + p.dp * 0.5) * m_light;
        if (a < 0.01) continue;
        double x = p.x + shiftX(p), y = p.y + shiftY(p);
        if (snap > 0) { x = std::round(x / snap) * snap; y = std::round(y / snap) * snap; }
        const int r = p.c.r, g = p.c.g, b = p.c.b;
        if (p.shape == kBokeh) { e.radial(base, 2, x, y, p.sz, p.sz, r, g, b, a); continue; }
        if (blurred(p)) { // Out of focus: a soft disc, bigger and fainter the further it is
            const double rr = p.sz * (1.6 + (0.6 - p.dp) * 3);
            e.radial(base, 2, x, y, rr, rr, r, g, b, std::min(1.0, a * 1.6));
            continue;
        }
        if (cfg.streak) {
            const double spd = std::sqrt(p.vx * p.vx + p.vy * p.vy);
            if (spd < 0.01) continue;
            const double len = cfg.streakK > 0 ? std::min(cfg.streakMax, spd * cfg.streakK + 1) : streakLen * (0.4 + p.dp * 0.6);
            double ang = std::atan2(p.vy, p.vx);
            if (cfg.streakK == 0) ang -= windAng * p.dp;
            e.line(base, x, y, x - std::cos(ang) * len, y - std::sin(ang) * len,
                   std::max(0.8, p.sz * (cfg.streakK > 0 ? 0.9 : 0.7)), r, g, b, a);
            continue;
        }
        const double rot = snap > 0 ? 0 : p.rt;
        const int cell = cellOf(p.shape);
        if (cell >= 0) {
            const double fx = (p.shape == 1 || p.shape == 2 || p.shape == 11) && cfg.flip
                ? fcos(p.rt * 1.3 + p.ph) * 0.85 + (p.rt >= 0 ? 0.15 : -0.15) : 1;
            e.sprite(base, cell, x, y, p.sz, p.shape == 8 ? 0 : rot, fx, r, g, b, a);
        } else if (p.shape == 7) { // Cross: two bars
            e.rect(base, x, y, p.sz * 2, p.sz * 0.5, rot, r, g, b, a);
            e.rect(base, x, y, p.sz * 0.5, p.sz * 2, rot, r, g, b, a);
        } else if (p.shape == 10) { // Pixel
            e.rect(base, x, y, p.sz, p.sz, 0, r, g, b, a);
        } else {
            e.radial(base, 3, x, y, p.sz, p.sz, r, g, b, a);
        }
    }
    for (const auto &sb : m_sparkBursts) // Pops
        for (const Spark &s : sb)
            if (s.al >= 0.01) e.line(1, s.x, s.y, s.x - s.vx * 0.04, s.y - s.vy * 0.04, s.sz, s.c.r, s.c.g, s.c.b, s.al);
    if (m_flash > 0.003) e.rect(0, W / 2, H / 2, W, H, 0, 223, 232, 255, m_flash); // Lightning flash

    m_main->submit(bytes(m_buf));
}
