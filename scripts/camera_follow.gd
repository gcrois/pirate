extends Camera3D

@export var target: NodePath = NodePath("")
@export var offset: Vector3 = Vector3(0, 8, 15)
@export var combat_offset: Vector3 = Vector3(0, 11, 23)
@export var follow_speed: float = 5.0
@export var vertical_speed: float = 2.0   # slower Y follow makes wave impacts feel heavy
@export var focus_lerp_speed: float = 5.5
@export var combat_camera_blend_speed: float = 4.5
@export var combat_fov: float = 82.0
@export var offset_smoothing_speed: float = 6.0
@export var yaw_smoothing_speed: float = 6.5

var _target: Node3D
var _combat_blend: float = 0.0
var _base_fov: float = 75.0
var _smoothed_focus_pos: Vector3 = Vector3.ZERO
var _smoothed_offset: Vector3
var _smoothed_forward_xz: Vector3 = Vector3.FORWARD

func _ready() -> void:
	if not target.is_empty():
		_target = get_node(target)
	_base_fov = fov
	_smoothed_offset = offset
	if _target:
		_snap()

func _process(delta: float) -> void:
	if _target == null:
		return
	var focus_pos: Vector3 = _target.global_position + Vector3(0, 1, 0)
	var trajectory_active: bool = false
	if _target.has_method("get_trajectory_camera_hint"):
		var hint_any = _target.call("get_trajectory_camera_hint")
		if hint_any is Dictionary:
			var hint: Dictionary = hint_any
			trajectory_active = bool(hint.get("active", false))
			if trajectory_active:
				var hint_focus: Variant = hint.get("focus_pos", focus_pos)
				if hint_focus is Vector3:
					focus_pos = focus_pos.lerp(hint_focus, 0.55)

	var blend_target: float = 1.0 if trajectory_active else 0.0
	_combat_blend = move_toward(_combat_blend, blend_target, combat_camera_blend_speed * delta)
	var live_offset: Vector3 = offset.lerp(combat_offset, _combat_blend)
	_smoothed_offset = _smoothed_offset.lerp(live_offset, clamp(offset_smoothing_speed * delta, 0.0, 1.0))
	var target_forward: Vector3 = -_target.transform.basis.z
	target_forward.y = 0.0
	if target_forward.length_squared() > 0.0001:
		target_forward = target_forward.normalized()
		_smoothed_forward_xz = _smoothed_forward_xz.lerp(target_forward, clamp(yaw_smoothing_speed * delta, 0.0, 1.0)).normalized()
	var yaw_basis := _basis_from_forward_xz(_smoothed_forward_xz)
	var desired := _target.global_position + yaw_basis * _smoothed_offset
	global_position.x = lerp(global_position.x, desired.x, follow_speed * delta)
	global_position.z = lerp(global_position.z, desired.z, follow_speed * delta)
	global_position.y = lerp(global_position.y, desired.y, vertical_speed * delta)
	if _smoothed_focus_pos == Vector3.ZERO:
		_smoothed_focus_pos = focus_pos
	_smoothed_focus_pos = _smoothed_focus_pos.lerp(focus_pos, clamp(focus_lerp_speed * delta, 0.0, 1.0))
	look_at(_smoothed_focus_pos, Vector3.UP)
	fov = lerp(fov, lerp(_base_fov, combat_fov, _combat_blend), clamp(4.0 * delta, 0.0, 1.0))

func _snap() -> void:
	var fwd := -_target.transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		fwd = Vector3.FORWARD
	_smoothed_forward_xz = fwd.normalized()
	var yaw_basis := _basis_from_forward_xz(_smoothed_forward_xz)
	global_position = _target.global_position + yaw_basis * offset
	_smoothed_offset = offset
	_smoothed_focus_pos = _target.global_position + Vector3(0, 1, 0)
	look_at(_target.global_position + Vector3(0, 1, 0), Vector3.UP)


func _basis_from_forward_xz(forward_xz: Vector3) -> Basis:
	var fwd := forward_xz
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	return Basis(right, Vector3.UP, -fwd)
