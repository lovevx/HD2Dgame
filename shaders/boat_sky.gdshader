shader_type spatial;
// 3D 过场专用球体天空盒：夜→破晓渐变色带 + 太阳光晕 + 星空微点。
// 挂在相机子节点上的大球（radius≈5000，far=6000），不受场景指数雾影响（雾走 FogVolume）。

render_mode unshaded, cull_disabled;

uniform vec3 u_top_col : source_color = vec3(0.02, 0.03, 0.05);
uniform vec3 u_hor_col : source_color = vec3(0.05, 0.10, 0.16);
uniform vec3 u_ground_col : source_color = vec3(0.008, 0.008, 0.012);
uniform vec3 u_sun_dir = vec3(0.4, 0.3, -0.87);
uniform vec3 u_sun_col : source_color = vec3(1.0, 0.72, 0.4);
uniform float u_amber : hint_range(0.0, 1.0) = 0.1;   // 破晓程度：0=夜 1=昼
uniform float u_stars : hint_range(0.0, 1.0) = 0.8;
uniform float u_t = 0.0;

float hash11(float p) {
	p = fract(p * 443.897);
	p *= p;
	return fract(p * p * 317.2);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 sun = normalize(u_sun_dir);
	float h = n.y;
	vec3 col;
	// 主色带：头顶 vs 地平线 vs 脚下
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 0.5);
		col = mix(u_hor_col, u_top_col, t);
	} else {
		col = mix(u_hor_col, u_ground_col, pow(clamp(-h, 0.0, 1.0), 0.8));
	}
	// 破晓：太阳方向的水平暖带
	float sd = dot(n, sun);
	float band = exp(-abs(h) * 3.5) * 0.75 * step(0.0, sd + 0.2);
	col += vec3(1.0, 0.5, 0.22) * band * u_amber;
	// 太阳：光晕 + 日盘
	float ang = acos(clamp(sd, -1.0, 1.0));
	float halo = exp(-ang * 26.0) * 0.9;
	float core = 1.0 - smoothstep(0.006, 0.03, ang);
	col += u_sun_col * (core + halo * (0.35 + 0.65 * u_amber));
	// 星点（夜间可见，破晓渐隐）
	if (h > 0.06) {
		vec2 g = floor(n.xz * 420.0);
		float rnd = hash11(g.x * 31.7 + g.y * 9.1);
		if (rnd > 0.97) {
			float tw = 0.5 + 0.5 * sin(u_t * 2.2 + rnd * 60.0);
			col += vec3(0.85, 0.92, 1.0) * (1.0 - u_amber) * 85.0 * tw;
		}
	}
	ALBEDO = col;
	EMISSION = col;
}