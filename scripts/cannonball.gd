extends Node3D

var _owner = null
var _faction: String = ""
var _velocity: Vector3 = Vector3.ZERO
var _damage: float = 0.0
var _max_distance: float = 220.0
var _traveled: float = 0.0
var _life: float = 16.0

@export var hit_radius: float = 2.8


func setup(owner, origin: Vector3, velocity: Vector3, damage: float, faction: String, max_distance: float) -> void:
	_owner = owner
	_velocity = velocity
	_damage = damage
	_faction = faction
	_max_distance = max_distance
	if is_inside_tree():
		global_position = origin
	else:
		position = origin


func _ready() -> void:
	add_to_group("projectile")
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
	var step: Vector3 = _velocity * delta
	global_position += step
	_traveled += step.length()
	_life -= delta
	if _life <= 0.0 or _traveled >= _max_distance:
		queue_free()
		return
	_check_hits()


func _check_hits() -> void:
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
		if global_position.distance_to(center) > hit_radius:
			continue
		if n.has_method("apply_damage"):
			n.apply_damage(_damage, _owner)
		queue_free()
		return
