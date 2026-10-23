shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
void fragment() {
	float feather = smoothstep(0.0,.30,UV.x)*(1.0-smoothstep(.85,1.0,UV.x));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a*feather*.68;
}
