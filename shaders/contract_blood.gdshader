shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.53, 0.63);
uniform vec4 blood_color : source_color = vec4(0.72, 0.12, 0.10, 0.85);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = UV - origin;
	float d = length(vec2(p.x * 0.92, p.y * 1.06));
	vec2 cell = floor(UV * vec2(18.0, 14.0));
	float grain = (hash21(cell) - 0.5) * 0.11;
	float veins = abs(sin(UV.x * 37.0 + sin(UV.y * 19.0) * 2.1)) * 0.025;
	float edge = progress * 1.12;
	float stain = smoothstep(d + grain + veins, d + grain + veins + 0.08, edge);
	float pools = 0.28 + 0.5 * hash21(floor(UV * vec2(9.0, 7.0)));
	float alpha = stain * pools * blood_color.a;
	COLOR = vec4(blood_color.rgb, alpha);
}
