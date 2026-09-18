shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = floor(world_pos.xz * 6.0) / 6.0;
	float ripple = sin(p.x * 1.5 + p.y * 2.8 + TIME * 0.65) * sin(p.y * 1.1 - TIME * 0.4);
	ALBEDO = mix(vec3(0.035, 0.085, 0.12), vec3(0.08, 0.19, 0.23), ripple * 0.5 + 0.5);
	vec2 cell = floor(world_pos.xz * vec2(3.0, 12.0));
	float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float sparkle = step(0.985, seed) * pow(max(0.0, sin(TIME * 0.8 + seed * 60.0)), 12.0);
	EMISSION = vec3(0.18, 0.31, 0.35) * sparkle;
	ROUGHNESS = 0.27;
	METALLIC = 0.30;
	NORMAL_MAP = vec3(0.5 + ripple * 0.055, 0.5 + cos(p.y * 2.0 + TIME) * 0.045, 1.0);
}
