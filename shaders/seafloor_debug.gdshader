shader_type spatial;
render_mode cull_front, diffuse_lambert, specular_disabled;

uniform vec3 base_color_low : source_color = vec3(0.12, 0.10, 0.08);
uniform vec3 base_color_high : source_color = vec3(0.34, 0.30, 0.24);
uniform float min_height = -48.0;
uniform float max_height = 8.0;
uniform float contour_steps : hint_range(1.0, 64.0) = 26.0;
uniform float contour_strength : hint_range(0.0, 1.0) = 0.26;
uniform float noise_scale : hint_range(0.001, 1.0) = 0.085;
uniform float slope_darkening : hint_range(0.0, 1.0) = 0.30;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 nrm = normalize(world_normal);
	if (!FRONT_FACING) {
		nrm = -nrm;
	}

	float h01 = clamp((world_pos.y - min_height) / max(max_height - min_height, 0.001), 0.0, 1.0);
	vec3 base_col = mix(base_color_low, base_color_high, h01);

	float n = noise2(world_pos.xz * noise_scale);
	base_col *= 0.90 + n * 0.20;

	float contour_phase = fract(h01 * contour_steps + n * 0.22);
	float contour_dist = abs(contour_phase - 0.5) * 2.0;
	float contour = 1.0 - smoothstep(0.46, 0.54, contour_dist);
	base_col = mix(base_col, vec3(0.70, 0.64, 0.55), contour * contour_strength);

	float slope = 1.0 - clamp(dot(nrm, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	base_col *= 1.0 - slope * slope_darkening;

	ALBEDO = base_col;
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
}
