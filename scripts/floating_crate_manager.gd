extends Node

@export var crate_scene: PackedScene = preload("res://scenes/floating_crate.tscn")
@export var target_crates: int = 12
@export var world_extent: float = 330.0
@export var min_spawn_from_player: float = 42.0
@export var min_island_margin: float = 8.0
@export var respawn_interval: float = 2.5

var _rng := RandomNumberGenerator.new()
var _respawn_timer: float = 0.0


func _ready() -> void:
	_rng.randomize()
	for _i in range(target_crates):
		_spawn_one()


func _process(delta: float) -> void:
	_respawn_timer -= delta
	if _respawn_timer > 0.0:
		return
	_respawn_timer = respawn_interval

	var existing: int = get_tree().get_nodes_in_group("floating_crate").size()
	var needed: int = max(0, target_crates - existing)
	for _i in range(needed):
		if not _spawn_one():
			break


func _spawn_one() -> bool:
	if crate_scene == null:
		return false

	for _attempt in range(48):
		var pos := Vector3(
			_rng.randf_range(-world_extent, world_extent),
			0.0,
			_rng.randf_range(-world_extent, world_extent)
		)
		if not _is_valid_spawn(pos):
			continue
		var crate = crate_scene.instantiate()
		if crate == null:
			return false
		add_child(crate)
		crate.global_position = pos
		crate.set("good", Economy.GOODS[_rng.randi_range(0, Economy.GOODS.size() - 1)])
		crate.set("amount", _rng.randi_range(1, 2))
		return true
	return false


func _is_valid_spawn(pos: Vector3) -> bool:
	var player = _get_player_actor()
	if player != null and pos.distance_to(player.global_position) < min_spawn_from_player:
		return false

	for n in get_tree().get_nodes_in_group("island"):
		if n is not Node3D:
			continue
		var island := n as Node3D
		var radius: float = float(island.get("radius"))
		if pos.distance_to(island.global_position) < radius + min_island_margin:
			return false
	return true


func _get_player_actor():
	for n in get_tree().get_nodes_in_group("ship"):
		if n.get("is_ai") == null:
			continue
		if not bool(n.is_ai):
			return n
	return null
