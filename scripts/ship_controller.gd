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
@export var cannon_damage: float = 20.0
@export var cannons_per_side: int = 4
@export var bounty_gold: int = 120

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

var _wake_controller: WakeController

# Public read by DebugOverlay / OceanManager
var velocity:    Vector3 = Vector3.ZERO
var _prev_pos:   Vector3
var _wave_speed: float   = 0.0

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
	add_child(_wake_controller)


func _input(event: InputEvent) -> void:
	if is_ai:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_S:
			_toggle_type()
		elif event.physical_keycode == KEY_Q:
			_try_fire_port()
		elif event.physical_keycode == KEY_E:
			_try_fire_starboard()


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
	_apply_island_anchor(delta)
	_handle_buoyancy(delta)

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
		# S is reserved for type-toggle; reverse uses Down-arrow only
		if   Input.is_physical_key_pressed(KEY_UP)    or Input.is_physical_key_pressed(KEY_W):
			throttle =  1.0
		elif Input.is_physical_key_pressed(KEY_DOWN):
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
	var local: Vector3 = to_local(target.global_position)
	if local.x < -8.0 and abs(local.z) < cannon_range * 0.85:
		_try_fire_port()
	elif local.x > 8.0 and abs(local.z) < cannon_range * 0.85:
		_try_fire_starboard()


func _try_fire_port() -> void:
	if actor_type != "ship" or health <= 0.0:
		return
	if _reload_port > 0.0:
		return
	_reload_port = cannon_reload
	_fire_broadside(-1)


func _try_fire_starboard() -> void:
	if actor_type != "ship" or health <= 0.0:
		return
	if _reload_starboard > 0.0:
		return
	_reload_starboard = cannon_reload
	_fire_broadside(1)


func _fire_broadside(side: int) -> void:
	var half_len: float = 4.2
	var half_wid: float = 1.8
	var count: int = max(1, cannons_per_side)
	var denom: float = max(1.0, float(count - 1))
	for i in range(count):
		var t: float = float(i) / denom - 0.5
		var muzzle: Vector3 = global_position
		muzzle += transform.basis.x * (float(side) * (half_wid + 0.35))
		muzzle += transform.basis.z * (t * half_len * 1.25)
		muzzle += Vector3.UP * 0.45
		var direction: Vector3 = transform.basis.x * float(side)
		direction += -transform.basis.z * (t * 0.35)
		direction = direction.normalized()
		_spawn_cannonball(muzzle, direction)


func _spawn_cannonball(origin: Vector3, direction: Vector3) -> void:
	var ball = CANNONBALL_SCRIPT.new()
	if ball == null:
		return
	get_tree().current_scene.add_child(ball)
	if ball.has_method("setup"):
		ball.setup(self, origin, direction * cannonball_speed, cannon_damage, faction, cannon_range * 3.4)


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


func _update_wake(_delta: float) -> void:
	var h_len := surfboard_half_length if actor_type == "surfboard" else 4.5
	var h_wid := surfboard_half_width  if actor_type == "surfboard" else 1.75
	var draft := surfboard_draft       if actor_type == "surfboard" else 1.0
	_wake_controller.process_wake(global_position, transform.basis, velocity, _wave_speed, h_len, h_wid, draft)
