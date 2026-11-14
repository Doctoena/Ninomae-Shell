#pragma once
// Ninomae.Particles: the launcher's particles moving in C++ (the movement of GameParticles.qml's JavaScript, which
// stays as the Canvas fallback), drawn into two ParticleLayers every frame. GameParticles.qml keeps the presets,
// picks one and works out the colours; it hands them over with configure(), then restart().
#include "particlelayer.hpp"

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <algorithm>
#include <array>
#include <optional>
#include <vector>

class ParticleSim : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(ParticleLayer *soft MEMBER m_soft NOTIFY layersChanged)
    Q_PROPERTY(ParticleLayer *main MEMBER m_main NOTIFY layersChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int target MEMBER m_target NOTIFY targetChanged) // How many particles to keep up
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged)

public:
    explicit ParticleSim(QObject *parent = nullptr);
    // The preset (GameParticles' _presets entry), the palette ([{r, g, b}], 0..255) and the size scale
    Q_INVOKABLE void configure(const QVariantMap &preset, const QVariantList &palette, double sizeK);
    Q_INVOKABLE void setPalette(const QVariantList &palette); // Recolours the live particles too
    Q_INVOKABLE void restart(); // The old particles fade out as dots, new ones scatter in
    Q_INVOKABLE void clear();
    bool running() const { return m_timer.isActive(); }
    void setRunning(bool on);
    int fps() const { return 1000 / std::max(1, m_timer.interval()); }
    void setFps(int fps);

signals:
    void layersChanged();
    void runningChanged();
    void targetChanged();
    void fpsChanged();

private:
    struct Rgb { int r = 200, g = 200, b = 255; };
    struct Particle {
        double x = 0, y = 0, vx = 0, vy = 0, sz = 0, al = 0, mx = 0, fr = 0, dp = 0, ag = 0, ph = 0, sp = 0, rt = 0,
               gy = 0, gw = 0, tm = 1;
        int ci = 0, shape = 0;
        Rgb c;
    };
    struct Point { double x, y; };
    struct Bolt { std::vector<Point> pts, branch; double life, maxLife, w; };
    struct Spark { double x, y, vx, vy, al, life, sz; Rgb c; };
    struct Ripple { double x, y, r, maxR, life, maxLife; };
    struct Drip { double x, y, vy, d, ground; Rgb c; };
    struct Tracer { double x, y, dx, dy, spd, len, life, w; Rgb c; };
    struct Packet { double x1, y1, x2, y2, t, dur; Rgb c; };
    struct Shooting { double x, y, a, spd, life, max, len; Rgb c; };
    struct FadeDot { double x, y, sz, al, fr; Rgb c; };
    struct Range { double lo, hi; };

    // The preset, read once
    struct Config {
        int dir = 0; // 0 float, 1 rise, 2 fall, 3 side, 4 radial
        double szMin = 1, szMax = 3, spdMin = 1, spdMax = 5, fadeIn = 0.5, fadeOut = 0.04, aMin = 0.4, aMax = 1;
        double glow = 0, drift = 0, wobble = 0, gravity = 0, accel = 0, slant = 0, yMin = 0, pixelSnap = 0;
        bool noise = false, twinkle = false, blink = false, additive = false, spin = false, flip = false;
        bool anywhere = false, sizeSpeed = false, streak = false, splash = false, fast = false;
        Range spinRange { 0.1, 0.5 };
        double streakLen = 10, streakK = 0, streakMax = 120;
        double gust = 0, gustForce = 30;
        std::vector<int> shapes { 0 };
        std::array<std::optional<Range>, 13> shapeSize, shapeAlpha;
        std::array<std::optional<double>, 13> shapeGlow;
        bool hot = false; double hotChance = 0, hotGlow = 2; Rgb hotColor;
        bool bolt = false; double boltRate = 5, boltJitter = 40, flash = 0;
        bool arcs = false; double arcRate = 0.8, arcDist = 200;
        bool pops = false; double popRate = 3;
        bool tracers = false; double tracerRate = 1, tracerAngle = 0, tracerSpread = 0, tracerW = 1.5;
        bool tracerBoth = false; Range tracerSpd { 1500, 2000 }, tracerLen { 100, 160 };
        std::optional<Rgb> tracerColor;
        bool drips = false; double dripRate = 1.5;
        bool shootingStar = false; double shootingRate = 4;
        bool connections = false; double connDist = 120;
        bool packets = false; double packetRate = 0.4;
    };

    void step();
    void update(double dt);
    void spawnAt(Particle &p, bool scatter);
    bool every(double &timer, double rate, double dt);
    std::vector<Point> genBolt(double x1, double y1, double x2, double y2, int depth, double jitter);
    void spawnBolt();
    void spawnArc();
    void spawnSparkBurst(double x, double y, Rgb c);
    void spawnRipple(double x, double y, double maxR);
    void spawnTracer();
    Rgb paletteAt(int i) const;
    Rgb randomColour() const;
    double fsin(double a) const;
    double fcos(double a) const;
    double noise2d(double x, double y) const;
    void emitSoft();
    void emitMain();
    double w() const;
    double h() const;

    QPointer<ParticleLayer> m_soft, m_main;
    QTimer m_timer;
    qint64 m_lastMs = 0;
    int m_target = 0;
    bool m_ready = false;
    Config m_cfg;
    double m_sizeK = 1;
    std::vector<Rgb> m_palette;
    std::array<double, 256> m_sinL {}, m_cosL {};

    std::vector<Particle> m_parts;
    std::vector<FadeDot> m_fadeOut;
    std::vector<Bolt> m_bolts;
    std::vector<std::vector<Spark>> m_sparkBursts;
    std::vector<Ripple> m_ripples;
    std::vector<Drip> m_drips;
    std::vector<Tracer> m_tracers;
    std::vector<Packet> m_packets;
    std::vector<double> m_links; // x1, y1, x2, y2, … from the last frame's connections
    std::optional<Shooting> m_shooting;
    double m_flash = 0, m_time = 0;
    double m_boltT = 0, m_arcT = 0, m_popT = 0, m_dripT = 0, m_tracerT = 0, m_packetT = 0, m_shootT = 0;
    double m_wph = 0, m_wx = 0, m_wy = 0, m_gTimer = 0, m_gx = 0, m_gy = 0, m_gStr = 0;
    std::vector<float> m_buf;
};
