extends CanvasLayer

@export var y_offset: float = 8.0
@export var max_label_distance: float = 900.0

var _labels: Dictionary = {}


func _ready() -> void:
	layer = 12


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not camera.is_current():
		_hide_all()
		return

	var active_ids: Array = []
	var islands: Array = get_tree().get_nodes_in_group("island")
	for n in islands:
		if n is not Node3D:
			continue
		var island := n as Node3D
		var island_id: int = island.get_instance_id()
		active_ids.append(island_id)
		var label := _get_label(island_id)

		label.text = island.name
		var peak_height: float = float(island.get("peak_height"))
		var world_pos := island.global_position + Vector3(0.0, peak_height + y_offset, 0.0)
		var dist: float = camera.global_position.distance_to(world_pos)
		if dist > max_label_distance or camera.is_position_behind(world_pos):
			label.visible = false
			continue

		label.visible = true
		var screen_pos := camera.unproject_position(world_pos)
		label.position = screen_pos - Vector2(label.size.x * 0.5, label.size.y)

	_cleanup_labels(active_ids)


func _get_label(island_id: int) -> Label:
	if _labels.has(island_id):
		return _labels[island_id] as Label

	var label := Label.new()
	label.size = Vector2(220.0, 32.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.72, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	_labels[island_id] = label
	return label


func _cleanup_labels(active_ids: Array) -> void:
	for key in _labels.keys():
		if key in active_ids:
			continue
		var label := _labels[key] as Label
		if label != null:
			label.queue_free()
		_labels.erase(key)


func _hide_all() -> void:
	for label in _labels.values():
		var l := label as Label
		if l != null:
			l.visible = false
