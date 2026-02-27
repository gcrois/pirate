extends CanvasLayer

var _labels: Dictionary = {}
var _tex_rects: Dictionary = {}
var _is_debug_visible: bool = true

const PREVIEW_SIZE := 200

var _sample_counter: int = 0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_D:
		_is_debug_visible = not _is_debug_visible
		for l in _labels.values():
			l.visible = _is_debug_visible
		for t in _tex_rects.values():
			t["container"].visible = _is_debug_visible


func _process(_delta: float) -> void:
	if not _is_debug_visible:
		return

	var actors = get_tree().get_nodes_in_group("ship")
	if actors.is_empty():
		return

	var camera = get_viewport().get_camera_3d()
	if camera == null or not camera.is_current():
		return

	var active_ids: Array = []
	var preview_index := 0

	for actor in actors:
		if actor.get("actor_type") == null:
			continue

		var actor_id = actor.get_instance_id()
		active_ids.append(actor_id)

		if not _labels.has(actor_id):
			var l := Label.new()
			l.add_theme_font_size_override("font_size", 24)
			l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.1))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", 6)
			add_child(l)
			_labels[actor_id] = l

		if not _tex_rects.has(actor_id):
			var container := VBoxContainer.new()

			var title := Label.new()
			title.add_theme_font_size_override("font_size", 14)
			title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			title.add_theme_constant_override("outline_size", 4)
			container.add_child(title)

			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			container.add_child(tr)

			var stats_label := Label.new()
			stats_label.add_theme_font_size_override("font_size", 12)
			stats_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
			stats_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			stats_label.add_theme_constant_override("outline_size", 3)
			container.add_child(stats_label)

			add_child(container)
			_tex_rects[actor_id] = {
				container = container,
				title = title,
				rect = tr,
				stats = stats_label,
			}

		var l = _labels[actor_id] as Label
		var pos = actor.global_position

		if camera.is_position_behind(pos):
			l.visible = false
			continue

		l.visible = true
		var rot = actor.rotation_degrees
		var spd = Vector2(actor.velocity.x, actor.velocity.z).length()
		var heading = fmod(360.0 - rot.y, 360.0)
		var type_name = str(actor.actor_type).capitalize()
		var label_name = type_name if str(actor.actor_name).is_empty() else "%s (%s)" % [actor.actor_name, type_name]
		if actor.is_ai:
			label_name = "AI " + label_name

		var ocean = get_tree().get_first_node_in_group("ocean")
		var wave_h = 0.0
		if ocean != null and ocean.has_method("get_wave_height"):
			wave_h = ocean.get_wave_height(pos)
		var y_offset = pos.y - wave_h

		l.text = (
			"[%s]\n" % label_name
			+ "Pos: %6.1f, %4.1f, %6.1f\n" % [pos.x, pos.y, pos.z]
			+ "WaterH: %4.1f  Offset: %4.2f\n" % [wave_h, y_offset]
			+ "Spd: %6.1f u/s\n" % spd
			+ "Hdg: %6.1f deg\n" % heading
		)

		l.position = camera.unproject_position(pos) + Vector2(40.0, -40.0)

		var info = _tex_rects[actor_id]
		var wc = actor.get("_wake_controller")
		if wc != null and wc.wake_texture != null:
			info["rect"].texture = wc.wake_texture
			info["title"].text = "%s Wake Buffer" % label_name
			info["container"].position = Vector2(
				10 + preview_index * (PREVIEW_SIZE + 20),
				get_viewport().get_visible_rect().size.y - PREVIEW_SIZE - 60
			)
			_update_buffer_stats(wc, info["stats"])

		preview_index += 1

	for key in _labels.keys():
		if not key in active_ids:
			_labels[key].queue_free()
			_labels.erase(key)

	for key in _tex_rects.keys():
		if not key in active_ids:
			_tex_rects[key]["container"].queue_free()
			_tex_rects.erase(key)


func _update_buffer_stats(wc: WakeController, stats_label: Label) -> void:
	if DisplayServer.get_name() == "headless":
		return

	_sample_counter += 1
	if _sample_counter % 30 != 0:
		return

	var vp: SubViewport = wc.get("_viewport")
	if vp == null:
		return
	var tex = vp.get_texture()
	if tex == null:
		return
	if not tex.get_rid().is_valid():
		return
	var img: Image = tex.get_image()
	if img == null:
		return

	var total := 0.0
	var count := 0
	var min_v := 1.0
	var max_v := 0.0
	var center_v := 0.0
	var resolution := img.get_width()

	for y in 16:
		for x in 16:
			var px := int(x * resolution / 16.0)
			var py := int(y * resolution / 16.0)
			var c := img.get_pixel(px, py)
			total += c.r
			count += 1
			min_v = min(min_v, c.r)
			max_v = max(max_v, c.r)

	var cc := img.get_pixel(resolution / 2, resolution / 2)
	center_v = cc.r

	var avg := total / count
	var net_disp := (avg - 0.5) * 4.0

	stats_label.text = (
		"Avg: %.3f  Center: %.3f  Min: %.3f  Max: %.3f\n" % [avg, center_v, min_v, max_v]
		+ "Net displacement: %+.2fm (should be ~0)" % net_disp
	)
