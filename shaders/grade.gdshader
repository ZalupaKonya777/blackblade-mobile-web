shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength = 0.65;
void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float l = dot(c, vec3(.2126,.7152,.0722));
	vec3 grade = mix(vec3(l), c, .94);
	grade = (grade-.5)*1.035+.5;
	grade += vec3(-.005,.001,.008)*(1.0-smoothstep(.12,.65,l));
	grade += vec3(.006,.003,-.004)*smoothstep(.35,.85,l);
	vec2 v = (SCREEN_UV-.5)*vec2(1.0,.78);
	float vignette = 1.0-smoothstep(.23,.73,length(v))*.21;
	COLOR = vec4(mix(c,grade*vignette,strength),1.0);
}
