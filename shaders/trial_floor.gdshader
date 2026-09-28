shader_type spatial;
// 四区共用世界坐标地表：废品场为泥土，城门/总部/欢乐街为不同铺装。
uniform vec4 stone_color : source_color = vec4(0.24, 0.30, 0.34, 1.0);
uniform vec4 detail_color : source_color = vec4(0.14, 0.18, 0.20, 1.0);
uniform int surface_kind = 0;
uniform float tile_scale = 0.7;
uniform float grout : hint_range(0.01, 0.12) = 0.04;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_pos.xz;
	float broad = noise(p * 0.13);
	float medium = noise(p * 0.75);
	float grain = hash(floor(p * 13.0));
	vec3 color;
	if (surface_kind == 0) {
		// 废品场：有车辙的泥地、碎石与不规则干湿色块，不出现城市石砖网格。
		float track = 1.0 - smoothstep(2.5, 5.2, abs(p.x + (broad - 0.5) * 1.8));
		color = mix(detail_color.rgb, stone_color.rgb, clamp(0.36 + broad * 0.55 + medium * 0.16, 0.0, 1.0));
		color *= 1.0 - track * 0.16;
		color += (grain - 0.5) * 0.075;
		float pebble = step(0.983, hash(floor(p * 9.0))) * step(0.45, medium);
		color += vec3(0.13, 0.11, 0.09) * pebble;
		ROUGHNESS = 0.95;
	} else {
		vec2 grid = p * tile_scale;
		if (surface_kind == 1 || surface_kind == 3) {
			grid.x += mod(floor(grid.y), 2.0) * 0.5;
		}
		vec2 cell = floor(grid);
		vec2 uv = fract(grid);
		float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float worn_edge = edge + (medium - 0.5) * 0.022;
		float mortar = 1.0 - smoothstep(grout - 0.008, grout + 0.015, worn_edge);
		float stone_variation = 0.79 + hash(cell) * 0.36;
		color = mix(stone_color.rgb * stone_variation, detail_color.rgb, mortar * 0.68);
		color += (medium - 0.5) * 0.075 + (grain - 0.5) * 0.038;
		if (surface_kind == 3) {
			// 欢乐街夜雨留下的暗色潮斑。
			float wet = smoothstep(0.57, 0.75, broad) * 0.25;
			color *= 1.0 - wet;
			ROUGHNESS = mix(0.78, 0.34, wet);
		} else {
			ROUGHNESS = 0.87;
		}
	}
	ALBEDO = max(color, vec3(0.02));
	SPECULAR = 0.14;
}
