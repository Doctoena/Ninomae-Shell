#version 440
// The old look of the screen, with a soft-edged hole growing from the cursor: inside it, the new look shows
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 center;  // Pixels
    vec2 size;    // Pixels
    float radius; // Pixels
    float feather;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float d = distance(qt_TexCoord0 * size, center);
    float keep = smoothstep(radius - feather, radius, d);
    fragColor = texture(source, qt_TexCoord0) * keep * qt_Opacity;
}
