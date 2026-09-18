shader_type spatial;
// 试炼场专用石板地面：规整等距方形砖（无砖砌错缝），低俯角透视下不会出现斜向纹路。
// 缝宽 / 砖色 / 磨损都可以调；世界坐标取样保证全场景纹素密度一致。
uniform vec4 stone_color : source_color = vec4(0.24, 0.30, 0.34, 1.0);
uniform float tile_scale = 1.0;      // 1 / 米，约每格 2 米
uniform float grout : hint_range(0.02, 0.12) = 0.05;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 cell = floor(world_pos.xz * tile_scale);
	vec2 uv = fract(world_pos.xz * tile_scale);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float is_stone = step(grout, edge);
	float variation = 0.86 + hash(cell) * 0.28;
	float grain = (hash(floor(world_pos.xz * 24.0)) - 0.5) * 0.07;
	float rim = (1.0 - step(0.12, edge)) * 0.06;
	// 远处的砖缝不要硬得像刻线：按边缘距离做一圈柔和过渡
	float mortar = smoothstep(grout + 0.01, grout, edge);
	ALBEDO = stone_color.rgb * (variation + grain) * mix(0.55, 1.0, is_stone) + rim;
	ROUGHNESS = mix(0.96, 0.55, mortar);
	SPECULAR = 0.18;
}