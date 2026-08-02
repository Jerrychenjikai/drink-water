#include <flutter/runtime_effect.glsl>

uniform vec2 u_container_size;   // 0, 1: 容器宽高
uniform vec2 u_container_offset; // 2, 3: 实时屏幕坐标
uniform vec2 u_bg_size;          // 4, 5: 背景图片宽高
uniform float u_intensity;       // 6: 折射强度
uniform float u_corner_radius;   // 7: 容器圆角半径
uniform float u_edge_margin;     // 8: 边缘畸变带的宽度（像素）
uniform sampler2D u_bg_texture;

out vec4 fragColor;

// 计算点 p 到圆角矩形边界的 SDF ( Signed Distance Function )
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// 【关键修复】：利用 SDF 有限差分求梯度，获得精确且连续的向外法线向量
vec2 getRoundedBoxNormal(vec2 p, vec2 b, float r) {
    vec2 e = vec2(0.1, 0.0); // 0.1 像素微小偏移
    float dx = sdRoundedBox(p + e.xy, b, r) - sdRoundedBox(p - e.xy, b, r);
    float dy = sdRoundedBox(p + e.yx, b, r) - sdRoundedBox(p - e.yx, b, r);
    return normalize(vec2(dx, dy));
}

void main() {
    vec2 localCoord = FlutterFragCoord().xy;
    vec2 centerPos = u_container_size * 0.5;
    
    // 换算为以容器中心为原点的相对坐标
    vec2 p = localCoord - centerPos;
    
    // 修正圆角半径，防止圆角大于宽高的一半
    float r = min(u_corner_radius, min(centerPos.x, centerPos.y));
    vec2 b = centerPos - vec2(r);

    // 计算 SDF：在卡片内部时 sdf 为负数
    float sdf = sdRoundedBox(p, b, r);
    float distFromEdge = -sdf; // 转为正数：当前像素点距离卡片外边缘的实际像素数

    vec2 lensOffset = vec2(0.0);

    // 【关键控制】：只在 [0, u_edge_margin] 像素范围内产生畸变，再往深处完全不畸变
    if (distFromEdge >= 0.0 && distFromEdge < u_edge_margin) {
        // 归一化进度：0.0 (靠近内部无畸变边界) -> 1.0 (最外侧边缘)
        float t = 1.0 - (distFromEdge / u_edge_margin);
        
        // 高阶非线性过渡，让最靠里的地方衔接极度平滑，最外层边缘弯折剧烈
        float factor = pow(t, 4);

        // 利用 SDF 梯度计算法线方向（自动指向卡片外侧）
        vec2 normal = getRoundedBoxNormal(p, b, r);

        // 沿法线方向做偏移计算
        lensOffset = normal * factor * u_intensity * 40.0;
    }

    // 计算全局采样坐标
    vec2 globalCoord = u_container_offset + localCoord + lensOffset;
    vec2 globalUv = globalCoord / u_bg_size;
    globalUv = clamp(globalUv, vec2(0.001), vec2(0.999));

    fragColor = texture(u_bg_texture, globalUv);
}