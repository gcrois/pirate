extends Node

@export var camera_path: NodePath
var _camera: Camera3D
var _ships: Array[ShipController] = []
var _current_idx: int = 0

func _ready() -> void:
	if not camera_path.is_empty():
		_camera = get_node(camera_path)
	
	# Wait a bit for all ships to join the group
	await get_tree().process_frame
	await get_tree().process_frame
	
	var nodes = get_tree().get_nodes_in_group("ship")
	for n in nodes:
		if n is ShipController:
			_ships.append(n)
	
	# Initial state based on main.tscn or first ship
	for i in _ships.size():
		if not _ships[i].is_ai:
			_current_idx = i
			break

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		_switch_vessel()

func _switch_vessel() -> void:
	if _ships.size() < 2:
		return
		
	# 1. Turn current vessel into AI
	_ships[_current_idx].is_ai = true
	
	# 2. Increment index
	_current_idx = (_current_idx + 1) % _ships.size()
	
	# 3. Turn new vessel into Player
	var new_vessel = _ships[_current_idx]
	new_vessel.is_ai = false
	
	# 4. Update camera
	if _camera != null:
		_camera.set("_target", new_vessel)
		# We don't snap, let the lerp handle the transition
		print("[VesselManager] Switched to %s" % ("Surfboard" if new_vessel.is_surfboard else "Ship"))
