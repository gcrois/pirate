extends Node

var _frame_count = 0
@export var auto_quit: bool = false
@export var log_interval_frames: int = 180


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_all_tests()


func _run_all_tests() -> void:
	print("\n╔══════════════════════════════════════════════╗")
	print("║       BUOYANCY & WAKE DIAGNOSTIC TESTS       ║")
	print("╚══════════════════════════════════════════════╝\n")

	var all_pass = true
	var ocean = get_tree().get_first_node_in_group("ocean")
	all_pass = _assert("Ocean node exists", ocean != null) and all_pass
	if ocean == null:
		print("[ABORT] Cannot continue without ocean node\n")
		if auto_quit:
			get_tree().quit(1)
		return

	all_pass = _assert("Ocean has get_wave_height()", ocean.has_method("get_wave_height")) and all_pass
	all_pass = _assert("Ocean is Node3D", ocean is Node3D) and all_pass
	all_pass = _assert("Ocean material is assigned", ocean.get("ocean_material") != null) and all_pass

	var actors = get_tree().get_nodes_in_group("ship")
	all_pass = _assert("At least one actor in 'ship' group", actors.size() > 0) and all_pass

	for a in actors:
		if a.get("actor_type") == null:
			continue
		var tag = ("%s [%s]" % [a.actor_name, a.actor_type]).strip_edges()
		if a.is_ai:
			tag = "AI " + tag

		print("\n── %s ──" % tag)
		print("  pos: %s" % a.global_position)
		print("  gold: %d  inv: %d / %d" % [a.gold, a.total_inventory(), a.max_inventory])

		all_pass = _assert("%s actor_type valid" % tag, a.actor_type == "ship" or a.actor_type == "surfboard") and all_pass
		all_pass = _assert("%s inventory exists" % tag, a.inventory is Dictionary) and all_pass
		all_pass = _assert("%s max_inventory > 0" % tag, a.max_inventory > 0) and all_pass
		for good in Economy.GOODS:
			all_pass = _assert("%s has '%s' inventory key" % [tag, good], a.inventory.has(good)) and all_pass

		var wc = a.get("_wake_controller")
		all_pass = _assert("%s wake controller exists" % tag, wc != null) and all_pass
		if wc != null:
			all_pass = _assert("%s wake texture exists" % tag, wc.wake_texture != null) and all_pass

		if ocean.has_method("get_wave_height"):
			var wave_h = ocean.get_wave_height(a.global_position)
			var target_y = wave_h + (0.1 if a.actor_type == "surfboard" else 0.4)
			var diff = a.global_position.y - target_y
			print("  y=%.3f  wave=%.3f  target=%.3f  diff=%.3f" % [a.global_position.y, wave_h, target_y, diff])
			all_pass = _assert("%s buoyancy diff < 4.0m" % tag, abs(diff) < 4.0) and all_pass

	if ocean.has_method("get_wave_height"):
		print("\n── Wave Height Sanity ──")
		var samples = [
			Vector3.ZERO,
			Vector3(50, 0, 50),
			Vector3(-140, 0, 75),
			Vector3(220, 0, -180),
		]
		var in_range = true
		for p in samples:
			var h = ocean.get_wave_height(p)
			print("  get_wave_height(%.1f, %.1f) = %.3f" % [p.x, p.z, h])
			in_range = in_range and h > -8.0 and h < 8.0
		all_pass = _assert("Sampled wave heights are in [-8, 8]", in_range) and all_pass

	print("\n╔══════════════════════════════════════════════╗")
	if all_pass:
		print("║           ALL TESTS PASSED ✓                 ║")
	else:
		print("║           SOME TESTS FAILED ✗                ║")
	print("╚══════════════════════════════════════════════╝\n")

	if auto_quit:
		get_tree().quit(0 if all_pass else 1)


func _assert(name: String, condition: bool) -> bool:
	if condition:
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)
	return condition


func _process(_delta: float) -> void:
	if auto_quit:
		return
	if log_interval_frames <= 0:
		return
	_frame_count += 1
	if _frame_count % log_interval_frames != 0:
		return

	var ocean = get_tree().get_first_node_in_group("ocean")
	if ocean == null or not ocean.has_method("get_wave_height"):
		return

	for a in get_tree().get_nodes_in_group("ship"):
		if a.get("actor_type") == null:
			continue
		var pos = a.global_position
		var wave_h = ocean.get_wave_height(pos)
		print("[DIAG] %s (%s) pos=(%.1f, %.1f, %.1f) wave=%.3f off=%.3f spd=%.1f" % [
			a.actor_name, a.actor_type, pos.x, pos.y, pos.z, wave_h, pos.y - wave_h, a._wave_speed
		])
