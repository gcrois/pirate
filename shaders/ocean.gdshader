shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.05, 0.52, 0.68, 1.0);
uniform vec4 deep_color    : source_color = vec4(0.01, 0.12, 0.32, 1.0);
uniform float wave_height : hint_range(0.0, 4.0) = 0.8;
uniform float wave_speed  : hint_range(0.0, 5.0) = 1.0;
uniform float wave_scale  : hint_range(0.0, 2.0) = 0.25;
uniform float roughness   : hint_range(0.0, 1.0) = 0.04;

// ======= MULTI-SHIP SUPPORT (Explicit Uniforms) =======
uniform vec3 ship_pos_0;
uniform vec3 ship_pos_1;
uniform float ship_spd_0;
uniform float ship_spd_1;
uniform float ship_len_0;
uniform float ship_len_1;
uniform float ship_wid_0;
uniform float ship_wid_1;
uniform sampler2D wake_tex_0;
uniform sampler2D wake_tex_1;

uniform float ocean_size_meters = 100.0;
uniform float wake_max_displacement = 4.0;
// ===================================

// Bow wave — scalable
uniform float bow_wave_depth : hint_range(0.0, 4.0) = 1.8;
uniform float bow_v_angle    : hint_range(0.1, 1.0) = 0.4;

// Kelvin wake — scalable
uniform float wake_length    : hint_range(0.0, 200.0) = 60.0;
uniform float wake_amplitude : hint_range(0.0, 2.0)   = 0.5;
uniform float wake_frequency : hint_range(0.0, 2.0)   = 0.28;

// Expanding ring ripples (inner mesh only — set 0 on outer)
uniform float ring_frequency : hint_range(0.0, 3.0)  = 0.5;
uniform float ring_speed     : hint_range(0.0, 30.0) = 10.0;
uniform float ring_decay     : hint_range(1.0, 60.0) = 18.0;
uniform float ring_amplitude : hint_range(0.0, 1.0)  = 0.25;

// Inner mesh edge fade
uniform float edge_fade_radius : hint_range(0.0, 200.0) = 0.0;
uniform int follow_ship_index = 0; // 0 for ship_pos_0, 1 for ship_pos_1

varying float v_wave_h;
varying vec3  v_world_pos;
varying vec2  v_wave_local;   // (along, lateral) in movement-direction space

// ── Base ocean (mirrored in ocean.gd) ───────────────────────────────────────
float get_wave(vec2 p, float t) {
	float s = wave_scale;
	float h = wave_height;
	float w = 0.0;
	w += sin(dot(vec2( 0.800,  0.600), p) * s * 1.00 + t * 1.00) * h * 1.000;
	w += sin(dot(vec2( 0.980,  0.200), p) * s * 1.60 + t * 0.80) * h * 0.600;
	w += sin(dot(vec2( 0.195,  0.981), p) * s * 2.20 + t * 1.30) * h * 0.350;
	w += sin(dot(vec2(-0.686,  0.728), p) * s * 3.80 + t * 2.00) * h * 0.180;
	w += sin(dot(vec2( 0.530, -0.848), p) * s * 6.50 + t * 2.60) * h * 0.090;
	w += sin(dot(vec2(-0.978,  0.208), p) * s * 10.0 + t * 1.50) * h * 0.045;
	return w;
}

// ── Expanding hull ripples ────────────────────────────────────────────────────
float get_rings(float dist, float speed_fac) {
	if (ring_amplitude < 0.001 || dist < 0.5 || dist > ring_decay * 2.5) return 0.0;
	float ring  = sin(dist * ring_frequency * TAU - TIME * ring_speed);
	float decay = exp(-dist / ring_decay);
	return ring * decay * ring_amplitude * speed_fac;
}

// ────────────────────────────────────────────────────────────────────────────
void vertex() {
	float t     = TIME * wave_speed;
	vec3 world  = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world;

	float h         = get_wave(world.xz, t);
	VERTEX.y += h;
	v_wave_h   = h;

	// --- WAKE 0 ---
	{
		float speed_fac = smoothstep(0.5, 6.0, ship_spd_0);
		float d = length(world.xz - ship_pos_0.xz);
		VERTEX.y += get_rings(d, speed_fac);
		
		vec2 diff = world.xz - ship_pos_0.xz;
		vec2 wake_uv = (diff / ocean_size_meters) + vec2(0.5, 0.5);
		if (wake_uv.x >= 0.0 && wake_uv.x <= 1.0 && wake_uv.y >= 0.0 && wake_uv.y <= 1.0) {
			vec4 wake_data = texture(wake_tex_0, wake_uv);
			if (wake_data.r > 0.05) {
				VERTEX.y += (wake_data.r - 0.5) * wake_max_displacement;
			}
		}
	}
	
	// --- WAKE 1 ---
	{
		float speed_fac = smoothstep(0.5, 6.0, ship_spd_1);
		float d = length(world.xz - ship_pos_1.xz);
		VERTEX.y += get_rings(d, speed_fac);
		
		vec2 diff = world.xz - ship_pos_1.xz;
		vec2 wake_uv = (diff / ocean_size_meters) + vec2(0.5, 0.5);
		if (wake_uv.x >= 0.0 && wake_uv.x <= 1.0 && wake_uv.y >= 0.0 && wake_uv.y <= 1.0) {
			vec4 wake_data = texture(wake_tex_1, wake_uv);
			if (wake_data.r > 0.05) {
				VERTEX.y += (wake_data.r - 0.5) * wake_max_displacement;
			}
		}
	}

	float eps = 0.4;
	float hL  = get_wave(world.xz + vec2(-eps, 0.0), t);
	float hR  = get_wave(world.xz + vec2( eps, 0.0), t);
	float hD  = get_wave(world.xz + vec2(0.0, -eps), t);
	float hU  = get_wave(world.xz + vec2(0.0,  eps), t);
	NORMAL = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
}

// ────────────────────────────────────────────────────────────────────────────
void fragment() {
	float fresnel   = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3  water_col = mix(deep_color.rgb, shallow_color.rgb, fresnel);

	// Base wave foam on crests
	float total_foam = smoothstep(wave_height * 1.3, wave_height * 2.1, v_wave_h);
	
	// --- FOAM 0 ---
	{
		float speed_fac = smoothstep(0.5, 6.0, ship_spd_0);
		vec2 wake_diff = v_world_pos.xz - ship_pos_0.xz;
		vec2 wake_uv = (wake_diff / ocean_size_meters) + vec2(0.5, 0.5);
		if (wake_uv.x >= 0.0 && wake_uv.x <= 1.0 && wake_uv.y >= 0.0 && wake_uv.y <= 1.0) {
			vec4 wake_data = texture(wake_tex_0, wake_uv);
			if (wake_data.r > 0.6) {
				total_foam += smoothstep(0.6, 1.0, wake_data.r) * speed_fac * 2.0;
			}
		}
	}
	
	// --- FOAM 1 ---
	{
		float speed_fac = smoothstep(0.5, 6.0, ship_spd_1);
		vec2 wake_diff = v_world_pos.xz - ship_pos_1.xz;
		vec2 wake_uv = (wake_diff / ocean_size_meters) + vec2(0.5, 0.5);
		if (wake_uv.x >= 0.0 && wake_uv.x <= 1.0 && wake_uv.y >= 0.0 && wake_uv.y <= 1.0) {
			vec4 wake_data = texture(wake_tex_1, wake_uv);
			if (wake_data.r > 0.6) {
				total_foam += smoothstep(0.6, 1.0, wake_data.r) * speed_fac * 2.0;
			}
		}
	}
	
	total_foam = clamp(total_foam, 0.0, 1.0);

	ALBEDO    = mix(water_col, vec3(1.0), total_foam);
	ROUGHNESS = roughness;
	METALLIC  = 0.0;
	SPECULAR  = 0.9;
	ALPHA     = mix(0.62, 0.96, fresnel);

	// Inner mesh edge fade
	if (edge_fade_radius > 0.0) {
		vec3 center = (follow_ship_index == 1) ? ship_pos_1 : ship_pos_0;
		float dist = length(v_world_pos.xz - center.xz);
		ALPHA *= smoothstep(edge_fade_radius, edge_fade_radius * 0.6, dist);
	}
}
