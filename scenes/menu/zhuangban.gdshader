shader_type canvas_item;

// 1. 品红抠底设置
uniform vec4 key_color : source_color = vec4(1.0, 0.0, 1.0, 1.0);
uniform float chroma_threshold : hint_range(0.0, 1.0) = 0.25;

// 2. 黄色虚化发光设置
uniform vec4 glow_color : source_color = vec4(1.0, 0.92, 0.55, 0.85); // 柔和暖黄色光晕
uniform float glow_radius : hint_range(0.0, 30.0) = 8.0;              // 虚化光晕宽度（像素）
uniform float glow_intensity : hint_range(0.0, 5.0) = 1.6;           // 虚化光晕强度
uniform int samples : hint_range(4, 32) = 16;                        // 采样平滑度（建议 16）

// 辅助函数：判断是否为抠除背景
bool is_background(vec4 c) {
    return c.a < 0.05 || distance(c.rgb, key_color.rgb) < chroma_threshold;
}

void fragment() {
    vec4 src = texture(TEXTURE, UV);
    vec2 ps = TEXTURE_PIXEL_SIZE;
    
    // 多方向圆周采样计算虚化边缘的外溢 Alpha
    float max_glow = 0.0;
    float sum_glow = 0.0;
    
    for (int i = 0; i < samples; i++) {
        float angle = float(i) * 6.2831853 / float(samples);
        vec2 dir = vec2(cos(angle), sin(angle));
        
        // 分层衰减采样（形成虚化羽化渐变）
        for (float r = 1.0; r <= 3.0; r += 1.0) {
            vec2 sample_uv = UV + dir * ps * (glow_radius * (r / 3.0));
            vec4 sample_col = texture(TEXTURE, sample_uv);
            
            if (!is_background(sample_col)) {
                float weight = 1.0 - (r / 3.0) * 0.5;
                sum_glow += weight;
                max_glow = max(max_glow, weight);
            }
        }
    }
    
    float glow_factor = clamp((sum_glow / float(samples * 3)) * glow_intensity, 0.0, 1.0);

    // 核心渲染逻辑
    if (is_background(src)) {
        // 背景区域：仅显示向外扩散的虚化黄色微光
        if (glow_factor > 0.01) {
            COLOR = vec4(glow_color.rgb, glow_color.a * glow_factor);
        } else {
            discard;
        }
    } else {
        // 物体内部：原图颜色叠加黄色边缘柔光
        vec4 base_glow = vec4(glow_color.rgb, glow_color.a * glow_factor);
        COLOR = mix(src, base_glow, 0.25);
    }
}