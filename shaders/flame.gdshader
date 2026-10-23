shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never;
uniform vec4 tint : source_color=vec4(0.10,0.45,1.0,0.8);
void vertex(){VERTEX.x+=sin(UV.y*11.0+TIME*9.0)*0.05*UV.y;}
void fragment(){vec2 u=UV*2.0-1.0;float shape=max(0.0,1.0-length(u*vec2(1.0,0.85)));float tendril=sin(UV.x*18.0+UV.y*13.0-TIME*8.0)*0.18+0.82;ALBEDO=mix(tint.rgb,vec3(0.65,0.9,1.0),pow(shape,4.0))*2.0;ALPHA=pow(shape,1.7)*tendril*tint.a;}
