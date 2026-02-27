extends CanvasLayer

var _labels: Dictionary = {}
var _tex_rects: Dictionary = {}  # Wake buffer preview rectangles
var _is_debug_visible: bool = true

const PREVIEW_SIZE := 200  # px side length for wake buffer preview

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_D:
			_is_debug_visible = not _is_debug_visible
			for l in _labels.values():
				l.visible = _is_debug_visible
			for t in _tex_rects.values():
				t.visible = _is_debug_visible

func _process(_delta: float) -> void:
	if not _is_debug_visible:
		return

	var ships = get_tree().get_nodes_in_group("ship")
	if ships.size() == 0:
		return
		
	var camera := get_viewport().get_camera_3d()
	if camera == null or not camera.is_current():
		return

	var active_ids = []
	var preview_index := 0
	
	for ship in ships:
		if not ship is ShipController:
			continue
			
		var s_id = ship.get_instance_id()
		active_ids.append(s_id)
		
		if not _labels.has(s_id):
			var l = Label.new()
			l.add_theme_font_size_override("font_size", 24)
			l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.1))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", 6)
			add_child(l)
			_labels[s_id] = l
		
		# Create wake buffer preview if not exists
		if not _tex_rects.has(s_id):
			var container = VBoxContainer.new()
			
			var title = Label.new()
			title.add_theme_font_size_override("font_size", 14)
			title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			title.add_theme_constant_override("outline_size", 4)
			container.add_child(title)
			
			var tr = TextureRect.new()
			tr.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			container.add_child(tr)
			
			var stats_label = Label.new()
			stats_label.add_theme_font_size_override("font_size", 12)
			stats_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
			stats_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			stats_label.add_theme_constant_override("outline_size", 3)
			container.add_child(stats_label)
			
			add_child(container)
			_tex_rects[s_id] = {"container": container, "title": title, "rect": tr, "stats": stats_label}
			
		var l: Label = _labels[s_id]
		var pos: Vector3 = ship.global_position
		
		if camera.is_position_behind(pos):
			l.visible = false
			continue
			
		l.visible = true
		var rot: Vector3 = ship.rotation_degrees
		var raw_vel: Variant = ship.velocity
		var spd     := 0.0
		if raw_vel is Vector3:
			spd = Vector2((raw_vel as Vector3).x, (raw_vel as Vector3).z).length()

		var heading := fmod(360.0 - rot.y, 360.0)
		var label_name = "Surfboard" if ship.is_surfboard else "Ship"
		if ship.is_ai:
			label_name = "AI " + label_name

		# Get water height at ship position
		var ocean = get_tree().get_first_node_in_group("ocean")
		var wave_h := 0.0
		if ocean != null and ocean.has_method("get_wave_height"):
			wave_h = ocean.get_wave_height(pos)
		var y_offset: float = pos.y - wave_h

		l.text = (
			"[%s]\n" % label_name
			+ "Pos: %6.1f, %4.1f, %6.1f\n" % [pos.x, pos.y, pos.z]
			+ "WaterH: %4.1f  Offset: %4.2f\n" % [wave_h, y_offset]
			+ "Spd: %6.1f u/s\n"  % spd
			+ "Hdg: %6.1f deg\n"  % heading
		)
		
		l.position = camera.unproject_position(pos) + Vector2(40.0, -40.0)
		
		# Update wake buffer preview
		var info: Dictionary = _tex_rects[s_id]
		var wc = ship.get("_wake_controller")
		if wc != null and wc.wake_texture != null:
			info["rect"].texture = wc.wake_texture
			info["title"].text = "%s Wake Buffer" % label_name
			
			# Position preview in bottom corners
			info["container"].position = Vector2(10 + preview_index * (PREVIEW_SIZE + 20), get_viewport().get_visible_rect().size.y - PREVIEW_SIZE - 60)
			
			# Sample center pixel to show stats (center = directly under the ship)
			_update_buffer_stats(wc, info["stats"])
		
		preview_index += 1
		
	# Cleanup deleted ships
	for key in _labels.keys():
		if not key in active_ids:
			_labels[key].queue_free()
			_labels.erase(key)
	for key in _tex_rects.keys():
		if not key in active_ids:
			_tex_rects[key]["container"].queue_free()
			_tex_rects.erase(key)

var _sample_counter: int = 0

func _update_buffer_stats(wc: WakeController, stats_label: Label) -> void:
	# Only sample every 30 frames (GPU readback is expensive)
	_sample_counter += 1
	if _sample_counter % 30 != 0:
		return
	
	var vp: SubViewport = wc.get("_viewport")
	if vp == null:
		return
	var img: Image = vp.get_texture().get_image()
	if img == null:
		return
	
	# Sample a grid of points to compute average and min/max
	var total := 0.0
	var count := 0
	var min_v := 1.0
	var max_v := 0.0
	var center_v := 0.0
	var resolution := img.get_width()
	
	# Sample 16x16 grid
	for y in 16:
		for x in 16:
			var px := int(x * resolution / 16.0)
			var py := int(y * resolution / 16.0)
			var c := img.get_pixel(px, py)
			total += c.r
			count += 1
			min_v = min(min_v, c.r)
			max_v = max(max_v, c.r)
	
	# Sample center pixel
	var cc := img.get_pixel(resolution / 2, resolution / 2)
	center_v = cc.r
	
	var avg := total / count
	var net_disp := (avg - 0.5) * 4.0  # wake_max_displacement = 4.0
	
	stats_label.text = (
		"Avg: %.3f  Center: %.3f  Min: %.3f  Max: %.3f\n" % [avg, center_v, min_v, max_v]
		+ "Net displacement: %+.2fm (should be ~0)" % net_disp
	)
