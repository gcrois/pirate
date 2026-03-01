// Gerstner wave ocean shader
// Base: Chrisknyfe/boujie_water_shader (MIT)
// Additions: wake texture displacement + ring ripples
// Uses depth buffer for depth-aware transparency

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx, world_vertex_coords, shadows_disabled;

#define WORLD_TRIPLANAR
#define ALBEDO_WAVE
#define VERTEX_WAVE
#define FOAM
#define FRESNEL
#define DISTANCE_FADE
#define FOAM_FADE
#define VERTEX_WAVE_FADE

uniform bool freeze_time = false;
uniform float wave_time_seconds = 0.0;
uniform vec4 albedo : source_color = vec4(0.05, 0.52, 0.68, 0.62);
uniform vec4 albedo_fresnel : source_color = vec4(0.08, 0.38, 0.72, 0.96);
uniform float water_opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms DepthBlend;
uniform sampler2D scene_depth_texture : hint_depth_texture, filter_linear, repeat_disable;
uniform float shallow_water_alpha : hint_range(0.0, 1.0) = 0.32;
uniform float deep_water_alpha : hint_range(0.0, 1.0) = 0.68;
uniform float depth_absorption : hint_range(0.0, 12.0) = 3.2;
uniform float depth_color_strength : hint_range(0.0, 1.0) = 0.22;
group_uniforms;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float albedo_texture_strength : hint_range(0.0, 1.0) = 0.92;
uniform float specular : hint_range(0.0, 1.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool vertex_displace_from_mesh_normal = false;
uniform bool normal_wave_from_mesh_normal = false;

group_uniforms Foam;
uniform sampler2D texture_foam : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 foam_tri_scale = vec3(12.0, 12.0, 12.0);
uniform float crest_height_start : hint_range(-2.0, 2.0) = 0.22;
uniform float crest_height_end : hint_range(-2.0, 3.0) = 0.92;
uniform float crest_slope_start : hint_range(0.0, 1.0) = 0.06;
uniform float crest_slope_end : hint_range(0.0, 1.0) = 0.30;
uniform float crest_foam_strength : hint_range(0.0, 1.0) = 0.36;
uniform float wake_foam_strength : hint_range(0.0, 1.0) = 0.42;
uniform float surface_pattern_strength : hint_range(0.0, 1.0) = 0.52;
group_uniforms;

group_uniforms DistanceFade;
uniform float distance_fade_min = 450.0;
uniform float distance_fade_max = 600.0;
group_uniforms;

group_uniforms FeatureFade;
uniform float near_fade_min = 1.5;
uniform float near_fade_max = 1.7;
uniform float foam_fade_min = 150.0;
uniform float foam_fade_max = 350.0;
uniform float vertex_wave_fade_min = 200.0;
uniform float vertex_wave_fade_max = 500.0;
group_uniforms;

group_uniforms WorldTriplanarUvs;
uniform float uv_blend_sharpness = 2.0;
uniform vec3 uv_tri_scale = vec3(20.0, 20.0, 20.0);
uniform vec3 uv_tri_offset = vec3(0.0, 0.0, 0.0);
group_uniforms;

group_uniforms WaveParameters;
uniform int WaveCount : hint_range(0, 8) = 0;
uniform float WaveSteepnesses[8];
uniform float WaveAmplitudes[8];
uniform float WaveDirectionsDegrees[8];
uniform float WaveFrequencies[8];
uniform float WaveSpeeds[8];
uniform float WavePhases[8];
group_uniforms;

group_uniforms FoamWaveParameters;
uniform int FoamWaveCount : hint_range(0, 8) = 0;
uniform float FoamWaveSteepnesses[8];
uniform float FoamWaveAmplitudes[8];
uniform float FoamWaveDirectionsDegrees[8];
uniform float FoamWaveFrequencies[8];
uniform float FoamWaveSpeeds[8];
uniform float FoamWavePhases[8];
group_uniforms;

group_uniforms UVWaveParameters;
uniform int UVWaveCount : hint_range(0, 8) = 0;
uniform float UVWaveSteepnesses[8];
uniform float UVWaveAmplitudes[8];
uniform float UVWaveDirectionsDegrees[8];
uniform float UVWaveFrequencies[8];
uniform float UVWaveSpeeds[8];
uniform float UVWavePhases[8];
group_uniforms;

// ── Wake / ship system ────────────────────────────────────────────────────────
group_uniforms Wake;
uniform vec3 ship_pos_0 = vec3(0.0);
uniform vec3 ship_pos_1 = vec3(0.0);
uniform float ship_spd_0 = 0.0;
uniform float ship_spd_1 = 0.0;
uniform float ship_contact_0 = 0.0;
uniform float ship_contact_1 = 0.0;
uniform float ship_rel_spd_0 = 0.0;
uniform float ship_rel_spd_1 = 0.0;
uniform float ship_len_0 = 4.5;
uniform float ship_len_1 = 4.5;
uniform float ship_wid_0 = 1.75;
uniform float ship_wid_1 = 1.75;
uniform sampler2D wake_tex_0 : filter_linear, repeat_disable;
uniform sampler2D wake_tex_1 : filter_linear, repeat_disable;
uniform float ocean_size_meters = 100.0;
uniform float wake_filter_uv : hint_range(0.0, 0.02) = 0.0022;
uniform float wake_detail_scale : hint_range(1.0, 16.0) = 8.0;
uniform float wake_detail_brightness : hint_range(1.0, 3.0) = 1.42;
uniform float wake_detail_strength : hint_range(0.0, 1.5) = 0.85;
uniform float wake_max_displacement : hint_range(0.0, 5.0) = 2.0;
uniform float ring_frequency : hint_range(0.0, 3.0) = 0.5;
uniform float ring_speed : hint_range(0.0, 30.0) = 10.0;
uniform float ring_decay : hint_range(1.0, 60.0) = 18.0;
uniform float ring_amplitude : hint_range(0.0, 1.0) = 0.15;
group_uniforms;
// ─────────────────────────────────────────────────────────────────────────────

varying vec3  uv_tri;
varying vec3  uv_power_normal;
varying vec3  world_coordinates;
varying float wave_height_v;
varying float wave_slope_v;


float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

// Gerstner wave position offset
vec3 P_DEG(float x, float z, float t,
		float Steepness, float Amplitude,
		float DirectionDegrees, float Frequency, float Speed, float PhaseDegrees) {
	vec2 D = vec2(sin(DirectionDegrees * TAU / 360.0), cos(DirectionDegrees * TAU / 360.0));
	float p = PhaseDegrees * TAU / 360.0;
	float phi = TAU * dot(Frequency * D, vec2(x, z)) + Speed * (t + p);
	return vec3(
		Steepness * Amplitude * D.x * cos(phi),
		Steepness * sin(phi),
		Steepness * Amplitude * D.y * cos(phi)
	);
}

// Gerstner wave normal perturbation
vec3 N_DEG(float x, float z, float t,
		float Steepness, float Amplitude,
		float DirectionDegrees, float Frequency, float Speed, float PhaseDegrees) {
	vec2 D = vec2(sin(DirectionDegrees * TAU / 360.0), cos(DirectionDegrees * TAU / 360.0));
	float p = PhaseDegrees * TAU / 360.0;
	float phi = Frequency * TAU * dot(D, vec2(x, z)) + Speed * (t + p);
	return vec3(
		-D.x * Frequency * Amplitude * cos(phi),
		1.0 - Steepness * Frequency * Amplitude * sin(phi),
		-D.y * Frequency * Amplitude * cos(phi)
	);
}

vec3 rotate_to_normal(vec3 point, vec3 normal) {
	float theta = atan(normal.z, normal.x);
	if (abs(normal.z) < 0.0001 && abs(normal.x) < 0.0001) theta = 0.0;
	float phi = acos(normal.y);
	float ct = cos(theta); float st = sin(theta);
	float cp = cos(phi);   float sp = sin(phi);
	mat3 rot = mat3(vec3(cp*ct, -sp, cp*st), vec3(sp*ct, cp, sp*st), vec3(-st, 0.0, ct));
	return rot * point;
}

// Wake ring ripples around a ship
float wake_rings(vec2 world_xz, vec3 ship_pos, float ship_speed, float t) {
	float speed_fac = smoothstep(0.5, 6.0, ship_speed);
	float d = length(world_xz - ship_pos.xz);
	if (ring_amplitude < 0.001 || d < 0.5 || d > ring_decay * 2.5) return 0.0;
	float ring  = sin(d * ring_frequency * TAU - t * ring_speed);
	float decay = exp(-d / ring_decay);
	return ring * decay * ring_amplitude * speed_fac;
}

// Wake texture displacement
float wake_safe_sample(sampler2D wake_tex, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.5;
	}
	return texture(wake_tex, uv).r;
}


float wake_tex_filtered(vec2 world_xz, vec3 ship_pos, sampler2D wake_tex) {
	vec2 diff = world_xz - ship_pos.xz;
	vec2 uv   = (diff / ocean_size_meters) + vec2(0.5);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.5;
	vec2 o = vec2(wake_filter_uv, wake_filter_uv);
	float c = wake_safe_sample(wake_tex, uv);
	float n = wake_safe_sample(wake_tex, uv + vec2(0.0, -o.y));
	float s = wake_safe_sample(wake_tex, uv + vec2(0.0, o.y));
	float e = wake_safe_sample(wake_tex, uv + vec2(o.x, 0.0));
	float w = wake_safe_sample(wake_tex, uv + vec2(-o.x, 0.0));
	return (c * 4.0 + n + s + e + w) / 8.0;
}


float wake_tex_disp(vec2 world_xz, vec3 ship_pos, sampler2D wake_tex) {
	float r = wake_tex_filtered(world_xz, ship_pos, wake_tex);
	return (r > 0.05) ? (r - 0.5) * wake_max_displacement : 0.0;
}


float wake_tex_disturbance(vec2 world_xz, vec3 ship_pos, sampler2D wake_tex) {
	return abs(wake_tex_filtered(world_xz, ship_pos, wake_tex) - 0.5);
}


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
	float time = freeze_time ? 0.0 : wave_time_seconds;

	world_coordinates = VERTEX;
	vec2 wave_coords = world_coordinates.xz;
	vec3 world_camera_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist_cam = distance(world_coordinates, world_camera_pos);

#ifdef WORLD_TRIPLANAR
	uv_power_normal = pow(abs(NORMAL), vec3(uv_blend_sharpness));
	uv_power_normal /= dot(uv_power_normal, vec3(1.0));
	uv_tri = (world_coordinates).xyz / uv_tri_scale + uv_tri_offset;
	uv_tri *= vec3(1.0, -1.0, 1.0);
	UV = uv_tri.xz;
#endif

#ifdef ALBEDO_WAVE
	vec3 uvwave = vec3(0.0);
	for (int i = 0; i < UVWaveCount; i++) {
		uvwave += P_DEG(UV.x, UV.y, time,
			UVWaveSteepnesses[i], UVWaveAmplitudes[i],
			UVWaveDirectionsDegrees[i], UVWaveFrequencies[i],
			UVWaveSpeeds[i], UVWavePhases[i]);
	}
	uv_tri += uvwave;
	UV += uvwave.xz;
#endif

	wave_height_v = 0.0;
	wave_slope_v = 0.0;

	float vertex_fade = 1.0;
#ifdef VERTEX_WAVE_FADE
	vertex_fade = smoothstep(vertex_wave_fade_max, vertex_wave_fade_min, dist_cam);
#endif

#ifdef VERTEX_WAVE
	vec3 vertexWave = vec3(0.0);
	for (int i = 0; i < WaveCount; i++) {
		vertexWave += P_DEG(wave_coords.x, wave_coords.y, time,
			WaveSteepnesses[i], WaveAmplitudes[i],
			WaveDirectionsDegrees[i], WaveFrequencies[i],
			WaveSpeeds[i], WavePhases[i]);
	}
	vertexWave = vertexWave / float(WaveCount);
	wave_height_v = vertexWave.y;
	if (vertex_displace_from_mesh_normal) vertexWave = rotate_to_normal(vertexWave, NORMAL);
	vertexWave *= vertex_fade;
	if (WaveCount > 0) VERTEX += vertexWave;

	vec3 normalWave = vec3(0.0);
	for (int i = 0; i < WaveCount; i++) {
		normalWave += N_DEG(wave_coords.x, wave_coords.y, time,
			WaveSteepnesses[i], WaveAmplitudes[i],
			WaveDirectionsDegrees[i], WaveFrequencies[i],
			WaveSpeeds[i], WavePhases[i]);
	}
	normalWave = normalize(normalWave / float(WaveCount));
	wave_slope_v = clamp(1.0 - normalWave.y, 0.0, 1.0);
	if (normal_wave_from_mesh_normal) normalWave = rotate_to_normal(normalWave, NORMAL);
	normalWave = mix(NORMAL, normalWave, vertex_fade);
	if (WaveCount > 0) NORMAL = normalize(normalWave);
#endif

	// ── Wake displacement ────────────────────────────────────────────────────
	float wake_disp_0 = wake_rings(wave_coords, ship_pos_0, ship_spd_0, time)
		+ wake_tex_disp(wave_coords, ship_pos_0, wake_tex_0);
	float wake_disp_1 = wake_rings(wave_coords, ship_pos_1, ship_spd_1, time)
		+ wake_tex_disp(wave_coords, ship_pos_1, wake_tex_1);
	VERTEX.y += wake_disp_0 * vertex_fade;
	VERTEX.y += wake_disp_1 * vertex_fade;
	// ─────────────────────────────────────────────────────────────────────────

	world_coordinates = VERTEX;
}


vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
	samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	return samp;
}


void fragment() {
	ALPHA = 1.0;
	float dist_cam = distance(CAMERA_POSITION_WORLD, world_coordinates);
	float scene_depth_raw = texture(scene_depth_texture, SCREEN_UV).r;
	float frag_depth_raw = FRAGCOORD.z;
	float water_column_depth = max(scene_depth_raw - frag_depth_raw, 0.0);
	float depth_norm = water_column_depth / max(1.0 - frag_depth_raw, 0.0001);
	float depth_mix = 1.0 - exp(-depth_norm * depth_absorption);
	// When depth texture reads sky (no opaque geometry), fade toward deep water by distance
	// to avoid a hard ring at the seafloor mesh edge.
	float missing_depth = smoothstep(0.9985, 1.0, scene_depth_raw);
	float distance_depth = smoothstep(110.0, 460.0, dist_cam);
	depth_mix = max(depth_mix, missing_depth * distance_depth);

	float foam_fade = 1.0;
#ifdef DISTANCE_FADE
	ALPHA *= smoothstep(distance_fade_max, distance_fade_min, dist_cam);
	ALPHA *= smoothstep(near_fade_min, near_fade_max, dist_cam);
#endif
#ifdef FOAM_FADE
	foam_fade = smoothstep(foam_fade_max, foam_fade_min, dist_cam);
#endif

	if (ALPHA <= 0.0) discard;
	float fade_mask = ALPHA;

	METALLIC  = metallic;
	SPECULAR  = specular;
	ROUGHNESS = roughness;

	float time = freeze_time ? 0.0 : wave_time_seconds;
	vec4 albedo_tex;
#ifdef WORLD_TRIPLANAR
	vec3 flow_warp = vec3(NORMAL.x, 0.0, NORMAL.z) * 0.22
		+ vec3(
			noise2(world_coordinates.xz * 0.06 + vec2(time * 0.05, -time * 0.03)) - 0.5,
			0.0,
			noise2(world_coordinates.xz * 0.06 + vec2(-time * 0.04, time * 0.06)) - 0.5
		) * 0.20;
	vec3 albedo_uv_a = uv_tri + flow_warp;
	vec3 albedo_uv_b = uv_tri * 1.71 + vec3(11.2, -7.4, 5.9) + flow_warp * 0.65;
	albedo_tex = mix(
		triplanar_texture(texture_albedo, uv_power_normal, albedo_uv_a),
		triplanar_texture(texture_albedo, uv_power_normal, albedo_uv_b),
		0.45
	);
#else
	vec2 uv_a = UV + vec2(
		noise2(world_coordinates.xz * 0.06 + vec2(time * 0.05, -time * 0.03)) - 0.5,
		noise2(world_coordinates.xz * 0.06 + vec2(-time * 0.04, time * 0.06)) - 0.5
	) * 0.04;
	vec2 uv_b = UV * 1.71 + vec2(3.7, -2.4) + uv_a * 0.2;
	albedo_tex = mix(texture(texture_albedo, uv_a), texture(texture_albedo, uv_b), 0.45);
#endif

#ifdef FRESNEL
	float fresnel_fac = fresnel(3.0, NORMAL, VIEW);
	vec4 surface_color = mix(albedo, albedo_fresnel, fresnel_fac);
#else
	vec4 surface_color = albedo;
#endif

	vec3 albedo_tex_contrast = clamp((albedo_tex.rgb - vec3(0.5)) * 1.75 + vec3(0.5), vec3(0.0), vec3(1.0));
	float albedo_luma = dot(albedo_tex_contrast, vec3(0.299, 0.587, 0.114));
	vec3 albedo_neutral_detail = mix(vec3(albedo_luma), albedo_tex_contrast, 0.18);
	vec3 albedo_mod = mix(vec3(1.0), albedo_neutral_detail, albedo_texture_strength);
	ALBEDO = surface_color.rgb * albedo_mod;
	ALBEDO = mix(ALBEDO, surface_color.rgb, depth_mix * depth_color_strength);
	float base_alpha = fade_mask * surface_color.a * albedo_tex.a;
	float depth_alpha = fade_mask * mix(shallow_water_alpha, deep_water_alpha, depth_mix);
	ALPHA = clamp(mix(base_alpha, depth_alpha, 0.56) * water_opacity, 0.0, 1.0);
	float base_micro = noise2(world_coordinates.xz * 0.45 + vec2(time * 0.14, -time * 0.11));
	float base_pattern = clamp(albedo_luma * 0.72 + base_micro * 0.28, 0.0, 1.0);
	float base_signed = (base_pattern - 0.5) * 2.0;
	ALBEDO *= 1.0 + base_signed * (0.18 * albedo_texture_strength);
	ROUGHNESS = clamp(
		roughness - base_signed * (0.12 * albedo_texture_strength),
		0.01,
		1.0
	);

#ifdef FOAM
	vec4 foam_tex;
#ifdef WORLD_TRIPLANAR
	vec3 foam_uv_tri = (world_coordinates).xyz / foam_tri_scale + uv_tri_offset + vec3(flow_warp.x, 0.0, flow_warp.z);
	foam_uv_tri *= vec3(1.0, -1.0, 1.0);
	vec3 foam_uv_tri_2 = foam_uv_tri * 1.93 + vec3(17.0, -9.0, 3.0);
	foam_tex = mix(
		triplanar_texture(texture_foam, uv_power_normal, foam_uv_tri),
		triplanar_texture(texture_foam, uv_power_normal, foam_uv_tri_2),
		0.40
	);
#else
	vec2 foam_uv = world_coordinates.xz / foam_tri_scale.x + uv_tri_offset.xz + flow_warp.xz;
	vec2 foam_uv_2 = foam_uv * 1.93 + vec2(4.1, -2.6);
	foam_tex = mix(texture(texture_foam, foam_uv), texture(texture_foam, foam_uv_2), 0.40);
#endif
	float surface_noise = noise2(world_coordinates.xz * 0.28 + vec2(time * 0.11, -time * 0.09));
	surface_noise = mix(surface_noise, noise2(world_coordinates.xz * 0.62 + vec2(-time * 0.19, time * 0.16)), 0.42);
	float surface_tex = clamp(foam_tex.r * 0.62 + foam_tex.g * 0.38, 0.0, 1.0);
	float surface_pattern = clamp(surface_tex * 0.70 + surface_noise * 0.30, 0.0, 1.0);
	surface_pattern = smoothstep(0.26, 0.84, surface_pattern);
	float surface_signed = (surface_pattern - 0.5) * 2.0;
	ALBEDO *= 1.0 + surface_signed * (surface_pattern_strength * 0.62);
	ROUGHNESS = clamp(ROUGHNESS - surface_signed * (surface_pattern_strength * 0.40), 0.01, 1.0);

	float crest_from_height = smoothstep(crest_height_start, crest_height_end, wave_height_v);
	float crest_from_slope = smoothstep(crest_slope_start, crest_slope_end, wave_slope_v);
	float crest_mask = clamp(crest_from_height * (0.55 + crest_from_slope), 0.0, 1.0);
	float foam_breakup = clamp(foam_tex.r * 0.7 + foam_tex.g * 0.3, 0.0, 1.0);
	float crest_foam = crest_mask * (0.40 + foam_breakup * 0.60) * crest_foam_strength * foam_fade;

	float wake_motion_0 = smoothstep(0.25, 6.5, ship_rel_spd_0);
	float wake_motion_1 = smoothstep(0.25, 6.5, ship_rel_spd_1);
	float wake_contact = clamp(ship_contact_0 * wake_motion_0 + ship_contact_1 * wake_motion_1, 0.0, 1.4);
	float wake_disturbance = wake_tex_disturbance(world_coordinates.xz, ship_pos_0, wake_tex_0)
		+ wake_tex_disturbance(world_coordinates.xz, ship_pos_1, wake_tex_1);
	float wake_mask = smoothstep(0.006, 0.098, wake_disturbance);
	float wake_presence = clamp(wake_mask * wake_contact, 0.0, 1.0);

	vec4 wake_detail_tex;
#ifdef WORLD_TRIPLANAR
	vec3 wake_albedo_uv_a = uv_tri * wake_detail_scale + flow_warp;
	vec3 wake_albedo_uv_b = uv_tri * (wake_detail_scale * 1.71) + vec3(11.2, -7.4, 5.9) + flow_warp * 0.65;
	wake_detail_tex = mix(
		triplanar_texture(texture_albedo, uv_power_normal, wake_albedo_uv_a),
		triplanar_texture(texture_albedo, uv_power_normal, wake_albedo_uv_b),
		0.45
	);
#else
	vec2 wake_uv_a = UV * wake_detail_scale + vec2(
		noise2(world_coordinates.xz * 0.06 + vec2(time * 0.05, -time * 0.03)) - 0.5,
		noise2(world_coordinates.xz * 0.06 + vec2(-time * 0.04, time * 0.06)) - 0.5
	) * 0.04;
	vec2 wake_uv_b = wake_uv_a * 1.71 + vec2(3.7, -2.4) + wake_uv_a * 0.2;
	wake_detail_tex = mix(texture(texture_albedo, wake_uv_a), texture(texture_albedo, wake_uv_b), 0.45);
#endif
	vec3 wake_detail_contrast = clamp((wake_detail_tex.rgb - vec3(0.5)) * 1.75 + vec3(0.5), vec3(0.0), vec3(1.0));
	float wake_detail = dot(wake_detail_contrast, vec3(0.299, 0.587, 0.114));
	wake_detail = smoothstep(0.24, 0.88, wake_detail);
	float wake_foam = wake_presence * (0.15 + wake_detail * 0.85) * (0.35 + foam_breakup * 0.65) * wake_foam_strength * foam_fade;

	float final_foam = clamp(crest_foam + wake_foam, 0.0, 0.68);
	ALBEDO = mix(ALBEDO, vec3(0.95, 0.98, 1.0), final_foam);
	float wake_highlight = wake_presence * wake_detail_strength * wake_detail;
	float wake_boost = 1.0 + wake_highlight * (wake_detail_brightness - 1.0);
	ALBEDO = min(ALBEDO * wake_boost, vec3(1.0));
	ROUGHNESS = clamp(ROUGHNESS - wake_highlight * 0.08, 0.01, 1.0);
#endif
}
