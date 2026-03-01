extends Node3D

@export var good: String = "Rum"
@export var amount: int = 1
@export var pickup_radius: float = 4.0
@export var waterline_offset: float = 0.0
@export var draft: float = 0.34
@export var sample_radius: float = 0.52
@export var bob_lerp: float = 7.0
@export var tilt_lerp: float = 5.0
@export var drift_strength: float = 1.0
@export var spin_speed: float = 0.55

var _ocean: Node = null
var _half_height: float = 0.36


func _ready() -> void:
	add_to_group("floating_crate")
	_ocean = get_tree().get_first_node_in_group("ocean")
	if good.is_empty():
		good = Economy.GOODS[0]
	amount = max(1, amount)
	var crate_mi := get_node_or_null("Crate") as MeshInstance3D
	if crate_mi != null and crate_mi.mesh != null:
		_half_height = max(0.05, crate_mi.mesh.get_aabb().size.y * 0.5 * crate_mi.scale.y)


func _process(delta: float) -> void:
	_update_floating_motion(delta)
	_try_pickup()


func _update_floating_motion(delta: float) -> void:
	if _ocean != null and _ocean.has_method("get_wave_height"):
		var center := global_position
		var p_f := center + Vector3(0.0, 0.0, -sample_radius)
		var p_b := center + Vector3(0.0, 0.0, sample_radius)
		var p_l := center + Vector3(-sample_radius, 0.0, 0.0)
		var p_r := center + Vector3(sample_radius, 0.0, 0.0)
		p_f.y = float(_ocean.call("get_wave_height", p_f))
		p_b.y = float(_ocean.call("get_wave_height", p_b))
		p_l.y = float(_ocean.call("get_wave_height", p_l))
		p_r.y = float(_ocean.call("get_wave_height", p_r))

		var avg_y: float = (p_f.y + p_b.y + p_l.y + p_r.y) * 0.25
		var target_y: float = avg_y + (_half_height - draft) + waterline_offset
		global_position.y = lerp(global_position.y, target_y, clamp(bob_lerp * delta, 0.0, 1.0))

		var fwd_slope := (p_f - p_b).normalized()
		var right_slope := (p_r - p_l).normalized()
		var target_up := right_slope.cross(fwd_slope).normalized()
		var new_up := transform.basis.y.lerp(target_up, clamp(tilt_lerp * delta, 0.0, 1.0)).normalized()
		var cur_fwd := -transform.basis.z
		var new_right := cur_fwd.cross(new_up).normalized()
		var final_fwd := new_up.cross(new_right).normalized()
		transform.basis = Basis(new_right, new_up, -final_fwd)

	if _ocean != null and _ocean.has_method("get_wave_velocity_xz"):
		var flow_any = _ocean.call("get_wave_velocity_xz", global_position)
		if flow_any is Vector2:
			var flow: Vector2 = flow_any
			global_position.x += flow.x * drift_strength * delta
			global_position.z += flow.y * drift_strength * delta
	rotate_y(spin_speed * delta)


func _try_pickup() -> void:
	if amount <= 0:
		queue_free()
		return

	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if n.get("health") == null or float(n.health) <= 0.0:
			continue
		if not n.has_method("free_pickup"):
			continue
		if global_position.distance_to(n.global_position) > pickup_radius:
			continue
		var picked: int = int(n.call("free_pickup", good, amount))
		if picked <= 0:
			continue
		amount -= picked
		if amount <= 0:
			queue_free()
		return
