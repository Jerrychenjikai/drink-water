#include <flutter/runtime_effect.glsl>

uniform vec2 u_container_size;   // 容器尺寸
uniform vec2 u_container_offset; // 容器在屏幕上的左上角偏移 (x, y)
uniform vec2 u_bg_size;          // 背景总尺寸
uniform float u_intensity;       // 折射强度
uniform sampler2D u_bg_texture;  // 背景纹理

out vec4 fragColor;

void main() {
    // 当前像素在卡片内部的本地坐标
    vec2 localCoord = FlutterFragCoord().xy;
    vec2 localUv = localCoord / u_container_size;

    // 1. 纯平滑边缘透镜折射 (完全无表面波纹 ripples)
    // 以中心点为基准，利用二次方让中心保持平整，仅在边缘产生平滑倒角偏折
    vec2 center = localUv - vec2(0.5);
    float dist = length(center);
    vec2 lensOffset = center * pow(dist, 2.0) * u_intensity;

    // 2. 换算像素级偏移量
    vec2 pixelOffset = lensOffset * u_container_size;

    // 3. 计算并采样背景的全局坐标
    vec2 globalCoord = u_container_offset + localCoord + pixelOffset;
    vec2 globalUv = globalCoord / u_bg_size;
    globalUv = clamp(globalUv, vec2(0.001), vec2(0.999));

    fragColor = texture(u_bg_texture, globalUv);
}