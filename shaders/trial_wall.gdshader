shader_type spatial;
// 战役远景城墙：世界坐标砖缝避免墙段和垛口出现拉伸纹理。
uniform vec4 stone_color : source_color = vec4(0.34, 0.39, 0.42, 1.0);
varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 horizontal = abs(world_normal.x) > abs(world_normal.z) ? world_pos.zy : world_pos.xy;
	vec2 grid = horizontal * vec2(0.8, 1.4);
	grid.x += mod(floor(grid.y), 2.0) * 0.5;
	vec2 cell = floor(grid);
	vec2 uv = fract(grid);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float joint = 1.0 - smoothstep(0.035, 0.07, edge);
	float variation = 0.78 + hash(cell) * 0.3;
	float grain = (hash(floor(world_pos.xy * 11.0)) - 0.5) * 0.075;
	ALBEDO = stone_color.rgb * (variation * (1.0 - joint * 0.35) + grain);
	ROUGHNESS = 0.91;
}
