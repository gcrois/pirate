class_name Actor
extends Node3D

const CANNONBALL_SCRIPT = preload("res://scripts/cannonball.gd")

@export var actor_name:   String = ""
@export var actor_type:   String = "ship"   # "ship" or "surfboard"
@export var is_ai:        bool   = false
@export_enum("player", "enemy", "neutral") var faction: String = "neutral"

@export var max_speed:    float = 10.0
@export var acceleration: float = 8.0
@export var deceleration: float = 5.0
@export var turn_speed:   float = 1.5
@export var bob_lerp:     float = 8.0
@export var tilt_lerp:    float = 3.0
@export var slam_threshold: float = 0.3
@export var slam_drag:      float = 0.4
@export var slam_recover:   float = 3.0
@export var water_drift_strength: float = 0.55

@export_category("Surfboard shape")
@export var surfboard_half_length: float = 1.0
@export var surfboard_half_width:  float = 0.3
@export var surfboard_draft:       float = 0.1

@export_category("Island Anchor")
@export var anchor_zone_scale: float = 1.45
@export var anchor_hard_padding: float = 3.5
@export var anchor_brake: float = 9.0

@export_category("Combat")
@export var max_health: float = 140.0
@export var cannon_range: float = 210.0
@export var cannon_reload: float = 1.8
@export var cannonball_speed: float = 28.0
@export var cannonball_gravity: float = 10.0
@export var min_fire_angle_degrees: float = 10.0
@export var cannon_damage: float = 20.0
@export var cannons_per_side: int = 4
@export var bounty_gold: int = 120
@export var trajectory_preview_seconds: float = 2.8
@export var trajectory_preview_steps: int = 28
@export var trajectory_width_start: float = 0.95
@export var trajectory_width_end: float = 0.14
@export var trajectory_alpha: float = 0.82
@export var target_side_threshold: float = 8.0
@export var target_longitudinal_factor: float = 0.92
@export var collision_radius_ship: float = 2.25
@export var collision_radius_surfboard: float = 1.05
@export var collision_damage_base: float = 16.0
@export var collision_damage_speed_scale: float = 1.6
@export var collision_damage_max: float = 56.0
@export var collision_cooldown: float = 0.85

@onready var _bow:       Marker3D = $Bow
@onready var _stern:     Marker3D = $Stern
@onready var _port:      Marker3D = $Port
@onready var _starboard: Marker3D = $Starboard

# Per-actor inventory & wallet
var inventory: Dictionary = {}
@export var max_inventory: int = 6
@export var gold: int = 200

var _ocean:         Node
var _current_drag:  float = 1.0
var _current_speed: float = 0.0
var _anchor_factor: float = 1.0
var _reload_port: float = 0.0
var _reload_starboard: float = 0.0
var _spawn_pos: Vector3
var health: float = 0.0
var _upgrade_levels: Dictionary = {"hull": 0, "cannons": 0, "reload": 0, "engine": 0}
var _ai_orbit_sign: float = 1.0
var _shot_profile_index: int = 1
var _collision_cooldowns: Dictionary = {}
var _trajectory_mesh: MeshInstance3D
var _trajectory_material: StandardMaterial3D
var _aim_mode: bool = false
var _aim_solution: Dictionary = {}
var _trajectory_preview_active: bool = false
var _trajectory_focus_world: Vector3 = Vector3.ZERO

var _wake_controller: WakeController

# Public read by DebugOverlay / OceanManager
var velocity:    Vector3 = Vector3.ZERO
var _prev_pos:   Vector3
var _wave_speed: float   = 0.0
var _wake_contact: float = 0.0
var _wake_rel_speed: float = 0.0
var _water_flow_xz: Vector2 = Vector2.ZERO

# Vertical physics
const GRAVITY: float = 9.8
var _vert_vel:  float = 0.0

const _UPGRADE_BASE_COSTS: Dictionary = {
	"hull": 150,
	"cannons": 190,
	"reload": 230,
	"engine": 170,
}

const _UPGRADE_MAX_LEVELS: Dictionary = {
	"hull": 4,
	"cannons": 4,
	"reload": 4,
	"engine": 4,
}

const _SHOT_PROFILES: Array = [
	{"name": "Long", "speed_scale": 1.16, "arc_lift": 0.04, "damage_scale": 0.95},
	{"name": "Balanced", "speed_scale": 1.0, "arc_lift": 0.11, "damage_scale": 1.0},
	{"name": "High Arc", "speed_scale": 0.86, "arc_lift": 0.19, "damage_scale": 1.05},
]

# Cached original ship mesh so we can restore after a surfboard switch
var _orig_hull_mesh: Mesh     = null
var _orig_hull_mat:  Material = null
var _orig_bow_pos:   Vector3
var _orig_stern_pos: Vector3
var _orig_port_pos:  Vector3
var _orig_star_pos:  Vector3


## Try every possible way to get a ShaderMaterial from a MeshInstance3D.
static func _get_shader_material(mi: MeshInstance3D) -> ShaderMaterial:
	if mi.material_override is ShaderMaterial:
		return mi.material_override
	if mi.get_surface_override_material(0) is ShaderMaterial:
		return mi.get_surface_override_material(0)
	if mi.mesh != null and mi.mesh.surface_get_material(0) is ShaderMaterial:
		return mi.mesh.surface_get_material(0)
	if mi.mesh is PrimitiveMesh:
		var pm := mi.mesh as PrimitiveMesh
		if pm.material is ShaderMaterial:
			return pm.material
	return null


func _ready() -> void:
	add_to_group("ship")
	_prev_pos = global_position
	_ocean    = get_tree().get_first_node_in_group("ocean")
	_spawn_pos = global_position
	health = max_health
	if actor_name.is_empty():
		actor_name = name
	if is_ai and faction == "enemy":
		_ai_orbit_sign = -1.0 if int(get_instance_id()) % 2 == 0 else 1.0

	# Initialise per-actor inventory from the shared goods list
	for good in Economy.GOODS:
		inventory[good] = 0

	# Cache original ship geometry so toggling back from surfboard works
	if has_node("Hull"):
		_orig_hull_mesh = $Hull.mesh
		_orig_hull_mat  = $Hull.material_override
	_orig_bow_pos   = _bow.position
	_orig_stern_pos = _stern.position
	_orig_port_pos  = _port.position
	_orig_star_pos  = _starboard.position

	_set_type(actor_type)

	_wake_controller = WakeController.new()
	if _ocean != null and _ocean.get("wake_footprint_meters") != null:
		_wake_controller.ocean_size_meters = float(_ocean.get("wake_footprint_meters"))
	if _ocean != null and _ocean.get("wake_buffer_resolution") != null:
		_wake_controller.viewport_resolution = int(_ocean.get("wake_buffer_resolution"))
	add_child(_wake_controller)
	_setup_trajectory_preview()


func _input(event: InputEvent) -> void:
	if is_ai:
		return
	if event is not InputEventKey:
		return
	if event.physical_keycode == KEY_Q:
		if event.echo:
			return
		_aim_mode = event.pressed
		if not _aim_mode:
			_aim_solution.clear()
			_trajectory_preview_active = false
			if _trajectory_mesh != null:
				_trajectory_mesh.visible = false
		return
	if not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_T:
		_toggle_type()
	elif event.physical_keycode == KEY_SPACE:
		if _aim_mode:
			_try_fire_auto()
	elif event.physical_keycode == KEY_R:
		_cycle_shot_profile()


func _setup_trajectory_preview() -> void:
	_trajectory_mesh = MeshInstance3D.new()
	_trajectory_mesh.name = "TrajectoryPreview"
	_trajectory_mesh.top_level = true
	_trajectory_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trajectory_mesh.visible = false

	_trajectory_material = StandardMaterial3D.new()
	_trajectory_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trajectory_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trajectory_material.albedo_color = Color(1.0, 0.12, 0.12, trajectory_alpha)
	_trajectory_material.emission_enabled = true
	_trajectory_material.emission = Color(1.0, 0.08, 0.08)
	_trajectory_material.emission_energy_multiplier = 2.2
	_trajectory_material.vertex_color_use_as_albedo = true
	_trajectory_material.set_flag(BaseMaterial3D.FLAG_DISABLE_DEPTH_TEST, true)
	_trajectory_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trajectory_mesh.material_override = _trajectory_material
	add_child(_trajectory_mesh)


func _cycle_shot_profile() -> void:
	if _SHOT_PROFILES.is_empty():
		return
	_shot_profile_index = (_shot_profile_index + 1) % _SHOT_PROFILES.size()


func _try_fire_auto() -> void:
	if actor_type != "ship" or health <= 0.0:
		return
	var solution: Dictionary = {}
	if _is_aim_solution_valid(_aim_solution):
		solution = _aim_solution
	else:
		solution = _get_player_fire_solution(false)
	if solution.is_empty():
		return
	var target = solution.get("target", null)
	var side: int = int(solution.get("side", 0))
	if side == 0 or not _is_side_ready(side):
		return
	if side < 0:
		_try_fire_port(target)
	elif side > 0:
		_try_fire_starboard(target)


func _toggle_type() -> void:
	_set_type("surfboard" if actor_type == "ship" else "ship")


func _set_type(type: String) -> void:
	actor_type = type
	if actor_type == "surfboard":
		_bow.position       = Vector3(0, 0, -surfboard_half_length)
		_stern.position     = Vector3(0, 0,  surfboard_half_length)
		_port.position      = Vector3(-surfboard_half_width, 0, 0)
		_starboard.position = Vector3( surfboard_half_width, 0, 0)
		max_speed  = 8.0
		turn_speed = 2.0
		bob_lerp   = 15.0
		tilt_lerp  = 10.0
		if has_node("Cabin"): $Cabin.hide()
		if has_node("Mast"):  $Mast.hide()
		if has_node("Yard"):  $Yard.hide()
		if has_node("Sail"):  $Sail.hide()
		if has_node("Hull"):
			var bm := BoxMesh.new()
			bm.size = Vector3(surfboard_half_width * 2.0, 0.2, surfboard_half_length * 2.0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.2, 0.2)
			$Hull.mesh              = bm
			$Hull.material_override = mat
	else:  # "ship"
		_bow.position       = _orig_bow_pos
		_stern.position     = _orig_stern_pos
		_port.position      = _orig_port_pos
		_starboard.position = _orig_star_pos
		max_speed  = 10.0
		turn_speed = 1.5
		bob_lerp   = 8.0
		tilt_lerp  = 3.0
		if has_node("Cabin"): $Cabin.show()
		if has_node("Mast"):  $Mast.show()
		if has_node("Yard"):  $Yard.show()
		if has_node("Sail"):  $Sail.show()
		if has_node("Hull") and _orig_hull_mesh != null:
			$Hull.mesh              = _orig_hull_mesh
			$Hull.material_override = _orig_hull_mat


func _process(delta: float) -> void:
	_handle_movement(delta)
	_reload_port = max(0.0, _reload_port - delta)
	_reload_starboard = max(0.0, _reload_starboard - delta)
	_handle_combat(delta)
	_handle_buoyancy(delta)
	_apply_water_drift(delta)
	_apply_island_anchor(delta)
	_tick_collision_cooldowns(delta)
	_handle_ship_collisions()
	_update_trajectory_preview()

	velocity  = (global_position - _prev_pos) / delta
	_prev_pos = global_position

	var actual_spd := Vector2(velocity.x, velocity.z).length()
	_wave_speed = lerp(_wave_speed, actual_spd, 4.0 * delta)

	_update_wake(delta)
	_update_crates()


func get_upgrade_level(kind: String) -> int:
	return int(_upgrade_levels.get(kind, 0))


func get_upgrade_cost(kind: String) -> int:
	if not _upgrade_levels.has(kind):
		return -1
	var level: int = int(_upgrade_levels[kind])
	var max_level: int = int(_UPGRADE_MAX_LEVELS.get(kind, 0))
	if level >= max_level:
		return -1
	var base: int = int(_UPGRADE_BASE_COSTS.get(kind, 0))
	return int(round(float(base) * pow(1.7, level)))


func can_upgrade(kind: String) -> bool:
	var cost: int = get_upgrade_cost(kind)
	return cost > 0 and gold >= cost


func apply_upgrade(kind: String) -> bool:
	var cost: int = get_upgrade_cost(kind)
	if cost <= 0 or gold < cost:
		return false

	gold -= cost
	var level: int = int(_upgrade_levels.get(kind, 0)) + 1
	_upgrade_levels[kind] = level

	match kind:
		"hull":
			max_health += 35.0
			health = max_health
		"cannons":
			cannon_damage += 8.0
			cannons_per_side = min(cannons_per_side + 1, 6)
		"reload":
			cannon_reload = max(0.35, cannon_reload * 0.82)
		"engine":
			max_speed += 1.2
			acceleration += 0.9
		_:
			return false
	return true


func apply_damage(amount: float, attacker = null) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = max(0.0, health - amount)
	if health > 0.0:
		return
	_on_sunk(attacker)


func on_kill(victim) -> void:
	if victim == null:
		return
	var bounty: int = int(victim.get("bounty_gold"))
	gold += max(0, bounty)


func _on_sunk(attacker) -> void:
	if attacker != null and attacker.has_method("on_kill"):
		attacker.on_kill(self)

	if is_ai and faction == "enemy":
		queue_free()
		return

	# Player/neutral recovery
	gold = int(floor(float(gold) * 0.8))
	health = max_health
	_current_speed = 0.0
	_vert_vel = 0.0
	global_position = _spawn_pos


func total_inventory() -> int:
	var n := 0
	for v in inventory.values():
		n += v
	return n


func can_buy() -> bool:
	return total_inventory() < max_inventory


func free_pickup(good: String, count: int = 1) -> int:
	if not inventory.has(good):
		return 0
	var remaining: int = max(0, count)
	var collected: int = 0
	while remaining > 0 and can_buy():
		inventory[good] += 1
		remaining -= 1
		collected += 1
	return collected


func buy(good: String, price: int) -> bool:
	if not inventory.has(good):
		return false
	if gold < price or not can_buy():
		return false
	gold -= price
	inventory[good] += 1
	return true


func sell(good: String, price: int) -> bool:
	if not inventory.has(good):
		return false
	if inventory.get(good, 0) <= 0:
		return false
	gold += price
	inventory[good] -= 1
	return true


func _update_crates() -> void:
	var total := total_inventory()
	for i in range(1, 7):
		var c := get_node_or_null("Crate%d" % i)
		if c:
			c.visible = i <= total


func _handle_movement(delta: float) -> void:
	_anchor_factor = _compute_anchor_factor()

	# ── Developer free-fly override (Ctrl / Cmd held) ───────────────────────
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_META):
		var tt := 0.0
		var ts := 0.0
		if Input.is_physical_key_pressed(KEY_UP):    tt =  1.0
		elif Input.is_physical_key_pressed(KEY_DOWN): tt = -1.0
		if Input.is_physical_key_pressed(KEY_LEFT):  ts =  1.0
		elif Input.is_physical_key_pressed(KEY_RIGHT): ts = -1.0

		if tt != 0.0:
			_current_speed += tt * acceleration * delta * 2.0
		else:
			_current_speed = move_toward(_current_speed, 0.0, deceleration * delta)
		if ts != 0.0:
			global_position += transform.basis.x * ts * max_speed * delta
		if abs(_current_speed) > 0.001:
			global_position += -transform.basis.z * _current_speed * delta
		return

	# ── Normal movement ────────────────────────────────────────────────────
	var throttle := 0.0
	var steer    := 0.0

	if is_ai:
		var ai_controls: Vector2 = _get_ai_controls()
		throttle = ai_controls.x
		steer = ai_controls.y
	else:
		# Player movement uses both WASD and arrow keys.
		if   Input.is_physical_key_pressed(KEY_UP)    or Input.is_physical_key_pressed(KEY_W):
			throttle =  1.0
		elif Input.is_physical_key_pressed(KEY_DOWN)  or Input.is_physical_key_pressed(KEY_S):
			throttle = -1.0
		if   Input.is_physical_key_pressed(KEY_LEFT)  or Input.is_physical_key_pressed(KEY_A):
			steer =  1.0
		elif Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
			steer = -1.0

	var anchor_scale := _anchor_factor if throttle >= 0.0 else 1.0
	var target := throttle * max_speed * _current_drag * anchor_scale
	var rate   := acceleration if throttle != 0.0 else deceleration
	_current_speed = move_toward(_current_speed, target, rate * delta)
	if _anchor_factor < 1.0:
		var brake := anchor_brake * (1.0 - _anchor_factor)
		_current_speed = move_toward(_current_speed, 0.0, brake * delta)

	if abs(_current_speed) > 0.001:
		global_position += -transform.basis.z * _current_speed * delta
	if steer != 0.0:
		rotate_y(steer * turn_speed * delta * lerp(0.4, 1.0, _anchor_factor))


func _get_ai_controls() -> Vector2:
	if faction != "enemy":
		return Vector2(0.85, 0.15)

	var target = _get_enemy_target()
	if target == null:
		return Vector2(0.7, 0.2)

	var local: Vector3 = to_local(target.global_position)
	var distance: float = global_position.distance_to(target.global_position)

	var desired_side_x: float = 18.0 * _ai_orbit_sign
	var side_error: float = local.x - desired_side_x

	var steer := 0.0
	if side_error < -3.0:
		steer = 1.0
	elif side_error > 3.0:
		steer = -1.0

	var throttle := 0.9
	if distance > cannon_range * 1.2:
		throttle = 1.0
	elif distance < cannon_range * 0.52:
		throttle = -0.35
	elif distance < cannon_range * 0.75:
		throttle = 0.35

	if abs(local.x) < 6.0:
		steer = -_ai_orbit_sign
	if distance > cannon_range * 1.6:
		steer = clamp(-local.x / 18.0, -1.0, 1.0)
	return Vector2(throttle, steer)


func _get_enemy_target():
	var player_target = _get_player_target()
	if player_target != null:
		return player_target

	var best = null
	var best_dist: float = INF
	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if n == self:
			continue
		if n.get("health") == null or float(n.health) <= 0.0:
			continue
		if str(n.get("faction")) == faction:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d < best_dist:
			best_dist = d
			best = n
	return best


func _get_player_target():
	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if str(n.get("faction")) != "player":
			continue
		if n.get("health") == null or float(n.health) <= 0.0:
			continue
		return n
	return null


func _handle_combat(_delta: float) -> void:
	if faction != "enemy" or not is_ai:
		return
	var target = _get_enemy_target()
	if target == null:
		return
	var dist: float = global_position.distance_to(target.global_position)
	if dist > cannon_range:
		return
	_shot_profile_index = _select_ai_shot_profile(dist)
	var local: Vector3 = _flat_local_of(target.global_position)
	if local.x < -target_side_threshold and abs(local.z) < cannon_range * 0.85:
		_try_fire_port(target)
	elif local.x > target_side_threshold and abs(local.z) < cannon_range * 0.85:
		_try_fire_starboard(target)


func _try_fire_port(target = null) -> void:
	if actor_type != "ship" or health <= 0.0:
		return
	if _reload_port > 0.0:
		return
	_reload_port = cannon_reload
	_fire_broadside(-1, target)


func _try_fire_starboard(target = null) -> void:
	if actor_type != "ship" or health <= 0.0:
		return
	if _reload_starboard > 0.0:
		return
	_reload_starboard = cannon_reload
	_fire_broadside(1, target)


func _fire_broadside(side: int, target = null) -> void:
	var profile: Dictionary = _get_shot_profile()
	var damage_scale: float = float(profile.get("damage_scale", 1.0))
	var shot := _build_broadside_shot(side, 0.0, profile, target)
	var origin: Vector3 = shot["origin"]
	var vel: Vector3 = shot["velocity"]
	_spawn_cannonball(origin, vel, cannon_damage * damage_scale)


func _spawn_cannonball(origin: Vector3, launch_velocity: Vector3, damage_amount: float) -> void:
	var ball = CANNONBALL_SCRIPT.new()
	if ball == null:
		return
	get_tree().current_scene.add_child(ball)
	if ball.has_method("setup"):
		ball.setup(
			self,
			origin,
			launch_velocity,
			damage_amount,
			faction,
			cannon_range * 3.4,
			cannonball_gravity
		)


func _select_ai_shot_profile(distance: float) -> int:
	if distance < cannon_range * 0.45:
		return 2
	if distance > cannon_range * 0.80:
		return 0
	return 1


func _get_shot_profile() -> Dictionary:
	if _SHOT_PROFILES.is_empty():
		return {}
	_shot_profile_index = clamp(_shot_profile_index, 0, _SHOT_PROFILES.size() - 1)
	return _SHOT_PROFILES[_shot_profile_index]


func _is_side_ready(side: int) -> bool:
	return _reload_port <= 0.0 if side < 0 else _reload_starboard <= 0.0


func _flat_local_of(world_pos: Vector3) -> Vector3:
	var forward: Vector3 = -transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var delta: Vector3 = world_pos - global_position
	return Vector3(delta.dot(right), delta.y, delta.dot(forward))


func _is_aim_solution_valid(solution: Dictionary) -> bool:
	if solution.is_empty():
		return false
	var target = solution.get("target", null)
	if target == null or not is_instance_valid(target):
		return false
	if target.get("health") == null or float(target.get("health")) <= 0.0:
		return false
	if str(target.get("faction")) == faction:
		return false
	var side: int = int(solution.get("side", 0))
	if side == 0:
		return false
	var d: float = global_position.distance_to(target.global_position)
	if d > cannon_range:
		return false
	var local: Vector3 = _flat_local_of(target.global_position)
	if abs(local.z) > cannon_range * target_longitudinal_factor:
		return false
	if side < 0 and local.x >= -target_side_threshold:
		return false
	if side > 0 and local.x <= target_side_threshold:
		return false
	return true


func _get_player_fire_solution(require_side_ready: bool = false) -> Dictionary:
	var best_target = null
	var best_side: int = 0
	var best_dist: float = INF
	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if n == self:
			continue
		if n.get("health") == null or float(n.health) <= 0.0:
			continue
		if str(n.get("faction")) == faction:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d > cannon_range:
			continue
		var local: Vector3 = _flat_local_of(n.global_position)
		if abs(local.z) > cannon_range * target_longitudinal_factor:
			continue
		var side: int = 0
		if local.x < -target_side_threshold:
			side = -1
		elif local.x > target_side_threshold:
			side = 1
		if side == 0:
			continue
		if require_side_ready and not _is_side_ready(side):
			continue
		if d < best_dist:
			best_dist = d
			best_target = n
			best_side = side
	if best_target == null:
		return {}
	return {
		"target": best_target,
		"side": best_side,
		"distance": best_dist,
	}


func _build_broadside_shot(side: int, lane_t: float, profile: Dictionary, target = null) -> Dictionary:
	var half_len: float = 4.2
	var half_wid: float = 1.8
	var muzzle: Vector3 = global_position
	muzzle += transform.basis.x * (float(side) * (half_wid + 0.35))
	muzzle += transform.basis.z * (lane_t * half_len * 1.25)
	muzzle += Vector3.UP * 0.45
	var speed: float = cannonball_speed * float(profile.get("speed_scale", 1.0))
	var direction: Vector3 = transform.basis.x * float(side)
	direction += -transform.basis.z * (lane_t * 0.35)
	direction.y += float(profile.get("arc_lift", 0.1))
	direction = direction.normalized()
	var launch_velocity: Vector3 = direction * speed

	var target_pos: Vector3 = Vector3.ZERO
	var has_target: bool = false
	if target != null and target.get("global_position") != null:
		target_pos = target.global_position + Vector3.UP * 0.6
		has_target = true
		if target.get("velocity") is Vector3:
			var tv: Vector3 = target.get("velocity")
			var rough_time: float = muzzle.distance_to(target_pos) / max(speed, 0.01)
			target_pos += tv * clamp(rough_time, 0.0, 2.5)

	if has_target:
		var prefer_high_arc: bool = float(profile.get("arc_lift", 0.1)) >= 0.14
		var solved_velocity: Vector3 = _solve_ballistic_velocity(muzzle, target_pos, speed, prefer_high_arc)
		if solved_velocity.length_squared() > 0.0001:
			launch_velocity = solved_velocity
		else:
			var direct := (target_pos - muzzle).normalized()
			launch_velocity = direct * speed
	launch_velocity = _enforce_min_fire_angle(launch_velocity, side)

	return {
		"origin": muzzle,
		"velocity": launch_velocity,
		"target_pos": target_pos,
		"has_target": has_target,
	}


func _solve_ballistic_velocity(origin: Vector3, target_pos: Vector3, speed: float, prefer_high_arc: bool) -> Vector3:
	var to_target: Vector3 = target_pos - origin
	var to_target_xz := Vector2(to_target.x, to_target.z)
	var dist_xz: float = to_target_xz.length()
	if dist_xz <= 0.001 or speed <= 0.001:
		return Vector3.ZERO

	var y: float = to_target.y
	var v2: float = speed * speed
	var g: float = max(0.001, cannonball_gravity)
	var root_term: float = v2 * v2 - g * (g * dist_xz * dist_xz + 2.0 * y * v2)
	if root_term < 0.0:
		return Vector3.ZERO

	var root: float = sqrt(root_term)
	var low: float = atan((v2 - root) / (g * dist_xz))
	var high: float = atan((v2 + root) / (g * dist_xz))
	var theta: float = high if prefer_high_arc else low
	var dir_xz: Vector2 = to_target_xz / dist_xz
	var cos_t: float = cos(theta)
	var sin_t: float = sin(theta)
	return Vector3(dir_xz.x * speed * cos_t, speed * sin_t, dir_xz.y * speed * cos_t)


func _enforce_min_fire_angle(velocity_in: Vector3, side: int) -> Vector3:
	var speed: float = velocity_in.length()
	if speed <= 0.001:
		return velocity_in
	var min_angle: float = clamp(min_fire_angle_degrees, 0.0, 85.0)
	var min_sin: float = sin(deg_to_rad(min_angle))
	var min_y: float = speed * min_sin
	if velocity_in.y >= min_y:
		return velocity_in
	var horiz := Vector2(velocity_in.x, velocity_in.z)
	var horiz_dir := horiz.normalized()
	if horiz.length_squared() <= 0.00001:
		var fallback := (transform.basis.x * float(side)).normalized()
		horiz_dir = Vector2(fallback.x, fallback.z).normalized()
	var clamped_h: float = sqrt(max(speed * speed - min_y * min_y, 0.00001))
	return Vector3(horiz_dir.x * clamped_h, min_y, horiz_dir.y * clamped_h)


func _update_trajectory_preview() -> void:
	if _trajectory_mesh == null:
		return
	if is_ai or actor_type != "ship" or health <= 0.0 or not _aim_mode:
		_trajectory_mesh.visible = false
		_trajectory_preview_active = false
		_aim_solution.clear()
		return
	var solution: Dictionary = _get_player_fire_solution(false)
	if solution.is_empty():
		_trajectory_mesh.visible = false
		_trajectory_preview_active = false
		_aim_solution.clear()
		return
	_aim_solution = solution
	var side: int = int(solution.get("side", 0))
	var target = solution.get("target", null)
	var profile: Dictionary = _get_shot_profile()
	var shot := _build_broadside_shot(side, 0.0, profile, target)
	var p: Vector3 = shot["origin"]
	var v: Vector3 = shot["velocity"]
	var points := PackedVector3Array()
	points.append(p)
	var steps: int = max(8, trajectory_preview_steps)
	var dt: float = max(0.02, trajectory_preview_seconds / float(steps))
	for _i in range(steps):
		v.y -= cannonball_gravity * dt
		p += v * dt
		points.append(p)
		if p.y < global_position.y - 3.0:
			break
	_update_trajectory_mesh(points)
	_trajectory_preview_active = points.size() >= 2
	_trajectory_mesh.visible = _trajectory_preview_active
	if _trajectory_preview_active:
		var focus_idx: int = int(clamp(float(points.size() - 1) * 0.62, 0.0, float(points.size() - 1)))
		_trajectory_focus_world = points[focus_idx]
		if bool(shot.get("has_target", false)):
			var target_pos: Vector3 = shot.get("target_pos", _trajectory_focus_world)
			_trajectory_focus_world = _trajectory_focus_world.lerp(target_pos, 0.38)


func _update_trajectory_mesh(points: PackedVector3Array) -> void:
	if points.size() < 2:
		_trajectory_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP
	var last_idx: int = points.size() - 1
	for i in range(last_idx):
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var dir0: Vector3 = (p1 - p0).normalized()
		var dir1: Vector3 = dir0
		if i + 2 <= last_idx:
			dir1 = (points[i + 2] - p1).normalized()
		var right0: Vector3 = dir0.cross(up).normalized()
		var right1: Vector3 = dir1.cross(up).normalized()
		if right0.length_squared() <= 0.0001:
			right0 = Vector3.RIGHT
		if right1.length_squared() <= 0.0001:
			right1 = Vector3.RIGHT
		var t0: float = float(i) / float(last_idx)
		var t1: float = float(i + 1) / float(last_idx)
		var w0: float = lerp(trajectory_width_start, trajectory_width_end, t0)
		var w1: float = lerp(trajectory_width_start, trajectory_width_end, t1)
		var a0: Vector3 = p0 + right0 * w0
		var b0: Vector3 = p0 - right0 * w0
		var a1: Vector3 = p1 + right1 * w1
		var b1: Vector3 = p1 - right1 * w1
		var alpha0: float = trajectory_alpha * (1.0 - t0 * 0.22)
		var alpha1: float = trajectory_alpha * (1.0 - t1 * 0.22)
		var col0 := Color(1.0, 0.12, 0.12, alpha0)
		var col1 := Color(1.0, 0.12, 0.12, alpha1)

		st.set_normal(up)
		st.set_color(col0)
		st.add_vertex(a0)
		st.set_normal(up)
		st.set_color(col0)
		st.add_vertex(b0)
		st.set_normal(up)
		st.set_color(col1)
		st.add_vertex(a1)

		st.set_normal(up)
		st.set_color(col0)
		st.add_vertex(b0)
		st.set_normal(up)
		st.set_color(col1)
		st.add_vertex(b1)
		st.set_normal(up)
		st.set_color(col1)
		st.add_vertex(a1)
	_trajectory_mesh.mesh = st.commit()


func get_trajectory_camera_hint() -> Dictionary:
	var fallback_focus: Vector3 = global_position + (-transform.basis.z * 14.0) + Vector3.UP * 1.2
	var focus: Vector3 = _trajectory_focus_world if _trajectory_preview_active else fallback_focus
	return {
		"active": _aim_mode,
		"focus_pos": focus,
	}


func _tick_collision_cooldowns(delta: float) -> void:
	var expired: Array = []
	for key in _collision_cooldowns.keys():
		var left: float = float(_collision_cooldowns[key]) - delta
		if left <= 0.0:
			expired.append(key)
		else:
			_collision_cooldowns[key] = left
	for key in expired:
		_collision_cooldowns.erase(key)


func _set_collision_cooldown_from_peer(peer_id: int, seconds: float) -> void:
	if seconds <= 0.0:
		return
	_collision_cooldowns[peer_id] = max(float(_collision_cooldowns.get(peer_id, 0.0)), seconds)


func _get_collision_radius() -> float:
	return collision_radius_surfboard if actor_type == "surfboard" else collision_radius_ship


func _handle_ship_collisions() -> void:
	if health <= 0.0:
		return
	var self_id: int = int(get_instance_id())
	var self_radius: float = _get_collision_radius()
	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if n == self:
			continue
		if n.get("health") == null or float(n.health) <= 0.0:
			continue
		var other_id: int = int(n.get_instance_id())
		if self_id >= other_id:
			continue
		if float(_collision_cooldowns.get(other_id, 0.0)) > 0.0:
			continue

		var other_type: String = str(n.get("actor_type"))
		var other_radius: float = float(n.get("collision_radius_ship"))
		if other_type == "surfboard":
			other_radius = float(n.get("collision_radius_surfboard"))

		var delta_xz := Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z)
		var dist: float = delta_xz.length()
		var min_dist: float = self_radius + other_radius
		if dist >= min_dist:
			continue

		var normal: Vector2 = Vector2.RIGHT if dist <= 0.001 else (delta_xz / dist)
		var penetration: float = min_dist - dist
		var correction: Vector2 = normal * (penetration * 0.5 + 0.02)
		global_position.x -= correction.x
		global_position.z -= correction.y
		var other_pos: Vector3 = n.global_position
		other_pos.x += correction.x
		other_pos.z += correction.y
		n.global_position = other_pos

		var self_vel := Vector2(velocity.x, velocity.z)
		var other_vel3: Variant = n.get("velocity")
		var other_vel := Vector2.ZERO
		if other_vel3 is Vector3:
			var v3 := other_vel3 as Vector3
			other_vel = Vector2(v3.x, v3.z)
		var closing_speed: float = max(0.0, (self_vel - other_vel).dot(normal))
		var impact_damage: float = clamp(
			collision_damage_base + closing_speed * collision_damage_speed_scale,
			0.0,
			collision_damage_max
		)
		if impact_damage <= 0.0:
			continue
		_set_collision_cooldown_from_peer(other_id, collision_cooldown)
		if n.has_method("_set_collision_cooldown_from_peer"):
			n.call("_set_collision_cooldown_from_peer", self_id, collision_cooldown)
		if has_method("apply_damage"):
			apply_damage(impact_damage, n)
		if n.has_method("apply_damage"):
			n.call("apply_damage", impact_damage, self)
		_current_speed *= 0.65
		if n.get("_current_speed") != null:
			n.set("_current_speed", float(n.get("_current_speed")) * 0.65)


func get_combat_debug() -> Dictionary:
	var side_label: String = "none"
	var target_name: String = "-"
	var target_dist: float = -1.0
	var in_range: bool = false
	var solution: Dictionary = {}
	if is_ai and faction == "enemy":
		var ai_target = _get_enemy_target()
		if ai_target != null:
			target_dist = global_position.distance_to(ai_target.global_position)
			target_name = str(ai_target.get("actor_name"))
			if target_name.is_empty():
				target_name = ai_target.name
			var local: Vector3 = _flat_local_of(ai_target.global_position)
			if local.x < -target_side_threshold and abs(local.z) < cannon_range * 0.85:
				side_label = "port"
			elif local.x > target_side_threshold and abs(local.z) < cannon_range * 0.85:
				side_label = "starboard"
			in_range = target_dist <= cannon_range
	else:
		solution = _get_player_fire_solution(false)
		if not solution.is_empty():
			var p_target = solution.get("target")
			target_dist = float(solution.get("distance", -1.0))
			var side: int = int(solution.get("side", 0))
			side_label = "port" if side < 0 else "starboard"
			in_range = target_dist >= 0.0 and target_dist <= cannon_range
			target_name = str(p_target.get("actor_name"))
			if target_name.is_empty():
				target_name = p_target.name

	var profile: Dictionary = _get_shot_profile()
	return {
		"profile": str(profile.get("name", "-")),
		"target_name": target_name,
		"target_distance": target_dist,
		"target_side": side_label,
		"in_range": in_range,
		"reload_port": _reload_port,
		"reload_starboard": _reload_starboard,
	}


func _compute_anchor_factor() -> float:
	var factor := 1.0
	var pos_xz := Vector2(global_position.x, global_position.z)
	var islands: Array = get_tree().get_nodes_in_group("island")
	for n in islands:
		if n is not Node3D:
			continue
		var island := n as Node3D
		var radius: float = float(island.get("radius"))
		var anchor_radius: float = radius * anchor_zone_scale
		var center := Vector2(island.global_position.x, island.global_position.z)
		var dist := pos_xz.distance_to(center)
		if dist >= anchor_radius:
			continue
		var inner_span: float = max(anchor_radius - radius, 0.001)
		var t: float = clamp((anchor_radius - dist) / inner_span, 0.0, 1.0)
		factor = min(factor, lerp(1.0, 0.18, t))
	return factor


func _apply_island_anchor(delta: float) -> void:
	var pos_xz := Vector2(global_position.x, global_position.z)
	var islands: Array = get_tree().get_nodes_in_group("island")
	var snapped := false
	for n in islands:
		if n is not Node3D:
			continue
		var island := n as Node3D
		var radius: float = float(island.get("radius"))
		var hard_radius := radius + anchor_hard_padding
		var center := Vector2(island.global_position.x, island.global_position.z)
		var from_center := pos_xz - center
		var dist := from_center.length()
		if dist >= hard_radius:
			continue
		var dir := Vector2.RIGHT if dist <= 0.001 else from_center / dist
		pos_xz = center + dir * hard_radius
		snapped = true

	if snapped:
		global_position.x = pos_xz.x
		global_position.z = pos_xz.y
		_current_speed = move_toward(_current_speed, 0.0, (anchor_brake * 2.0) * delta)


func _handle_buoyancy(delta: float) -> void:
	if _ocean == null or not _ocean.has_method("get_wave_height"):
		_water_flow_xz = Vector2.ZERO
		_wake_contact = 0.0
		_vert_vel -= GRAVITY * delta
		global_position.y += _vert_vel * delta
		return

	var p_bow   := _bow.global_position;        p_bow.y   = _ocean.get_wave_height(p_bow)
	var p_stern := _stern.global_position;      p_stern.y = _ocean.get_wave_height(p_stern)
	var p_port  := _port.global_position;       p_port.y  = _ocean.get_wave_height(p_port)
	var p_star  := _starboard.global_position;  p_star.y  = _ocean.get_wave_height(p_star)

	var avg_y:            float = (p_bow.y + p_stern.y + p_port.y + p_star.y) * 0.25
	var waterline_offset: float = 0.1 if actor_type == "surfboard" else 0.4
	var target_y          := avg_y + waterline_offset
	var draft := surfboard_draft if actor_type == "surfboard" else 1.0
	_wake_contact = clamp((avg_y + draft - global_position.y) / max(draft, 0.05), 0.0, 1.0)

	if _ocean.has_method("get_wave_velocity_xz"):
		var flow_any = _ocean.call("get_wave_velocity_xz", global_position)
		_water_flow_xz = flow_any if flow_any is Vector2 else Vector2.ZERO
	else:
		_water_flow_xz = Vector2.ZERO

	# Always apply reduced gravity
	_vert_vel -= GRAVITY * delta

	if global_position.y < target_y:
		# Submerged — spring pushes up; gentle water resistance keeps it stable
		_vert_vel += (target_y - global_position.y) * bob_lerp * 2.5 * delta
		_vert_vel  = lerp(_vert_vel, 0.0, 1.5 * delta)

	global_position.y += _vert_vel * delta

	# Tilt to match local wave surface normal
	var fwd_slope   := (p_bow - p_stern).normalized()
	var right_slope := (p_star - p_port).normalized()
	var target_up   := right_slope.cross(fwd_slope).normalized()

	var new_up    := transform.basis.y.lerp(target_up, tilt_lerp * delta).normalized()
	var cur_hdg   := -transform.basis.z
	var new_right := cur_hdg.cross(new_up).normalized()
	var final_fwd := new_up.cross(new_right).normalized()
	transform.basis = Basis(new_right, new_up, -final_fwd)

	# Bow-slam drag
	var bow_drop: float = p_bow.y - _bow.global_position.y
	if bow_drop > slam_threshold:
		_current_drag = slam_drag
	else:
		_current_drag = lerp(_current_drag, 1.0, slam_recover * delta)


func _apply_water_drift(delta: float) -> void:
	if _wake_contact <= 0.0:
		return
	if water_drift_strength <= 0.0:
		return
	var drift := _water_flow_xz * _wake_contact * water_drift_strength * delta
	global_position.x += drift.x
	global_position.z += drift.y


func _update_wake(_delta: float) -> void:
	var h_len := surfboard_half_length if actor_type == "surfboard" else 4.5
	var h_wid := surfboard_half_width  if actor_type == "surfboard" else 1.75
	var draft := surfboard_draft       if actor_type == "surfboard" else 1.0
	_wake_rel_speed = (Vector2(velocity.x, velocity.z) - _water_flow_xz).length()
	var water_displacement: Vector2 = _water_flow_xz * _delta
	_wake_controller.process_wake(
		global_position,
		transform.basis,
		velocity,
		_wave_speed,
		h_len,
		h_wid,
		draft,
		_wake_contact,
		_wake_rel_speed,
		water_displacement
	)
