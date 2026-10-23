shader_type sky;
// Static cathedral illumination for the radiance map. No TIME or directional
// light inputs: phase lighting and fire flicker never rebake this cubemap.
void sky() {
	vec3 direction = normalize(EYEDIR);
	float horizon = pow(1.0 - abs(direction.y), 3.0);
	vec3 upper = mix(vec3(0.055, 0.08, 0.15), vec3(0.22, 0.27, 0.36), horizon);
	vec3 lower = mix(vec3(0.035, 0.029, 0.023), vec3(0.17, 0.14, 0.10), horizon);
	vec3 colour = mix(lower, upper, smoothstep(-0.15, 0.15, direction.y));
	float oculus = pow(max(0.0, dot(direction, normalize(vec3(-0.3, 0.9, -0.2)))), 18.0);
	float warm = pow(max(0.0, dot(direction, normalize(vec3(0.7, 0.22, 0.55)))), 9.0);
	COLOR = colour + vec3(0.48, 0.61, 0.82) * oculus + vec3(0.19, 0.12, 0.055) * warm;
}
