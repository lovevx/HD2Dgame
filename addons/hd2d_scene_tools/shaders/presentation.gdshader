shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float vignette_amount = 0.36;
uniform float zone_blur = 1.0;
uniform float contrast = 1.11;
uniform float saturation = 1.10;
uniform vec3 tint = vec3(1.03,1.01,0.95);
void fragment(){
	vec2 uv=SCREEN_UV;
	float near_blur=smoothstep(0.79,1.0,uv.y)*2.7;
	float far_blur=(1.0-smoothstep(0.27,0.48,uv.y))*1.25;
	vec3 c=textureLod(screen_texture,uv,max(near_blur,far_blur)*zone_blur).rgb;
	c=(c-0.5)*contrast+0.5;
	float luma=dot(c,vec3(0.2126,0.7152,0.0722));
	c=mix(vec3(luma),c,saturation)*tint;
	vec2 d=(uv-vec2(0.5))*vec2(1.3,1.0);
	c*=1.0-vignette_amount*smoothstep(0.3,0.78,length(d));
	COLOR=vec4(c,1.0);
}
