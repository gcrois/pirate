extends Camera3D

@export var target: Vector3 = Vector3.ZERO


func _ready() -> void:
	current = true
	look_at(target, Vector3.UP)
