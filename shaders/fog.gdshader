shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never;
uniform vec4 tint : source_color=vec4(0.3,0.6,1.0,0.4);
void fragment(){vec2 u=UV;float v=sin(u.x*15.0+sin(u.y*9.0-TIME)*2.0+TIME*0.4)*0.5+0.5;v*=sin(u.y*25.0+TIME*0.7)*0.15+0.85;float edge=pow(max(0.0,1.0-abs(u.x-0.5)*2.0),0.4)*smoothstep(1.0,0.8,u.y);ALBEDO=tint.rgb;ALPHA=v*edge*tint.a;}
