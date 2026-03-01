extends Node3D

@export var radius:      float = 15.0
@export var peak_height: float = 6.0
@export var num_palms:   int   = 3
@export var island_seed: int   = 0
@export var shoreline_lift: float = 0.05

const RINGS := 14
const SEGS  := 36

## Per-island market prices, generated deterministically from island_seed.
var buy_prices:  Dictionary = {}
var sell_prices: Dictionary = {}
var _seafloor: Node = null

func _ready() -> void:
	add_to_group("island")
	_seafloor = get_tree().get_first_node_in_group("seafloor")
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed
	_build_terrain(rng)
	_build_palms(rng)
	_build_market(rng)

func _build_market(rng: RandomNumberGenerator) -> void:
	for good in Economy.GOODS:
		var base: int = Economy.BASE_PRICES[good]
		buy_prices[good]  = max(10, int(base * rng.randf_range(0.85, 1.55)))
		sell_prices[good] = max(5,  int(buy_prices[good] * rng.randf_range(0.60, 0.82)))

func _sample_seafloor_height(world_xz: Vector2) -> float:
	if _seafloor != null:
		if _seafloor.has_method("get_height_at_excluding_island"):
			var h_ex = _seafloor.call("get_height_at_excluding_island", world_xz.x, world_xz.y, self)
			if h_ex is float or h_ex is int:
				return float(h_ex)
		if _seafloor.has_method("get_height_at"):
			var h_any = _seafloor.call("get_height_at", world_xz.x, world_xz.y)
			if h_any is float or h_any is int:
				return float(h_any)
		if _seafloor.has_method("get_base_height_at"):
			var h_base = _seafloor.call("get_base_height_at", world_xz.x, world_xz.y)
			if h_base is float or h_base is int:
				return float(h_base)
	return -7.0


func _island_rise(t: float) -> float:
	if t <= 0.70:
		var u: float = t / 0.70
		return lerp(peak_height + 2.4, 0.9, u * u)
	var v: float = (t - 0.70) / 0.30
	var s: float = v * v * (3.0 - 2.0 * v)
	# Resolve almost flat at shoreline so island and seafloor blend continuously.
	return lerp(0.9, shoreline_lift, s)


func _terrain_height_local(local_xz: Vector2, t_norm: float) -> float:
	var world_xz := Vector2(global_position.x + local_xz.x, global_position.z + local_xz.y)
	var seabed: float = _sample_seafloor_height(world_xz)
	return seabed + _island_rise(t_norm)

# ------------------------------------------------------------------
# Build the island terrain mesh with SurfaceTool.
# ------------------------------------------------------------------
func _build_terrain(rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build concentric rings of vertices.
	# verts[ring][seg] – ring 0 is innermost.
	var verts: Array = []
	for ring in range(RINGS):
		var t      := float(ring + 1) / float(RINGS)
		var r      := radius * t
		var row: Array[Vector3] = []
		for seg in range(SEGS):
			var angle   := float(seg) / float(SEGS) * TAU
			# Fade shoreline distortion to zero at the edge so island and seabed join cleanly.
			var shoreline_noise: float = 0.16 * pow(max(0.0, 1.0 - t), 0.65)
			var nr := r * (1.0 + rng.randf_range(-1.0, 1.0) * shoreline_noise)
			var local_xz := Vector2(cos(angle) * nr, sin(angle) * nr)
			var nh := _terrain_height_local(local_xz, t)
			nh += rng.randf_range(-0.5, 0.5) * pow(max(0.0, 1.0 - t), 1.2) * peak_height * 0.20
			row.append(Vector3(local_xz.x, nh, local_xz.y))
		verts.append(row)

	# Apex to first ring (fan).
	var center_h: float = _terrain_height_local(Vector2.ZERO, 0.0)
	var apex := Vector3(0.0, center_h + peak_height * 0.20 * (1.0 + rng.randf_range(0.0, 0.16)), 0.0)
	for seg in range(SEGS):
		var nxt := (seg + 1) % SEGS
		_tri(st, apex, verts[0][seg], verts[0][nxt])

	# Ring-to-ring quads.
	for ring in range(RINGS - 1):
		for seg in range(SEGS):
			var nxt := (seg + 1) % SEGS
			var a: Vector3 = verts[ring][seg]
			var b: Vector3 = verts[ring][nxt]
			var c: Vector3 = verts[ring + 1][seg]
			var d: Vector3 = verts[ring + 1][nxt]
			_tri(st, a, d, b)
			_tri(st, a, c, d)

	st.generate_normals()

	var mat := _build_island_material()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _build_island_material() -> Material:
	if _seafloor is MeshInstance3D:
		var floor_mat := (_seafloor as MeshInstance3D).material_override
		if floor_mat != null:
			return floor_mat

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.63, 0.45)
	mat.roughness = 0.99
	mat.metallic = 0.0
	return mat

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

# ------------------------------------------------------------------
# Scatter palm trees on the upper dome.
# ------------------------------------------------------------------
func _build_palms(rng: RandomNumberGenerator) -> void:
	for _i in range(num_palms):
		var angle  := rng.randf() * TAU
		var t_norm := rng.randf_range(0.0, 0.55)   # keep palms away from shore
		var dist   := radius * t_norm
		var local_xz := Vector2(cos(angle) * dist, sin(angle) * dist)
		var base_h := _terrain_height_local(local_xz, t_norm)
		_add_palm(Vector3(local_xz.x, base_h, local_xz.y), rng)

func _add_palm(base: Vector3, rng: RandomNumberGenerator) -> void:
	var trunk_h  := rng.randf_range(4.5, 8.0)
	var lean     := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))

	# Trunk
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius    = 0.12
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height        = trunk_h

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.40, 0.27, 0.13)

	var trunk_mi := MeshInstance3D.new()
	trunk_mi.mesh              = trunk_mesh
	trunk_mi.material_override = trunk_mat
	trunk_mi.position          = base + Vector3(0.0, trunk_h * 0.5, 0.0)
	trunk_mi.rotation          = lean
	add_child(trunk_mi)

	# Leaf crown
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 2.4
	crown_mesh.height = 1.6

	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.10, 0.48, 0.16)

	var crown_mi := MeshInstance3D.new()
	crown_mi.mesh              = crown_mesh
	crown_mi.material_override = crown_mat
	crown_mi.position          = base + Vector3(0.0, trunk_h + 0.6, 0.0)
	add_child(crown_mi)
