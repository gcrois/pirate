extends MeshInstance3D

@export var follow_index: int = 0 # 0 for Player, 1 for AI

var _ocean: Node

func _ready() -> void:
	add_to_group("inner_ocean")
	_ocean = get_tree().get_first_node_in_group("ocean")

func _process(_delta: float) -> void:
	if _ocean == null: return
	
	# Resolve target from ocean's deterministic sorting
	var target: Node3D = null
	if follow_index == 0:
		target = _ocean.get("s0")
	elif follow_index == 1:
		target = _ocean.get("s1")
		
	if target != null:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
