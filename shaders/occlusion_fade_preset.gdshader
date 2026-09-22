shader_type spatial;
// 预设模型着色器（addons/hd2d_scene_tools/shaders/preset_normal.gdshader）的「淡出版本」——
// 只在前景遮挡淡出期间临时挂到摆件上（见 scripts/world/camera_occlusion_fade.gd）。
//
// 与原始版本只有两处差别，都是为了淡出：
//   1) render_mode 多了 blend_mix 且**不写深度**（写深度会把身后的玩家剔除掉）。
//   2) 多一个 instance uniform occl_fade，逐实例设置，1 = 实体，0 = 全透。
//
// 改外观时记得同步改原版；两边只此一处差别。
render_mode blend_mix, cull_disabled;

uniform sampler2D art : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D normal_art : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float cutoff : hint_range(0.0, 1.0) = 0.0;
// 剪影染色：被挡的楼光靠降不透明度会在亮背景上"整个消失"（浅墙低对比），
// 染一层偏亮的青调让楼的形状始终可辨——八方旅人式的"半透明剪影"。
// a = 染色强度；默认值走这里，代码不另设。
uniform vec4 occl_tint : source_color = vec4(0.10, 0.24, 0.38, 0.90);
instance uniform float occl_fade = 1.0;

void fragment() {
	vec4 pixel = texture(art, UV);
	if (pixel.a < cutoff) { discard; }
	// ※ 不要用 Fresnel 勾边：18° 长焦 + 16° 俯角下建筑所有面几乎正对相机，
	//   dot(N,V)≈1、rim 恒为 0——勾边在 HD-2D 俯视长焦机位下天然失效。
	// 楼的存在感全靠 occl_tint 染色（形状 = 青调剪影，与任何背景都有色差）。
	ALBEDO = mix(pixel.rgb, occl_tint.rgb, occl_tint.a);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	vec3 tangent_normal = texture(normal_art, UV).rgb;
	tangent_normal.g = 1.0 - tangent_normal.g;
	NORMAL_MAP = tangent_normal;
	ALPHA = occl_fade;
}
