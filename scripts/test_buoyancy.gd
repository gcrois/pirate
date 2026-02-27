## Auto-running diagnostic test script.
## Runs all tests automatically on _ready() — check the Godot console output.
## Also prints periodic DIAG lines so you can see live values without visual testing.
extends Node

var _frame_count: int = 0

func _ready() -> void:
	# Wait one frame so all other nodes are initialized
	await get_tree().process_frame
	await get_tree().process_frame  # two frames to let viewports render
	_run_all_tests()

func _run_all_tests() -> void:
	print("\n╔══════════════════════════════════════════════╗")
	print("║       BUOYANCY & WAKE DIAGNOSTIC TESTS       ║")
	print("╚══════════════════════════════════════════════╝\n")
	
	var all_pass = true
	
	# ── TEST 1: Ocean node ──
	var ocean = get_tree().get_first_node_in_group("ocean")
	all_pass = _assert("Ocean node exists", ocean != null) and all_pass
	if ocean == null:
		print("[ABORT] Cannot continue without ocean node\n")
		return
	all_pass = _assert("Ocean has get_wave_height()", ocean.has_method("get_wave_height")) and all_pass
	all_pass = _assert("Ocean is MeshInstance3D", ocean is MeshInstance3D) and all_pass
	
	# ── TEST 2: Ocean material access ──
	var mi: MeshInstance3D = ocean as MeshInstance3D
	print("\n── Ocean Material Access ──")
	print("  material_override:                  %s" % _fmt(mi.material_override))
	print("  get_surface_override_material(0):   %s" % _fmt(mi.get_surface_override_material(0)))
	print("  mesh.surface_get_material(0):       %s" % _fmt(mi.mesh.surface_get_material(0)))
	if mi.mesh is PrimitiveMesh:
		print("  (mesh as PrimitiveMesh).material:   %s" % _fmt((mi.mesh as PrimitiveMesh).material))
	
	# Determine which one actually works
	var resolved_mat: ShaderMaterial = null
	if mi.material_override is ShaderMaterial:
		resolved_mat = mi.material_override
		print("  → Resolved via: material_override")
	elif mi.get_surface_override_material(0) is ShaderMaterial:
		resolved_mat = mi.get_surface_override_material(0)
		print("  → Resolved via: get_surface_override_material(0)")
	elif mi.mesh.surface_get_material(0) is ShaderMaterial:
		resolved_mat = mi.mesh.surface_get_material(0)
		print("  → Resolved via: mesh.surface_get_material(0)")
	elif mi.mesh is PrimitiveMesh and (mi.mesh as PrimitiveMesh).material is ShaderMaterial:
		resolved_mat = (mi.mesh as PrimitiveMesh).material
		print("  → Resolved via: (mesh as PrimitiveMesh).material")
	
	all_pass = _assert("Outer ocean ShaderMaterial resolved", resolved_mat != null) and all_pass
	
	# ── TEST 3: Inner ocean material ──
	var inner = get_tree().get_first_node_in_group("inner_ocean")
	all_pass = _assert("Inner ocean node exists", inner != null) and all_pass
	if inner is MeshInstance3D:
		var inner_mi: MeshInstance3D = inner as MeshInstance3D
		print("\n── Inner Ocean Material Access ──")
		print("  material_override: %s" % _fmt(inner_mi.material_override))
		all_pass = _assert("Inner ocean material_override exists", inner_mi.material_override != null) and all_pass
	
	# ── TEST 4: Ship controllers ──
	var ships = get_tree().get_nodes_in_group("ship")
	all_pass = _assert("At least 1 ship in group", ships.size() >= 1) and all_pass
	all_pass = _assert("Exactly 2 ships in group", ships.size() == 2) and all_pass
	
	for i in ships.size():
		var ship = ships[i]
		if not ship is ShipController:
			continue
		var sc: ShipController = ship as ShipController
		var label = ("AI " if sc.is_ai else "") + ("Surfboard" if sc.is_surfboard else "Ship")
		print("\n── %s (group index %d) ──" % [label, i])
		print("  position: %s" % sc.global_position)
		
		# In new architecture, we check if the ocean node has resolved them.
		var central_ocean = get_tree().get_first_node_in_group("ocean")
		var om = central_ocean.get("_ocean_mat")
		var inners = get_tree().get_nodes_in_group("inner_ocean")
		
		all_pass = _assert("Central Ocean._ocean_mat resolved", om != null) and all_pass
		all_pass = _assert("At least 1 Inner Ocean exists", inners.size() > 0) and all_pass
		
		# Check if at least one inner material is being managed
		var inner_mi = inners[0] as MeshInstance3D
		var im = ShipController._get_shader_material(inner_mi)
		all_pass = _assert("Inner Ocean material resolved", im != null) and all_pass
		
		# Check wake controller
		var wc = sc.get("_wake_controller")
		all_pass = _assert("%s._wake_controller exists" % label, wc != null) and all_pass
		if wc:
			all_pass = _assert("%s.wake_texture exists" % label, wc.wake_texture != null) and all_pass
		
		# Check buoyancy sync
		if ocean.has_method("get_wave_height"):
			var wave_h: float = ocean.get_wave_height(sc.global_position)
			var target_y: float = wave_h + (0.1 if sc.is_surfboard else 0.4)
			var error: float = sc.global_position.y - target_y
			print("  ship.y=%.3f  wave_h=%.3f  target=%.3f  diff=%.3f" % [sc.global_position.y, wave_h, target_y, error])
			all_pass = _assert("%s track error < 1.0m" % label, abs(error) < 1.0) and all_pass
	
	# ── TEST 5: Wave height sanity ──
	if ocean.has_method("get_wave_height"):
		print("\n── Wave Height Sanity ──")
		var h0: float = ocean.get_wave_height(Vector3.ZERO)
		var h1: float = ocean.get_wave_height(Vector3(50, 0, 50))
		print("  get_wave_height(0,0,0)   = %.4f" % h0)
		print("  get_wave_height(50,0,50) = %.4f" % h1)
		all_pass = _assert("Wave height at origin in [-2, 2]", h0 > -2.0 and h0 < 2.0) and all_pass
	
	# ── SUMMARY ──
	print("\n╔══════════════════════════════════════════════╗")
	if all_pass:
		print("║           ALL TESTS PASSED ✓                 ║")
	else:
		print("║           SOME TESTS FAILED ✗                ║")
	print("╚══════════════════════════════════════════════╝\n")

func _assert(name: String, condition: bool) -> bool:
	if condition:
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)
	return condition

func _fmt(obj) -> String:
	if obj == null:
		return "null"
	return str(obj)

func _process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count % 180 != 0:  # Every 3 seconds
		return
	
	var ocean = get_tree().get_first_node_in_group("ocean")
	if ocean == null or not ocean.has_method("get_wave_height"):
		return
	
	for ship in get_tree().get_nodes_in_group("ship"):
		if not ship is ShipController:
			continue
		var sc: ShipController = ship as ShipController
		var label = ("AI " if sc.is_ai else "") + ("Surfboard" if sc.is_surfboard else "Ship")
		var pos: Vector3 = sc.global_position
		var wave_h: float = ocean.get_wave_height(pos)
		print("[DIAG] %s  pos=(%.1f, %.1f, %.1f)  waveH=%.3f  offset=%.3f  spd=%.1f" % [
			label, pos.x, pos.y, pos.z, wave_h, pos.y - wave_h, sc._wave_speed
		])
