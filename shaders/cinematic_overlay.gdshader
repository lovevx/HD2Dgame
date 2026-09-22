shader_type canvas_item;
// 开场过场全屏片场特效（透明叠层，不对源画面不透明覆盖）：
//   暗角/死亡黑场 → 黑色覆盖；冲击白闪 → 白色覆盖；心跳 → 暗红涟漪。
// 各部分按不透明度加权混合（黑 0 / 白闪 / 红心跳），透明处透出底层电影画面。
// 由 opening.gd 每帧写入 uniform；色相遵循世界色彩语言：红=危险/死亡。

uniform float u_vignette : hint_range(0.0, 1.6) = 0.62;
uniform vec3  u_flash : source_color = vec3(0.0, 0.0, 0.0);   // 冲击闪色（白闪填白）
uniform float u_flash_amt : hint_range(0.0, 2.0) = 0.0;       // 冲击闪强度
uniform float u_heart : hint_range(0.0, 1.5) = 0.0;           // 心跳脉冲强度
uniform float u_heart_hue = 0.0;                              // 0=红（默认），1=青
uniform float u_dark : hint_range(0.0, 1.0) = 0.0;            // 整体压暗（死亡黑场）
uniform float u_grain : hint_range(0.0, 1.0) = 0.1;           // 胶片噪点
uniform float u_asp = 1.7778;                           // 视口宽高比（16:9)
uniform float u_t = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	c.x *= u_asp;
	float d = length(c);

	// —— 暗角（黑色覆盖量）
	float vig = smoothstep(0.62, 1.16, d);
	float a_black = vig * u_vignette + u_dark;

	// —— 冲击白闪（白色覆盖量）
	float fm = 0.0;
	if (u_flash_amt > 0.0) {
		fm = smoothstep(1.25, 0.28, d) * u_flash_amt;
	}

	// —— 心跳：一圈从屏幕边缘涌向中心的暗红涟漪
	float hb_radius = 0.52 + 0.31 * (0.5 + 0.5 * sin(u_t * 3.6));
	float hb_ring = smoothstep(0.16, 0.0, abs(d - hb_radius));
	float hb = hb_ring * (0.55 + 0.45 * sin(u_t * 7.2)) * u_heart;
	vec3 heart_col = mix(vec3(0.62, 0.04, 0.06), vec3(0.05, 0.34, 0.55), u_heart_hue);
	float a_heart = hb;

	// —— 按覆盖量加权混合源色（黑=0 权重算进分母，防被平均拉灰）
	float a_total = clamp(a_black + fm + a_heart, 0.0, 1.0);
	vec3 src = vec3(0.0) * a_black + u_flash * fm + heart_col * a_heart;
	vec3 out_col = src / max(a_total, 0.0001);

	// —— 胶片噪点（只给叠层加，透明处让底透出）
	float g = hash21(UV * vec2(1607.0, 971.0) + fract(u_t) * 61.0);
	out_col += (g - 0.5) * u_grain * a_total;

	COLOR = vec4(out_col, a_total);
}