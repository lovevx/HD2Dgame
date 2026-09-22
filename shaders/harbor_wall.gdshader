shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 三平面投影的砖石墙面：勒脚、墙身共用一套 shader，只换砖色与砖尺寸。
// 用世界坐标而不是 UV，砖缝密度才不会随墙段长宽变化；按面法线选投影平面，
// 避免砖缝在竖直面上被拉成条纹。
uniform vec4 brick_color : source_color = vec4(0.72, 0.70, 0.64, 1.0);
uniform vec2 brick_size = vec2(0.46, 0.22);
uniform float mortar = 0.12;
uniform float wear = 0.10;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 墙体都是轴对齐的长方体，各向异性缩放不会改变法线方向，这里直接归一化即可。
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = (n.y > 0.7) ? world_pos.xz : ((n.x > n.z) ? world_pos.zy : world_pos.xy);
	vec2 grid = uv / max(brick_size, vec2(0.02));
	grid.x += mod(floor(grid.y), 2.0) * 0.5;          // 错缝
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float face = smoothstep(mortar, mortar + 0.08, edge);   // 1 = 砖面，0 = 砖缝
	float variation = 0.95 + hash(cell) * 0.09;
	float grain = (hash(floor(uv * 32.0)) - 0.5) * wear * 0.6;
	// 越靠地面越脏：勒脚与墙根自然积灰。
	float soil = smoothstep(2.2, 0.0, world_pos.y) * 0.20;
	// 砖缝只压到 0.78：远看是一整片墙，近看才见缝，避免整面墙变成马赛克。
	ALBEDO = brick_color.rgb * (variation + grain) * mix(0.78, 1.0, face) * (1.0 - soil);
	ROUGHNESS = 0.86;
	SPECULAR = 0.22;
}
