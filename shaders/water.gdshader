// Gerstner wave ocean shader
// Base: Chrisknyfe/boujie_water_shader (MIT)
// Additions: wake texture displacement + ring ripples
// GL Compatibility safe: no screen/depth texture reads

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx, world_vertex_coords;

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
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float specular : hint_range(0.0, 1.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool vertex_displace_from_mesh_normal = false;
uniform bool normal_wave_from_mesh_normal = false;

group_uniforms Foam;
uniform sampler2D texture_foam : source_color, filter_linear_mipmap, repeat_enable;
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
uniform float ship_len_0 = 4.5;
uniform float ship_len_1 = 4.5;
uniform float ship_wid_0 = 1.75;
uniform float ship_wid_1 = 1.75;
uniform sampler2D wake_tex_0 : filter_linear, repeat_disable;
uniform sampler2D wake_tex_1 : filter_linear, repeat_disable;
uniform float ocean_size_meters = 100.0;
uniform float wake_max_displacement : hint_range(0.0, 5.0) = 2.0;
uniform float ring_frequency : hint_range(0.0, 3.0) = 0.5;
uniform float ring_speed : hint_range(0.0, 30.0) = 10.0;
uniform float ring_decay : hint_range(1.0, 60.0) = 18.0;
uniform float ring_amplitude : hint_range(0.0, 1.0) = 0.15;
group_uniforms;
// ─────────────────────────────────────────────────────────────────────────────

varying vec3  uv_tri;
varying vec3  uv_power_normal;
varying float foam_alpha;
varying vec3  world_coordinates;


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
float wake_tex_disp(vec2 world_xz, vec3 ship_pos, sampler2D wake_tex) {
	vec2 diff = world_xz - ship_pos.xz;
	vec2 uv   = (diff / ocean_size_meters) + vec2(0.5);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
	float r = texture(wake_tex, uv).r;
	return (r > 0.05) ? (r - 0.5) * wake_max_displacement : 0.0;
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

	uv_tri += vec3(0.1) * time;
	UV    += vec2(0.1) * time;

#ifdef FOAM
	vec3 foamWave = vec3(0.0);
	for (int i = 0; i < FoamWaveCount; i++) {
		foamWave += P_DEG(wave_coords.x, wave_coords.y, time,
			FoamWaveSteepnesses[i], FoamWaveAmplitudes[i],
			FoamWaveDirectionsDegrees[i], FoamWaveFrequencies[i],
			FoamWaveSpeeds[i], FoamWavePhases[i]);
	}
	foamWave  = foamWave / float(FoamWaveCount);
	foam_alpha = foamWave.y;
#else
	foam_alpha = 0.0;
#endif

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
	if (normal_wave_from_mesh_normal) normalWave = rotate_to_normal(normalWave, NORMAL);
	normalWave = mix(NORMAL, normalWave, vertex_fade);
	if (WaveCount > 0) NORMAL = normalize(normalWave);
#endif

	// ── Wake displacement ────────────────────────────────────────────────────
	VERTEX.y += (wake_rings(wave_coords, ship_pos_0, ship_spd_0, time)
	           + wake_tex_disp(wave_coords, ship_pos_0, wake_tex_0)) * vertex_fade;
	VERTEX.y += (wake_rings(wave_coords, ship_pos_1, ship_spd_1, time)
	           + wake_tex_disp(wave_coords, ship_pos_1, wake_tex_1)) * vertex_fade;
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

	float foam_fade = 1.0;
#ifdef DISTANCE_FADE
	ALPHA *= smoothstep(distance_fade_max, distance_fade_min, dist_cam);
	ALPHA *= smoothstep(near_fade_min, near_fade_max, dist_cam);
#endif
#ifdef FOAM_FADE
	foam_fade = smoothstep(foam_fade_max, foam_fade_min, dist_cam);
#endif

	if (ALPHA <= 0.0) discard;

	METALLIC  = metallic;
	SPECULAR  = specular;
	ROUGHNESS = roughness;

	vec4 albedo_tex;
#ifdef WORLD_TRIPLANAR
	albedo_tex = triplanar_texture(texture_albedo, uv_power_normal, uv_tri);
#else
	albedo_tex = texture(texture_albedo, UV);
#endif

#ifdef FRESNEL
	float fresnel_fac = fresnel(3.0, NORMAL, VIEW);
	vec4 surface_color = mix(albedo, albedo_fresnel, fresnel_fac);
#else
	vec4 surface_color = albedo;
#endif

	ALBEDO = surface_color.rgb * albedo_tex.rgb;
	ALPHA *= surface_color.a * albedo_tex.a;

#ifdef FOAM
	vec4 foam_tex;
#ifdef WORLD_TRIPLANAR
	foam_tex = triplanar_texture(texture_foam, uv_power_normal, uv_tri);
#else
	foam_tex = texture(texture_foam, UV);
#endif
	float final_foam = foam_alpha * foam_tex.a * foam_fade;
	// Cap at 0.45 so crests are visible but not stark white
	final_foam = smoothstep(0.0, 1.0, final_foam) * 0.45;
	ALBEDO = mix(ALBEDO, foam_tex.rgb, final_foam);
#endif

	// ── Wake foam ────────────────────────────────────────────────────────────
	{
		float sf = smoothstep(0.5, 6.0, ship_spd_0);
		vec2 uv0 = (world_coordinates.xz - ship_pos_0.xz) / ocean_size_meters + vec2(0.5);
		if (uv0.x >= 0.0 && uv0.x <= 1.0 && uv0.y >= 0.0 && uv0.y <= 1.0) {
			float r = texture(wake_tex_0, uv0).r;
			if (r > 0.6) ALBEDO = mix(ALBEDO, vec3(1.0), clamp(smoothstep(0.6, 1.0, r) * sf * foam_fade, 0.0, 1.0));
		}
	}
	{
		float sf = smoothstep(0.5, 6.0, ship_spd_1);
		vec2 uv1 = (world_coordinates.xz - ship_pos_1.xz) / ocean_size_meters + vec2(0.5);
		if (uv1.x >= 0.0 && uv1.x <= 1.0 && uv1.y >= 0.0 && uv1.y <= 1.0) {
			float r = texture(wake_tex_1, uv1).r;
			if (r > 0.6) ALBEDO = mix(ALBEDO, vec3(1.0), clamp(smoothstep(0.6, 1.0, r) * sf * foam_fade, 0.0, 1.0));
		}
	}
	// ─────────────────────────────────────────────────────────────────────────
}
