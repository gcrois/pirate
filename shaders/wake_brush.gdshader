shader_type canvas_item;

uniform vec3 ship_position = vec3(0.0);
uniform mat3 ship_basis = mat3(1.0);
uniform vec3 ship_velocity = vec3(0.0);
uniform float ship_speed = 0.0;
uniform float ocean_size_meters = 100.0;

uniform float ship_half_length = 4.5;
uniform float ship_half_width = 1.75;
uniform float ship_draft = 1.0;


vec2 world_to_local_xz(vec2 world_xz) {
	vec3 to_pixel = vec3(world_xz.x - ship_position.x, 0.0, world_xz.y - ship_position.z);
	vec3 local = transpose(ship_basis) * to_pixel;
	return local.xz;
}


float hull_norm(vec2 local_xz) {
	float hw = max(ship_half_width, 0.05);
	float hl = max(ship_half_length, 0.05);
	vec2 q = vec2(local_xz.x / hw, local_xz.y / hl);
	return length(q);
}


void fragment() {
	vec2 world_xz = ship_position.xz + (UV - vec2(0.5)) * ocean_size_meters;
	vec2 local_xz = world_to_local_xz(world_xz);
	float n = hull_norm(local_xz);

	float speed_fac = clamp(ship_speed / 7.5, 0.0, 1.0);
	float draft_fac = clamp(ship_draft / 1.2, 0.2, 1.6);

	// Inside-hull trench (dark displacement) so the whole hull footprint interacts.
	float inside = 1.0 - smoothstep(0.95, 1.10, n);
	float trench = inside * (0.10 + 0.34 * (1.0 - clamp(n * n, 0.0, 1.0))) * draft_fac;

	// Around-hull pressure (white displacement): bow + sides.
	float hull_band = 1.0 - smoothstep(0.90, 1.45, n);
	float bow = smoothstep(0.40, -1.10, local_xz.y / max(ship_half_length, 0.05)); // -Z is bow
	float side = smoothstep(0.25, 1.0, abs(local_xz.x) / max(ship_half_width, 0.05));
	float pressure = hull_band * speed_fac * (0.16 + 0.52 * bow + 0.22 * side);

	// Very short stern stamp only; feedback/advection should build the long, curved wake.
	// Painting an extended trail in ship-local space each frame visually "snaps" wake to heading.
	float stern_center = ship_half_length * 1.03;
	float stern_axial = abs(local_xz.y - stern_center);
	float stern_band = 1.0 - smoothstep(ship_half_length * 0.06, ship_half_length * 0.34, stern_axial);
	float stern_width = 1.0 - smoothstep(ship_half_width * 0.15, ship_half_width * 1.25, abs(local_xz.x));

	// Twin stern vortices where prop/water exits hull.
	float v_l = 1.0 - smoothstep(
		ship_half_width * 0.18,
		ship_half_width * 0.95,
		length(local_xz - vec2(-ship_half_width * 0.68, stern_center))
	);
	float v_r = 1.0 - smoothstep(
		ship_half_width * 0.18,
		ship_half_width * 0.95,
		length(local_xz - vec2(ship_half_width * 0.68, stern_center))
	);
	float trail = speed_fac * (stern_band * stern_width * 0.26 + (v_l + v_r) * 0.30);

	float displacement = pressure + trail - trench;
	float target = clamp(0.5 + displacement, 0.0, 1.0);
	float influence = max(inside, max(hull_band * 0.75, trail));

	if (influence < 0.001) {
		COLOR = vec4(0.5, 0.5, 0.5, 0.0);
	} else {
		COLOR = vec4(target, target, target, clamp(influence, 0.0, 1.0));
	}
}
