extends Camera3D

@export var target: NodePath = NodePath("")
@export var offset: Vector3 = Vector3(0, 8, 15)
@export var follow_speed: float = 5.0
@export var vertical_speed: float = 2.0   # slower Y follow makes wave impacts feel heavy

var _target: Node3D

func _ready() -> void:
	if not target.is_empty():
		_target = get_node(target)
	if _target:
		_snap()

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.global_position + _target.transform.basis * offset
	global_position.x = lerp(global_position.x, desired.x, follow_speed * delta)
	global_position.z = lerp(global_position.z, desired.z, follow_speed * delta)
	global_position.y = lerp(global_position.y, desired.y, vertical_speed * delta)
	look_at(_target.global_position + Vector3(0, 1, 0), Vector3.UP)

func _snap() -> void:
	global_position = _target.global_position + _target.transform.basis * offset
	look_at(_target.global_position + Vector3(0, 1, 0), Vector3.UP)
