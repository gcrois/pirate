extends Control

@export var world_extent: float = 360.0
@export var island_color: Color = Color(0.92, 0.83, 0.58, 0.9)
@export var island_name_color: Color = Color(0.08, 0.06, 0.02, 0.95)
@export var player_color: Color = Color(0.2, 1.0, 0.35, 1.0)
@export var enemy_color: Color = Color(1.0, 0.35, 0.3, 1.0)
@export var neutral_color: Color = Color(1.0, 0.82, 0.32, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var map_rect := Rect2(Vector2.ZERO, size)
	draw_rect(map_rect, Color(0.03, 0.08, 0.14, 0.78), true)
	draw_rect(map_rect, Color(0.74, 0.88, 1.0, 0.95), false, 2.0)

	_draw_grid()
	_draw_islands()
	_draw_actors()
	_draw_north_marker()


func _draw_grid() -> void:
	var center := size * 0.5
	var grid_color := Color(0.35, 0.55, 0.7, 0.28)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), grid_color, 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), grid_color, 1.0)


func _draw_islands() -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = max(10, get_theme_default_font_size() - 2)
	var islands: Array = get_tree().get_nodes_in_group("island")
	for n in islands:
		if n is not Node3D:
			continue
		var island := n as Node3D
		var radius: float = float(island.get("radius"))
		var map_pos := _world_to_map(island.global_position)
		var map_radius: float = max(2.0, (radius / world_extent) * size.x * 0.5)
		draw_circle(map_pos, map_radius, island_color)
		draw_arc(map_pos, map_radius, 0.0, TAU, 18, Color(0.22, 0.16, 0.08, 0.95), 1.4)
		if font != null:
			draw_string(font, map_pos + Vector2(map_radius + 3.0, -2.0), island.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, island_name_color)


func _draw_actors() -> void:
	var actors: Array = get_tree().get_nodes_in_group("ship")
	for n in actors:
		if n is not Node3D:
			continue
		var actor := n as Node3D
		if actor.get("actor_type") == null:
			continue
		var map_pos := _world_to_map(actor.global_position)
		var faction := str(actor.get("faction"))
		var color := player_color
		if faction == "enemy":
			color = enemy_color
		elif faction == "neutral":
			color = neutral_color
		draw_circle(map_pos, 4.5, color)
		var fwd := Vector2(-actor.transform.basis.z.x, -actor.transform.basis.z.z)
		if fwd.length_squared() > 0.0001:
			fwd = fwd.normalized()
		else:
			fwd = Vector2.UP
		draw_line(map_pos, map_pos + fwd * 10.0, color.darkened(0.4), 2.0)


func _draw_north_marker() -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var font_size: int = max(11, get_theme_default_font_size())
	draw_string(font, Vector2(size.x * 0.5 - 5.0, 14.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.98, 1.0, 1.0))


func _world_to_map(world_pos: Vector3) -> Vector2:
	var nx: float = clamp(world_pos.x / world_extent, -1.0, 1.0)
	var nz: float = clamp(world_pos.z / world_extent, -1.0, 1.0)
	return Vector2(size.x * (0.5 + nx * 0.5), size.y * (0.5 + nz * 0.5))
