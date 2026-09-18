shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float vignette_strength : hint_range(0.0, 0.6) = 0.24;
void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	// 冷色暗部、琥珀高光，保留像素边缘，不对整个画面做模糊。
	c *= mix(vec3(0.89, 0.97, 1.08), vec3(1.07, 1.01, 0.91), smoothstep(0.12, 0.75, luma));
	c = mix(vec3(luma), c, 0.92);
	c = (c - 0.5) * 1.06 + 0.5;
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.15, 1.0);
	c *= 1.0 - vignette_strength * smoothstep(0.25, 0.73, length(d));
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
