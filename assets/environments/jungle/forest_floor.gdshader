shader_type spatial;
render_mode diffuse_burley;

uniform bool clearing = false;
varying vec3 world_position;

float hash(vec2 p) {
	// Integer hashing keeps shared cell corners identical across GPU compilers.
	uvec2 q = uvec2(ivec2(p));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 16777215u) / 16777215.0;
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = floor(world_position.xz * 12.0) / 12.0;
	float broad = noise(p * 0.22);
	float grain = noise(p * 2.6);
	float speckle = hash(floor(p * 12.0));
	vec3 moss = mix(vec3(0.028, 0.047, 0.027), vec3(0.070, 0.102, 0.042), broad);
	vec3 loam = mix(vec3(0.070, 0.049, 0.028), vec3(0.14, 0.101, 0.055), noise(p * 0.36));
	float trail_center = 1.2 * sin(p.y * 0.29) + 0.5 * cos(p.y * 0.51);
	float edge = (noise(p * 1.1) - 0.5) * 0.65;
	float path = 1.0 - smoothstep(1.25, 2.9, abs(p.x - trail_center) + edge);
	if (clearing) {
		float oval = length(p / vec2(14.0, 18.0));
		path = 1.0 - smoothstep(0.65, 1.22, oval + (broad - 0.5) * 0.17);
	}
	vec3 ground = mix(moss, loam, path);
	ground *= 0.92 + 0.12 * grain + 0.035 * speckle;
	float litter = step(0.977, speckle) * (1.0 - path * 0.82);
	ground = mix(ground, vec3(0.14, 0.095, 0.037), litter * 0.30);
	ALBEDO = ground;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
