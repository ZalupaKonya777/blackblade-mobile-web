shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D stone_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float rage = 0.0;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float ring(float r,float c,float w){return 1.0-smoothstep(w,w+0.025,abs(r-c));}
void fragment(){
 vec2 p=wp.xz;float r=length(p);float a=atan(p.y,p.x);float ri=floor(r/1.8);
 float segments=max(10.0,floor(6.283185*(ri+0.5)*1.8/2.1));
 float ai=floor((a+3.141593)/6.283185*segments);float id=hash(vec2(ri,ai));
 float rr=fract(r/1.8);float aa=fract((a+3.141593)/6.283185*segments);
 float seam=1.0-smoothstep(0.002,0.012,min(min(rr,1.0-rr),min(aa,1.0-aa)*0.6));
 vec2 uv=p*0.42+id*3.13;
 vec3 color=texture(stone_color,uv).rgb*vec3(0.62,0.72,0.86)*(0.75+id*0.35);
 float inlay=max(max(ring(r,3.2,0.055),ring(r,3.4,0.022)),max(ring(r,7.4,0.055),ring(r,7.65,0.02)));
 inlay=max(inlay,max(ring(r,12.0,0.06),ring(r,17.4,0.065)));
 float star_r=mix(2.8,0.55,abs(sin(a*4.0)));
 float star=1.0-smoothstep(0.035,0.065,abs(r-star_r));
 inlay=max(inlay,star*step(r,3.0));
 ALBEDO=mix(mix(color,vec3(0.014,0.024,0.035),seam),vec3(0.31,0.30,0.24),inlay);
 METALLIC=mix(0.12,0.7,inlay);ROUGHNESS=mix(0.56,0.32,inlay);
 NORMAL_MAP=texture(stone_normal,uv).rgb;NORMAL_MAP_DEPTH=0.5;
 EMISSION=inlay*mix(vec3(0.02,0.035,0.055),vec3(0.20,0.018,0.025),rage);
}
