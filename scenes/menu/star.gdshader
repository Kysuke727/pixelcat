shader_type canvas_item;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 如果像素非常接近桃红色（R > 0.9 且 G < 0.1 且 B > 0.9），就让它完全透明
    if (tex_color.r > 0.9 && tex_color.g < 0.1 && tex_color.b > 0.9) {
        discard; // 丢弃这个像素
    }
    
    COLOR = tex_color * COLOR; // 保留星芒并乘上粒子本色
}