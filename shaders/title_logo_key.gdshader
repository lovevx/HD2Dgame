shader_type canvas_item;

uniform vec4 key_color : source_color = vec4(0.22745, 0.25098, 0.27059, 1.0);
uniform float mask_start = 0.008;
uniform float mask_end = 0.06;
uniform float glint_position = -1.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float mask = smoothstep(mask_start, mask_end, distance(source.rgb, key_color.rgb));
	vec3 isolated = clamp(
		(source.rgb - key_color.rgb * (1.0 - mask)) / max(mask, 0.001),
		vec3(0.0), vec3(1.0)
	);
	float brightness = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float glint = exp(-pow((UV.x - glint_position) * 42.0, 2.0)) * smoothstep(0.08, 0.48, brightness) * mask;
	isolated += vec3(0.30, 0.34, 0.38) * glint;
	COLOR = vec4(isolated, source.a * mask);
}
