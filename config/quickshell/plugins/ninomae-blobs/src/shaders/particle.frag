#version 440
// Ninomae.Particles (particlelayer.cpp): one primitive of the launcher's particles, premultiplied, as the
// Canvas in GameParticles.qml drew it. vKind.x is the kind, the rest of vKind its parameters
layout(location = 0) in vec2 vLocal;
layout(location = 1) flat in vec4 vKind;
layout(location = 2) flat in vec4 vC0;
layout(location = 3) flat in vec4 vC1;
layout(location = 4) flat in vec4 vC2;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D atlas;

// Coverage of something `dist` pixels outside its edge, for a line `width` wide (thinner than a pixel: fainter)
float cover(float dist, float width) {
    return clamp(0.5 - dist, 0.0, 1.0) * min(1.0, width);
}

// Gradient stops along t: a list of (position, alpha) for one colour, interpolated linearly
float stops4(float t, vec4 pos, vec4 a) {
    if (t <= pos.x) return a.x;
    if (t <= pos.y) return mix(a.x, a.y, (t - pos.x) / (pos.y - pos.x));
    if (t <= pos.z) return mix(a.y, a.z, (t - pos.y) / (pos.z - pos.y));
    if (t <= pos.w) return mix(a.z, a.w, (t - pos.z) / (pos.w - pos.z));
    return a.w;
}

void main() {
    int kind = int(vKind.x + 0.5);
    vec3 rgb = vC0.rgb;
    float a = 0.0;
    if (kind == 0) { // Sprite: red the shape, green a dark stroke over it, blue a white one
        vec4 s = texture(atlas, vKind.yz + vLocal / vec2(4.0, 2.0));
        float fillA = s.r, darkA = s.g, whiteA = s.b;
        vec3 c = vC0.rgb * fillA;
        float ca = fillA;
        c *= 1.0 - darkA;               ca = ca + darkA * (1.0 - ca);
        c = c * (1.0 - whiteA) + whiteA; ca = ca + whiteA * (1.0 - ca);
        fragColor = vec4(c, ca) * vC0.a;
        return;
    } else if (kind == 1) { // Radial gradient, local in radii
        float d = length(vLocal);
        int profile = int(vKind.y + 0.5);
        if (profile == 0) { // Fog bank
            a = stops4(d, vec4(0.0, 0.45, 1.0, 1.0), vec4(1.0, 0.5, 0.0, 0.0));
        } else if (profile == 1) { // Glow: whitened in the middle
            a = stops4(d, vec4(0.0, 0.15, 0.45, 1.0), vec4(0.9, 0.6, 0.18, 0.0));
            if (d < 0.15) rgb = mix((vC0.rgb + 1.0) * 0.5, vC0.rgb, d / 0.15);
        } else if (profile == 2) { // Bokeh: even, soft at the edge
            a = stops4(d, vec4(0.0, 0.55, 0.85, 1.0), vec4(0.42, 0.34, 0.14, 0.0));
        } else { // Disc
            float w = fwidth(d);
            a = clamp((1.0 - d) / max(w, 1e-5) + 0.5, 0.0, 1.0);
        }
        a *= vC0.a;
    } else if (kind == 2) { // Line with round caps; local in pixels (along, across)
        float len = vKind.y, hw = vKind.z, mid = vKind.w;
        float along = clamp(vLocal.x, 0.0, len);
        float dist = length(vec2(vLocal.x - along, vLocal.y)) - max(hw, 0.5);
        float t = len > 0.0 ? along / len : 0.0;
        vec4 c = t < mid ? mix(vC0, vC1, mid > 0.0 ? t / mid : 1.0)
                         : mix(vC1, vC2, mid < 1.0 ? (t - mid) / (1.0 - mid) : 0.0);
        rgb = c.rgb;
        a = cover(dist, hw * 2.0) * c.a;
    } else if (kind == 5) { // Polyline segment: no end cap when one follows, nothing the previous one covers
        float len = vKind.y, hw = max(vKind.z, 0.5);
        if (vKind.w > 0.5 && vLocal.x > len) discard;
        if (vC1.z > 0.5) {
            float back = length(vC1.xy);
            vec2 dir = back > 0.0 ? vC1.xy / back : vec2(-1.0, 0.0);
            float t = dot(vLocal, dir), side = abs(dir.x * vLocal.y - dir.y * vLocal.x);
            if (t >= 0.0 && t <= back && side <= hw) discard;
        }
        float along = clamp(vLocal.x, 0.0, len);
        float dist = length(vec2(vLocal.x - along, vLocal.y)) - hw;
        a = cover(dist, vKind.z * 2.0) * vC0.a;
    } else if (kind == 3) { // Ring; local in the unsquashed ring's pixels
        float r = length(vLocal);
        float w = max(fwidth(r), 1e-5);
        float dist = (abs(r - vKind.y) - max(vKind.z, 0.5 * w)) / w;
        a = cover(dist, vKind.z * 2.0 / w) * vC0.a;
    } else { // Rectangle; local in pixels from its centre
        vec2 q = abs(vLocal) - vKind.yz;
        float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
        a = clamp(0.5 - dist, 0.0, 1.0) * vC0.a;
    }
    fragColor = vec4(rgb * a, a);
}
