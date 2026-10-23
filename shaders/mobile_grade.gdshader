shader_type canvas_item;
render_mode unshaded, blend_mul;
// A colour overlay needs no screen readback or extra framebuffer copy on Safari.
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.76);
	float edge = smoothstep(0.22, 0.67, length(p));
	vec3 tint = mix(vec3(1.0), vec3(0.85, 0.89, 0.95), edge * 0.68);
	COLOR = vec4(tint, 1.0);
}
