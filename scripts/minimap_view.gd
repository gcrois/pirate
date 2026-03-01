extends Control

@export var radar_range_meters: float = 280.0
@export var edge_padding: float = 12.0

@export var background_color: Color = Color(0.03, 0.08, 0.14, 0.9)
@export var border_color: Color = Color(0.74, 0.92, 1.0, 0.96)
@export var ring_color: Color = Color(0.43, 0.72, 0.9, 0.3)
@export var heading_color: Color = Color(0.25, 0.9, 0.95, 0.65)
@export var island_color: Color = Color(0.95, 0.86, 0.58, 0.95)
@export var island_name_color: Color = Color(0.97, 0.98, 1.0, 0.95)
@export var player_color: Color = Color(0.18, 1.0, 0.42, 1.0)
@export var enemy_color: Color = Color(1.0, 0.34, 0.28, 1.0)
@export var neutral_color: Color = Color(1.0, 0.82, 0.3, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius: float = max(10.0, min(size.x, size.y) * 0.5 - edge_padding)
	var player := _get_player()

	_draw_backdrop(center, radius)
	_draw_rings(center, radius)

	if player == null:
		return

	var heading: float = _get_heading_angle(player)
	_draw_heading_line(center, radius)
	_draw_north_marker(center, radius, heading)
	_draw_islands(player, heading, center, radius)
	_draw_actors(player, heading, center, radius)
	_draw_player_marker(center)


func _draw_backdrop(center: Vector2, radius: float) -> void:
	draw_circle(center, radius + 5.0, Color(0.01, 0.02, 0.04, 0.35))
	draw_circle(center, radius, background_color)
	draw_arc(center, radius, 0.0, TAU, 112, border_color, 2.2)


func _draw_rings(center: Vector2, radius: float) -> void:
	for i in range(1, 4):
		var t: float = float(i) / 4.0
		draw_arc(center, radius * t, 0.0, TAU, 96, ring_color, 1.0)
	for i in range(8):
		var a: float = float(i) / 8.0 * TAU
		var dir := Vector2(cos(a), sin(a))
		draw_line(center + dir * (radius * 0.9), center + dir * radius, Color(0.62, 0.82, 0.95, 0.28), 1.0)


func _draw_heading_line(center: Vector2, radius: float) -> void:
	draw_line(center, center + Vector2(0.0, -radius + 14.0), heading_color, 1.8)


func _draw_islands(player: Node3D, heading: float, center: Vector2, radius: float) -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = max(10, get_theme_default_font_size() - 1)
	var islands: Array = get_tree().get_nodes_in_group("island")
	for n in islands:
		if n is not Node3D:
			continue
		var island := n as Node3D
		var projected := _project_to_radar(player.global_position, heading, island.global_position, radius)
		var map_pos: Vector2 = center + projected.position
		var island_radius: float = float(island.get("radius"))
		var map_radius: float = max(2.6, (island_radius / radar_range_meters) * radius)
		if projected.inside:
			draw_circle(map_pos, map_radius + 1.4, Color(0.02, 0.03, 0.05, 0.45))
			draw_circle(map_pos, map_radius, island_color)
		else:
			draw_circle(map_pos, 3.2, Color(island_color.r, island_color.g, island_color.b, 0.75))
		if font != null and projected.inside and projected.distance <= radar_range_meters * 0.95:
			draw_string(
				font,
				map_pos + Vector2(map_radius + 3.5, -2.0),
				island.name,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				island_name_color
			)


func _draw_actors(player: Node3D, heading: float, center: Vector2, radius: float) -> void:
	var actors: Array = get_tree().get_nodes_in_group("ship")
	for n in actors:
		if n is not Node3D:
			continue
		var actor := n as Node3D
		if actor == player:
			continue
		var faction := str(actor.get("faction"))
		var color := neutral_color
		if faction == "enemy":
			color = enemy_color
		elif faction == "player":
			color = player_color
		var projected := _project_to_radar(player.global_position, heading, actor.global_position, radius)
		if projected.inside:
			var p: Vector2 = center + projected.position
			_draw_actor_icon(p, color, _relative_forward(actor, heading))
		else:
			var edge_pos: Vector2 = center + projected.position
			var edge_dir: Vector2 = projected.position.normalized()
			_draw_edge_indicator(edge_pos, edge_dir, color)


func _draw_actor_icon(pos: Vector2, color: Color, fwd: Vector2) -> void:
	draw_circle(pos, 5.8, Color(color.r, color.g, color.b, 0.20))
	draw_circle(pos, 4.1, color)
	var right := Vector2(-fwd.y, fwd.x)
	var tip := pos + fwd * 10.0
	var back := pos - fwd * 3.0
	var left := back + right * 3.6
	var right_pt := back - right * 3.6
	draw_colored_polygon(PackedVector2Array([tip, left, right_pt]), color.darkened(0.24))


func _draw_edge_indicator(pos: Vector2, dir: Vector2, color: Color) -> void:
	var tangent := Vector2(-dir.y, dir.x)
	var tip := pos + dir * 1.8
	var base := pos - dir * 7.2
	var left := base + tangent * 4.0
	var right := base - tangent * 4.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(color.r, color.g, color.b, 0.9))


func _draw_player_marker(center: Vector2) -> void:
	draw_circle(center, 6.2, Color(player_color.r, player_color.g, player_color.b, 0.22))
	draw_circle(center, 4.6, player_color)
	draw_colored_polygon(
		PackedVector2Array([center + Vector2(0.0, -12.0), center + Vector2(6.5, 4.6), center + Vector2(-6.5, 4.6)]),
		player_color
	)


func _draw_north_marker(center: Vector2, radius: float, heading: float) -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var north_world := Vector2(0.0, -1.0)
	var north_local := north_world.rotated(-heading - PI * 0.5)
	var p := center + north_local * (radius - 14.0)
	var font_size: int = max(11, get_theme_default_font_size() + 1)
	draw_string(font, p + Vector2(-5.0, 4.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.98, 1.0, 1.0))


func _get_player() -> Node3D:
	var fallback: Node3D = null
	for n in get_tree().get_nodes_in_group("ship"):
		if n is not Node3D:
			continue
		var actor := n as Node3D
		var faction := str(actor.get("faction"))
		if faction == "player":
			return actor
		if fallback == null and not bool(actor.get("is_ai")):
			fallback = actor
	return fallback


func _get_heading_angle(actor: Node3D) -> float:
	var fwd := Vector2(-actor.transform.basis.z.x, -actor.transform.basis.z.z)
	if fwd.length_squared() < 0.0001:
		return -PI * 0.5
	return fwd.angle()


func _relative_forward(actor: Node3D, player_heading: float) -> Vector2:
	var actor_heading := _get_heading_angle(actor)
	var rel_angle := actor_heading - player_heading - PI * 0.5
	return Vector2(cos(rel_angle), sin(rel_angle))


func _project_to_radar(player_pos: Vector3, heading: float, world_pos: Vector3, radius: float) -> Dictionary:
	var world_delta := Vector2(world_pos.x - player_pos.x, world_pos.z - player_pos.z)
	var local: Vector2 = world_delta.rotated(-heading - PI * 0.5)
	var scaled: Vector2 = local * (radius / max(0.001, radar_range_meters))
	var inside: bool = scaled.length_squared() <= radius * radius
	var clamped: Vector2 = scaled
	if not inside and scaled.length_squared() > 0.0001:
		clamped = scaled.normalized() * radius
	return {
		"position": clamped,
		"inside": inside,
		"distance": world_delta.length()
	}
