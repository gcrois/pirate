extends Node3D

var _owner = null
var _faction: String = ""
var _velocity: Vector3 = Vector3.ZERO
var _damage: float = 0.0
var _max_distance: float = 220.0
var _traveled: float = 0.0
var _life: float = 16.0
var _gravity: float = 10.0
var _seafloor: Node = null

@export var hit_radius: float = 2.8
@export var seabed_hit_padding: float = 0.18
@export var min_world_y: float = -40.0


func setup(
	owner,
	origin: Vector3,
	velocity: Vector3,
	damage: float,
	faction: String,
	max_distance: float,
	gravity: float = 10.0
) -> void:
	_owner = owner
	_velocity = velocity
	_damage = damage
	_faction = faction
	_max_distance = max_distance
	_gravity = max(0.0, gravity)
	if is_inside_tree():
		global_position = origin
	else:
		position = origin


func _ready() -> void:
	add_to_group("projectile")
	_seafloor = get_tree().get_first_node_in_group("seafloor")
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.44
	sphere.height = 0.88
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
	mat.roughness = 0.35
	mi.mesh = sphere
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	var prev_pos: Vector3 = global_position
	_velocity.y -= _gravity * delta
	var step: Vector3 = _velocity * delta
	global_position += step
	_traveled += step.length()
	_life -= delta
	if _life <= 0.0 or _traveled >= _max_distance:
		queue_free()
		return
	_check_hits_segment(prev_pos, global_position)
	if _hits_seabed(prev_pos, global_position):
		queue_free()
		return
	if global_position.y <= min_world_y:
		queue_free()
		return


func _check_hits_segment(start_pos: Vector3, end_pos: Vector3) -> void:
	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if n == _owner:
			continue
		if n.get("health") == null:
			continue
		if str(n.get("faction")) == _faction:
			continue
		if float(n.health) <= 0.0:
			continue
		var center: Vector3 = n.global_position + Vector3.UP * 0.6
		var target_radius: float = 1.35
		var actor_type: String = str(n.get("actor_type"))
		if actor_type == "surfboard" and n.get("collision_radius_surfboard") != null:
			target_radius = float(n.get("collision_radius_surfboard"))
		elif n.get("collision_radius_ship") != null:
			target_radius = float(n.get("collision_radius_ship"))
		var total_radius: float = hit_radius + target_radius * 0.55
		if _distance_to_segment(center, start_pos, end_pos) > total_radius:
			continue
		if n.has_method("apply_damage"):
			n.apply_damage(_damage, _owner)
		queue_free()
		return


func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.000001:
		return point.distance_to(a)
	var t: float = clamp((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _sample_seabed_height(world_pos: Vector3) -> float:
	if _seafloor != null and _seafloor.has_method("get_height_at"):
		var h_any = _seafloor.call("get_height_at", world_pos.x, world_pos.z)
		if h_any is float or h_any is int:
			return float(h_any)
	return -INF


func _hits_seabed(start_pos: Vector3, end_pos: Vector3) -> bool:
	var floor_start: float = _sample_seabed_height(start_pos)
	var floor_end: float = _sample_seabed_height(end_pos)
	if floor_end == -INF:
		return false
	var s_clear: float = start_pos.y - (floor_start + seabed_hit_padding)
	var e_clear: float = end_pos.y - (floor_end + seabed_hit_padding)
	return e_clear <= 0.0 or (s_clear > 0.0 and e_clear <= 0.0)
