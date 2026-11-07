shader_type canvas_item;

// 顶部：纯净雪亮奶白（避免乘法后变暗）
uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 底部：极浅柔和的布丁奶黄（低饱和度、高亮度，乘法后才通透）
uniform vec4 bottom_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);

// 文字高度（在检查器里拖拽，匹配文字字号）
uniform float text_height : hint_range(10.0, 120.0) = 45.0;

varying float v_y;

void vertex() {
    // 捕获每个字符在 Label 内部真实的垂直像素位置
    v_y = VERTEX.y;
}

void fragment() {
    // 保留你原本的 clamp 与 mix 逻辑
    float t = clamp(v_y / text_height, 0.0, 1.0);
    vec4 gradient_color = mix(top_color, bottom_color, t);
    
    // 保留你原本的乘法算法
    COLOR.rgb *= gradient_color.rgb;
}