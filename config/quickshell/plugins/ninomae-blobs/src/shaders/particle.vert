#version 440
// Ninomae.Particles (particlelayer.cpp): places a primitive's corners, passes the rest on unchanged
layout(location = 0) in vec4 posLocal; // xy content position, zw the primitive's own frame
layout(location = 1) in vec4 kindParams;
layout(location = 2) in vec4 colour0;
layout(location = 3) in vec4 colour1;
layout(location = 4) in vec4 colour2;

layout(location = 0) out vec2 vLocal;
layout(location = 1) flat out vec4 vKind;
layout(location = 2) flat out vec4 vC0;
layout(location = 3) flat out vec4 vC1;
layout(location = 4) flat out vec4 vC2;

layout(std140, binding = 0) uniform buf { mat4 mvp; };

void main() {
    vLocal = posLocal.zw;
    vKind = kindParams;
    vC0 = colour0; vC1 = colour1; vC2 = colour2;
    gl_Position = mvp * vec4(posLocal.xy, 0.0, 1.0);
}
