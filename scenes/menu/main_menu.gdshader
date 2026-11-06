shader_type canvas_item;

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    // 识别纯绿幕并剔除
    if (col.g > 0.55 && col.r < 0.35 && col.b < 0.35) {
        discard;
    }
    // 关键修正：必须乘上 COLOR，否则文字的字体颜色会被强制冲刷成纯白色
    COLOR = col * COLOR;
}