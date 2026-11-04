
shader_type canvas_item;

uniform vec4 top_color : source_color =
    vec4(1.0, 0.94, 0.76, 1.0);

uniform vec4 bottom_color : source_color =
    vec4(0.96, 0.70, 0.43, 1.0);

void fragment() {
    float t = clamp(UV.y, 0.0, 1.0);

    vec4 gradient_color = mix(
        top_color,
        bottom_color,
        t
    );

    COLOR.rgb *= gradient_color.rgb;
}
