#include <flutter/runtime_effect.glsl>

uniform vec2 u_container_size;   // 0, 1: 容器宽高
uniform vec2 u_container_offset; // 2, 3: 实时屏幕坐标
uniform vec2 u_bg_size;          // 4, 5: 背景图片宽高
uniform float u_intensity;       // 6: 折射强度 (可作为整体艺术缩放控制)
uniform float u_corner_radius;   // 7: 容器圆角半径
uniform float u_edge_margin;     // 8: 边缘畸变带的宽度（像素），相当于透镜半径 r
uniform sampler2D u_bg_texture;

out vec4 fragColor;

// 计算点 p 到圆角矩形边界的 SDF
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// 利用 SDF 有限差分求梯度 (稍微加大了偏移量 e 以获取更平滑的法线)
vec2 getRoundedBoxNormal(vec2 p, vec2 b, float r) {
    vec2 e = vec2(0.5, 0.0); 
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
    float rounded_r = min(u_corner_radius, min(centerPos.x, centerPos.y));
    vec2 b = centerPos - vec2(rounded_r);

    // 计算 SDF
    float sdf = sdRoundedBox(p, b, rounded_r);
    float distFromEdge = -sdf; 

    vec2 lensOffset = vec2(0.0);

    // 物理光学折射参数
    // 将物理玻璃的折射率设为常量 1.5 (你可以根据需要调整，水大约是 1.33)
    const float n = 1.7; 
    const float inv_n = 1.0 / n;
    const vec2 n2_and_one = vec2(n * n, 1.0);

    if (distFromEdge >= 0.0 && distFromEdge < u_edge_margin) {
        // 归一化进度 t (相当于公式中的 x/r): 
        // 0.0 (靠近内部无畸变边界) -> 1.0 (最外侧边缘)
        float t = 1.0 - (distFromEdge / u_edge_margin);
        float t2 = t * t;
        
        // 核心优化点：利用向量化合并两次开方运算
        // sqrts.x = sqrt(n^2 - t^2)
        // sqrts.y = sqrt(1 - t^2)
        // max() 确保由于浮点误差导致的极小负数不会引起 NaN
        vec2 sqrts = sqrt(max(n2_and_one - vec2(t2), 0.0));
        
        // 物理偏移幅度 (Delta d)
        // 公式：(t * r / n) * (sqrt(n^2 - t^2) - sqrt(1 - t^2))
        float offsetMag = (t * u_edge_margin * inv_n) * (sqrts.x - sqrts.y);

        // 计算法线并施加位移
        // u_intensity 此时作为额外的一个艺术控制系数，用来总体放大或缩小折射效果
        vec2 normal = getRoundedBoxNormal(p, b, rounded_r);
        lensOffset = normal * offsetMag * u_intensity;
    }

    // 计算全局采样坐标
    vec2 globalCoord = u_container_offset + localCoord + lensOffset;
    vec2 globalUv = globalCoord / u_bg_size;
    
    // 防止采样越界
    globalUv = clamp(globalUv, vec2(0.001), vec2(0.999));

    fragColor = texture(u_bg_texture, globalUv);
}