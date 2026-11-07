shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);       // 纯白
uniform vec4 bottom_color : source_color = vec4(1.0, 0.92, 0.72, 1.0);   // 奶黄
uniform float start_y = 0.0;     // 渐变起点
uniform float gradient_height = 180.0; // 调大容纳范围，避免运行态溢出锁死为1.0
uniform float power : hint_range(0.5, 4.0) = 2.2; // 曲线压制，把黄色压到最底部

varying float v_pos_y;

void vertex() {
    v_pos_y = VERTEX.y;
}

void fragment() {
    // 归一化计算，限制在 0~1 之间
    float raw_t = clamp((v_pos_y - start_y) / gradient_height, 0.0, 1.0);
    // 高次方曲线：让 0.0~0.7 都保持白色，只有接近 1.0 的底部边缘才透出淡黄
    float t = pow(raw_t, power);
    
    vec4 grad = mix(top_color, bottom_color, t);
    
    // 只调整明度和色相，保留原本文字基础亮色
    COLOR.rgb *= grad.rgb;
}