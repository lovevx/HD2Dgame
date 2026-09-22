shader_type spatial;
// 港城墙着色器的「淡出版本」——只在前景遮挡淡出期间临时挂到墙段上（见 scripts/world/camera_occlusion_fade.gd）。
//
// 与 shaders/harbor_wall.gdshader 的砖石外观逐行相同，只有两处差别，都是为了淡出：
//   1) render_mode 多了 blend_mix 且**不写深度**：实测写深度的半透明墙会把身后的玩家
//      整个剔除掉（只剩背景透出来），那样就完全失去"露出玩家"的意义。
//   2) 多一个 instance uniform occl_fade，逐实例设置，1 = 实体，0 = 全透。
//
// 改外观时记得同步改 shaders/harbor_wall.gdshader；两边只此一处差别。
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 brick_color : source_color = vec4(0.72, 0.70, 0.64, 1.0);
uniform vec2 brick_size = vec2(0.46, 0.22);
uniform float mortar = 0.12;
uniform float wear = 0.10;
// 剪影染色（与 occlusion_fade_preset.gdshader 同一套）：被挡的墙光靠降不透明度
// 会在亮背景上消失，染一层偏亮青调让墙形始终可辨。
uniform vec4 occl_tint : source_color = vec4(0.10, 0.24, 0.38, 0.90);
instance uniform float occl_fade = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = (n.y > 0.7) ? world_pos.xz : ((n.x > n.z) ? world_pos.zy : world_pos.xy);
	vec2 grid = uv / max(brick_size, vec2(0.02));
	grid.x += mod(floor(grid.y), 2.0) * 0.5;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float face = smoothstep(mortar, mortar + 0.08, edge);
	float variation = 0.95 + hash(cell) * 0.09;
	float grain = (hash(floor(uv * 32.0)) - 0.5) * wear * 0.6;
	float soil = smoothstep(2.2, 0.0, world_pos.y) * 0.20;
	ALBEDO = mix(brick_color.rgb * (variation + grain) * mix(0.78, 1.0, face) * (1.0 - soil),
		occl_tint.rgb, occl_tint.a);
	ROUGHNESS = 0.86;
	SPECULAR = 0.22;
	ALPHA = occl_fade;
}
