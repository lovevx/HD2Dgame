shader_type spatial;
uniform vec4 stone_color : source_color = vec4(0.36, 0.42, 0.44, 1.0);
uniform float tile_scale = 1.0;
varying vec3 world_pos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// 在世界坐标上画石块和像素磨损，保持所有铺装的纹素密度一致。
	vec2 pixel = floor(world_pos.xz * 24.0) / 24.0;
	vec2 grid = pixel * vec2(1.2, 2.2) * tile_scale;
	grid.x += mod(floor(grid.y), 2.0) * 0.5;
	vec2 cell = floor(grid);
	vec2 uv = fract(grid);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float grout = step(0.045, edge);
	float variation = 0.88 + hash(cell) * 0.24;
	float grain = (hash(floor(pixel * 24.0)) - 0.5) * 0.10;
	float rim = (1.0 - step(0.11, edge)) * 0.08;
	ALBEDO = stone_color.rgb * (variation + grain + rim) * mix(0.62, 1.0, grout);
	float damp = smoothstep(0.55, 0.85, sin(pixel.x * 0.37) * cos(pixel.y * 0.28));
	ROUGHNESS = mix(0.92, 0.42, damp);
	SPECULAR = 0.28;
}
