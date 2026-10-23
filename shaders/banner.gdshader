shader_type spatial;
render_mode cull_disabled;
uniform sampler2D cloth : source_color,filter_linear_mipmap;
void vertex(){float f=UV.y*UV.y;VERTEX.z+=sin(UV.y*7.0+TIME*1.35+MODEL_MATRIX[3].x)*f*0.12;VERTEX.x+=sin(UV.y*5.0+TIME*0.8)*f*0.025;}
void fragment(){vec4 c=texture(cloth,UV);ALBEDO=c.rgb;ALPHA=c.a;ALPHA_SCISSOR_THRESHOLD=0.5;ROUGHNESS=0.95;}
