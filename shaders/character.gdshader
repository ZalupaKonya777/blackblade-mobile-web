shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D armor : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = 0.42;
uniform float metal_strength = 0.85;
uniform float minimum_roughness = 0.34;

void fragment() {
	vec3 channels = texture(armor, UV).rgb;
	vec2 normal_xy = texture(normal_map, UV).rg * 2.0 - 1.0;
	vec3 mapped = vec3(normal_xy, sqrt(max(0.001, 1.0 - dot(normal_xy, normal_xy))));
	vec3 shading_normal = normalize(TANGENT * mapped.x * normal_strength
		+ BINORMAL * mapped.y * normal_strength + NORMAL * mapped.z);
	// Specular filtering for WebGL's Compatibility renderer, which has no
	// built-in screen-space roughness limiter. Fine fur and engraved edges
	// become broader highlights rather than crawling white pixels in motion.
	vec3 dx = dFdx(shading_normal), dy = dFdy(shading_normal);
	float variance = dot(dx, dx) + dot(dy, dy);
	float roughness = max(minimum_roughness, channels.g);
	ROUGHNESS = sqrt(min(1.0, roughness * roughness + min(0.32, variance * 0.38)));
	ALBEDO = texture(surface, UV).rgb;
	METALLIC = channels.b * metal_strength;
	SPECULAR = 0.36;
	AO = mix(1.0, channels.r, 0.68);
	AO_LIGHT_AFFECT = 0.35;
	NORMAL_MAP = mapped * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
}
