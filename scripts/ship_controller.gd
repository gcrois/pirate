class_name ShipController
extends Node3D

@export var max_speed:    float = 10.0
@export var acceleration: float = 8.0
@export var deceleration: float = 5.0
@export var turn_speed:   float = 1.5
@export var bob_lerp:     float = 8.0
@export var tilt_lerp:    float = 3.0
@export var slam_threshold: float = 0.3
@export var slam_drag:      float = 0.4
@export var slam_recover:   float = 3.0

@export_category("Surfboard & AI")
@export var is_surfboard: bool = false
@export var is_ai: bool = false
@export var surfboard_half_length: float = 1.0
@export var surfboard_half_width: float = 0.3
@export var surfboard_draft: float = 0.1

@onready var _bow:       Marker3D = $Bow
@onready var _stern:     Marker3D = $Stern
@onready var _port:      Marker3D = $Port
@onready var _starboard: Marker3D = $Starboard

var _ocean:        Node
var _current_drag: float = 1.0
var _current_speed: float = 0.0   # signed, along -basis.z

var _wake_controller: WakeController

# Public — read by DebugOverlay and OceanManager
var velocity: Vector3 = Vector3.ZERO
var _prev_pos: Vector3
var _wave_speed: float = 0.0   # smoothed speed

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
	_ocean = get_tree().get_first_node_in_group("ocean")

	if is_surfboard:
		_bow.position = Vector3(0, 0, -surfboard_half_length)
		_stern.position = Vector3(0, 0, surfboard_half_length)
		_port.position = Vector3(-surfboard_half_width, 0, 0)
		_starboard.position = Vector3(surfboard_half_width, 0, 0)
		max_speed = 8.0
		turn_speed = 2.0
		bob_lerp = 15.0
		tilt_lerp = 10.0
		
		if has_node("Cabin"): $Cabin.hide()
		if has_node("Mast"): $Mast.hide()
		if has_node("Yard"): $Yard.hide()
		if has_node("Sail"): $Sail.hide()
		if has_node("Hull"):
			$Hull.mesh = BoxMesh.new()
			$Hull.mesh.size = Vector3(surfboard_half_width * 2.0, 0.2, surfboard_half_length * 2.0)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.2, 0.2)
			$Hull.material_override = mat

	_wake_controller = WakeController.new()
	add_child(_wake_controller)

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_buoyancy(delta)

	velocity  = (global_position - _prev_pos) / delta
	_prev_pos = global_position

	var actual_spd := Vector2(velocity.x, velocity.z).length()
	_wave_speed = lerp(_wave_speed, actual_spd, 4.0 * delta)

	_update_wake(delta)

func _handle_movement(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_META):
		var test_throttle := Input.get_axis("ui_down", "ui_up")
		var test_steer := Input.get_axis("ui_right", "ui_left")
		
		if test_throttle != 0.0:
			_current_speed += test_throttle * acceleration * delta * 2.0
		else:
			_current_speed = move_toward(_current_speed, 0.0, deceleration * delta)
			
		if test_steer != 0.0:
			global_position += transform.basis.x * test_steer * max_speed * delta
			
		if abs(_current_speed) > 0.001:
			global_position += -transform.basis.z * _current_speed * delta
		return

	var throttle := Input.get_axis("ui_down", "ui_up")
	var steer := Input.get_axis("ui_right", "ui_left")
	
	if is_ai:
		throttle = 1.0
		steer = 1.0

	var target := throttle * max_speed * _current_drag
	var rate   := acceleration if throttle != 0.0 else deceleration
	_current_speed = move_toward(_current_speed, target, rate * delta)

	if abs(_current_speed) > 0.001:
		global_position += -transform.basis.z * _current_speed * delta

	if steer != 0.0:
		rotate_y(steer * turn_speed * delta)

func _handle_buoyancy(delta: float) -> void:
	if _ocean == null or not _ocean.has_method("get_wave_height"):
		return

	var p_bow   = _bow.global_position;   p_bow.y = _ocean.get_wave_height(p_bow)
	var p_stern = _stern.global_position; p_stern.y = _ocean.get_wave_height(p_stern)
	var p_port  = _port.global_position;  p_port.y = _ocean.get_wave_height(p_port)
	var p_star  = _starboard.global_position; p_star.y = _ocean.get_wave_height(p_star)

	var avg_y: float = (p_bow.y + p_stern.y + p_port.y + p_star.y) * 0.25
	var waterline_offset: float = 0.1 if is_surfboard else 0.4
	global_position.y = lerp(global_position.y, avg_y + waterline_offset, bob_lerp * delta)

	var fwd_slope   = (p_bow - p_stern).normalized()
	var right_slope = (p_star - p_port).normalized()
	var target_up   = right_slope.cross(fwd_slope).normalized()

	var new_up = transform.basis.y.lerp(target_up, tilt_lerp * delta).normalized()
	var current_heading = -transform.basis.z
	var new_right = current_heading.cross(new_up).normalized()
	var final_fwd = new_up.cross(new_right).normalized()

	transform.basis = Basis(new_right, new_up, -final_fwd)

	var bow_drop: float = p_bow.y - _bow.global_position.y
	if bow_drop > slam_threshold:
		_current_drag = slam_drag
	else:
		_current_drag = lerp(_current_drag, 1.0, slam_recover * delta)

func _update_wake(_delta: float) -> void:
	var h_len = surfboard_half_length if is_surfboard else 4.5
	var h_wid = surfboard_half_width if is_surfboard else 1.75
	var draft = surfboard_draft if is_surfboard else 1.0
	_wake_controller.process_wake(global_position, transform.basis, velocity, _wave_speed, h_len, h_wid, draft)
