extends MeshInstance3D

const _SEAFLOOR_DEBUG_SHADER := preload("res://shaders/seafloor_debug.gdshader")

@export var world_extent: float = 650.0
@export var resolution: int = 220
@export var base_depth: float = -4.8
@export var height_scale: float = 3.0
@export var noise_scale: float = 0.011
@export var detail_height_scale: float = 1.1
@export var detail_noise_scale: float = 0.065
@export var noise_seed: int = 424242
@export var shore_falloff_start: float = 360.0
@export var shore_falloff_end: float = 620.0
@export var world_edge_extra_depth: float = 20.0
@export var island_shelf_inner_scale: float = 0.95
@export var island_shelf_radius_scale: float = 1.24
@export var island_shelf_lift: float = 4.8
@export var island_shelf_noise_strength: float = 0.55

var _noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _island_cache: Array = []


func _ready() -> void:
	add_to_group("seafloor")
	_configure_noise()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 24.0
	call_deferred("_deferred_build")


func _deferred_build() -> void:
	_cache_islands()
	_build_mesh()


func _configure_noise() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = noise_scale
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.54

	_detail_noise.seed = noise_seed + 911
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = detail_noise_scale
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_lacunarity = 2.1
	_detail_noise.fractal_gain = 0.5


func get_base_height_at(x: float, z: float) -> float:
	var n: float = _noise.get_noise_2d(x, z)
	var nd: float = _detail_noise.get_noise_2d(x, z)
	var micro: float = _detail_noise.get_noise_2d(x * 2.6 + 113.0, z * 2.6 - 71.0)
	var h: float = base_depth + n * height_scale + nd * detail_height_scale + micro * 0.85
	var d: float = Vector2(x, z).length()
	var edge_t: float = smoothstep(shore_falloff_start, shore_falloff_end, d)
	return lerp(h, base_depth - world_edge_extra_depth, edge_t)


func get_height_at(x: float, z: float) -> float:
	return _height_with_shelves(x, z, null)


func get_height_at_excluding_island(x: float, z: float, excluded_island: Node3D) -> float:
	return _height_with_shelves(x, z, excluded_island)


func _height_with_shelves(x: float, z: float, excluded_island: Node3D) -> float:
	var h: float = get_base_height_at(x, z)
	var world_xz := Vector2(x, z)
	for island in _get_islands():
		if island is not Node3D:
			continue
		if island == excluded_island:
			continue
		var center := Vector2(island.global_position.x, island.global_position.z)
		var radius: float = float(island.get("radius"))
		var peak_h: float = float(island.get("peak_height"))
		var inner_r: float = max(radius * island_shelf_inner_scale, radius * 0.90)
		var radial := world_xz - center
		var dir := radial.normalized()
		if radial.length_squared() < 0.0001:
			dir = Vector2.RIGHT
		var shelf_edge_jitter: float = _noise.get_noise_2d(center.x + dir.x * 21.0, center.y + dir.y * 21.0)
		var shelf_r: float = max(radius * island_shelf_radius_scale * (1.0 + shelf_edge_jitter * 0.16), inner_r + 1.0)
		var d_island := radial.length()
		if d_island <= inner_r:
			continue
		if d_island >= shelf_r:
			continue
		var shelf_band: float = clamp((d_island - inner_r) / max(0.001, shelf_r - inner_r), 0.0, 1.0)
		var influence: float = 1.0 - smoothstep(0.0, 1.0, shelf_band)
		var shelf_noise: float = _noise.get_noise_2d(x * 0.10 + center.x * 0.02, z * 0.10 - center.y * 0.02)
		shelf_noise += _detail_noise.get_noise_2d(x * 0.34 - center.x * 0.05, z * 0.34 + center.y * 0.05) * 0.65
		var lift: float = (island_shelf_lift + peak_h * 0.06) * influence
		lift += shelf_noise * island_shelf_noise_strength * influence
		h += max(lift, 0.0)
		h += _detail_noise.get_noise_2d(x * 0.92 + 91.0, z * 0.92 - 47.0) * influence * 0.95

	return h


func _build_mesh() -> void:
	var steps: int = max(24, resolution)
	var span: float = world_extent * 2.0
	var verts_per_row: int = steps + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(verts_per_row):
		for x in range(verts_per_row):
			var uv := Vector2(float(x) / float(steps), float(z) / float(steps))
			st.set_uv(uv)
			st.add_vertex(_vertex_at(x, z, steps, span))

	for z in range(steps):
		for x in range(steps):
			var i0: int = z * verts_per_row + x
			var i1: int = i0 + 1
			var i2: int = i0 + verts_per_row
			var i3: int = i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)

	st.generate_normals()
	mesh = st.commit()

	var mat := ShaderMaterial.new()
	mat.shader = _SEAFLOOR_DEBUG_SHADER
	var min_h: float = base_depth - world_edge_extra_depth - (height_scale + detail_height_scale + 2.0)
	var max_h: float = base_depth + island_shelf_lift + 10.0
	mat.set_shader_parameter("min_height", min_h)
	mat.set_shader_parameter("max_height", max_h)
	material_override = mat


func _vertex_at(ix: int, iz: int, steps: int, span: float) -> Vector3:
	var fx: float = float(ix) / float(steps)
	var fz: float = float(iz) / float(steps)
	var x: float = -world_extent + fx * span
	var z: float = -world_extent + fz * span
	var y: float = get_height_at(x, z)
	return Vector3(x, y, z)


func _cache_islands() -> void:
	_island_cache = get_tree().get_nodes_in_group("island")


func _get_islands() -> Array:
	if _island_cache.is_empty():
		return get_tree().get_nodes_in_group("island")
	return _island_cache
