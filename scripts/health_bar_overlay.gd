extends CanvasLayer

const BAR_W: float = 132.0
const BAR_H: float = 12.0

var _bars: Dictionary = {}


func _ready() -> void:
	layer = 16


func _process(_delta: float) -> void:
	var camera = get_viewport().get_camera_3d()
	if camera == null or not camera.is_current():
		_hide_all()
		return

	var active_ids: Array = []
	var ships: Array = get_tree().get_nodes_in_group("ship")
	for n in ships:
		if n.get("health") == null or n.get("max_health") == null:
			continue
		var ship_id: int = int(n.get_instance_id())
		active_ids.append(ship_id)

		var info: Dictionary = _get_or_create_bar(ship_id)
		var root := info["root"] as Control
		var label := info["label"] as Label
		var fill := info["fill"] as ColorRect
		if root == null or label == null or fill == null:
			continue

		var hp: float = float(n.health)
		var max_hp: float = max(1.0, float(n.max_health))
		var ratio: float = clamp(hp / max_hp, 0.0, 1.0)
		fill.size = Vector2(BAR_W * ratio, BAR_H)

		var bar_color := Color(0.18, 0.85, 0.27, 0.95)
		var faction := str(n.get("faction"))
		if faction == "enemy":
			bar_color = Color(0.95, 0.24, 0.21, 0.95)
		elif faction == "neutral":
			bar_color = Color(0.97, 0.79, 0.24, 0.95)
		fill.color = bar_color

		var actor_name := str(n.get("actor_name"))
		if actor_name.is_empty():
			actor_name = n.name
		label.text = "%s  %.0f / %.0f" % [actor_name, hp, max_hp]

		var world_pos: Vector3 = n.global_position + Vector3(0.0, 3.6, 0.0)
		if camera.is_position_behind(world_pos):
			root.visible = false
			continue
		root.visible = true
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		root.position = screen_pos - Vector2(BAR_W * 0.5, 24.0)

	_cleanup_bars(active_ids)


func _get_or_create_bar(ship_id: int) -> Dictionary:
	if _bars.has(ship_id):
		return _bars[ship_id]

	var root := Control.new()
	root.size = Vector2(BAR_W, 32.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var label := Label.new()
	label.position = Vector2(-20.0, -2.0)
	label.size = Vector2(BAR_W + 40.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("outline_size", 3)
	root.add_child(label)

	var back := ColorRect.new()
	back.position = Vector2(0.0, 16.0)
	back.size = Vector2(BAR_W, BAR_H)
	back.color = Color(0.05, 0.05, 0.05, 0.78)
	root.add_child(back)

	var fill := ColorRect.new()
	fill.position = Vector2(0.0, 16.0)
	fill.size = Vector2(BAR_W, BAR_H)
	fill.color = Color(0.18, 0.85, 0.27, 0.95)
	root.add_child(fill)

	var info := {"root": root, "label": label, "fill": fill}
	_bars[ship_id] = info
	return info


func _cleanup_bars(active_ids: Array) -> void:
	for key in _bars.keys():
		if key in active_ids:
			continue
		var info: Dictionary = _bars[key]
		var root := info.get("root") as Control
		if root != null:
			root.queue_free()
		_bars.erase(key)


func _hide_all() -> void:
	for info_v in _bars.values():
		var info: Dictionary = info_v
		var root := info.get("root") as Control
		if root != null:
			root.visible = false
