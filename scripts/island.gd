extends Node3D

@export var radius:      float = 15.0
@export var peak_height: float = 6.0
@export var num_palms:   int   = 3
@export var island_seed: int   = 0

const RINGS := 12
const SEGS  := 28

## Per-island market prices, generated deterministically from island_seed.
var buy_prices:  Dictionary = {}
var sell_prices: Dictionary = {}

func _ready() -> void:
	add_to_group("island")
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

# ------------------------------------------------------------------
# Terrain height at a normalised radius (0 = centre, 1 = outer edge).
# ------------------------------------------------------------------
func _dome_h(t: float) -> float:
	if t <= 0.75:
		# Smooth quadratic dome above water.
		return peak_height * (1.0 - (t / 0.75) * (t / 0.75))
	else:
		# Slopes below the waterline so the skirt is hidden by the ocean.
		return -peak_height * (t - 0.75) / 0.25

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
		var base_h := _dome_h(t)
		var row: Array[Vector3] = []
		for seg in range(SEGS):
			var angle   := float(seg) / float(SEGS) * TAU
			# Add per-vertex noise that fades toward the shore.
			var nr := r * (1.0 + rng.randf_range(-0.18, 0.18) * sqrt(t))
			var nh := base_h + rng.randf_range(-0.5, 0.5) * (1.0 - t) * peak_height * 0.3
			row.append(Vector3(cos(angle) * nr, nh, sin(angle) * nr))
		verts.append(row)

	# Apex to first ring (fan).
	var apex := Vector3(0.0, peak_height * (1.0 + rng.randf_range(0.0, 0.12)), 0.0)
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

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.62, 0.44)   # sandy rock

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

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
		var base_h := _dome_h(t_norm)
		_add_palm(Vector3(cos(angle) * dist, base_h, sin(angle) * dist), rng)

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
