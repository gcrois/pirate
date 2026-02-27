extends CanvasLayer

var _panel: PanelContainer
var _title_lbl: Label
var _gold_lbl: Label
var _cargo_lbl: Label
var _good_rows: Dictionary = {} # good -> {buy_btn, sell_btn, count}

var _current_island = null
var _closed_island = null


func _ready() -> void:
	layer = 20
	_build_ui()
	_panel.hide()


func _build_ui() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.04
	_panel.anchor_top = 0.06
	_panel.anchor_right = 0.96
	_panel.anchor_bottom = 0.94
	_panel.offset_left = 0.0
	_panel.offset_top = 0.0
	_panel.offset_right = 0.0
	_panel.offset_bottom = 0.0
	overlay.add_child(_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	_title_lbl = Label.new()
	_title_lbl.text = "Port"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 32)
	header.add_child(_title_lbl)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 44)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)
	vbox.add_child(header)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	_gold_lbl = Label.new()
	_gold_lbl.text = "Gold: 0"
	_gold_lbl.add_theme_font_size_override("font_size", 24)
	stats.add_child(_gold_lbl)
	_cargo_lbl = Label.new()
	_cargo_lbl.text = "Cargo: 0 / 0"
	_cargo_lbl.add_theme_font_size_override("font_size", 24)
	stats.add_child(_cargo_lbl)
	vbox.add_child(stats)

	vbox.add_child(HSeparator.new())

	for good in Economy.GOODS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_lbl := Label.new()
		name_lbl.text = good
		name_lbl.custom_minimum_size = Vector2(220, 0)
		name_lbl.add_theme_font_size_override("font_size", 24)
		row.add_child(name_lbl)

		var count_lbl := Label.new()
		count_lbl.text = "x0"
		count_lbl.custom_minimum_size = Vector2(90, 0)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.add_theme_font_size_override("font_size", 24)
		row.add_child(count_lbl)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		var buy_btn := Button.new()
		buy_btn.custom_minimum_size = Vector2(220, 52)
		buy_btn.add_theme_font_size_override("font_size", 22)
		buy_btn.pressed.connect(_on_buy.bind(good))
		row.add_child(buy_btn)

		var sell_btn := Button.new()
		sell_btn.custom_minimum_size = Vector2(220, 52)
		sell_btn.add_theme_font_size_override("font_size", 22)
		sell_btn.pressed.connect(_on_sell.bind(good))
		row.add_child(sell_btn)

		vbox.add_child(row)
		_good_rows[good] = {buy_btn = buy_btn, sell_btn = sell_btn, count = count_lbl}


func _process(_delta: float) -> void:
	_poll_proximity()
	if _panel.visible:
		_refresh_ui()


func _poll_proximity() -> void:
	var player = _get_player_actor()
	if player == null:
		_panel.hide()
		return

	if _current_island != null:
		var dist = player.global_position.distance_to(_current_island.global_position)
		if dist > _current_island.radius * 2.0:
			_current_island = null
			_closed_island = null
			_panel.hide()
		return

	for island in get_tree().get_nodes_in_group("island"):
		var dist = player.global_position.distance_to(island.global_position)
		if dist < island.radius * 1.5:
			if island == _closed_island:
				continue
			_current_island = island
			_closed_island = null
			_panel.show()
			_refresh_ui()
			break


func _get_player_actor():
	for n in get_tree().get_nodes_in_group("ship"):
		if n.get("is_ai") != null and not n.is_ai:
			return n
	return null


func _refresh_ui() -> void:
	var player = _get_player_actor()
	if player == null:
		return

	_gold_lbl.text = "Gold: %d" % player.gold
	_cargo_lbl.text = "Cargo: %d / %d" % [player.total_inventory(), player.max_inventory]
	if _current_island == null:
		return

	_title_lbl.text = "Port: %s" % _current_island.name
	for good in Economy.GOODS:
		var row = _good_rows[good]
		var buy_price = int(_current_island.buy_prices.get(good, 0))
		var sell_price = int(_current_island.sell_prices.get(good, 0))
		var count = int(player.inventory.get(good, 0))

		row["count"].text = "x%d" % count
		row["buy_btn"].text = "Buy  %dg" % buy_price
		row["buy_btn"].disabled = not player.can_buy() or player.gold < buy_price
		row["sell_btn"].text = "Sell %dg" % sell_price
		row["sell_btn"].disabled = count <= 0


func _on_buy(good: String) -> void:
	if _current_island == null:
		return
	var player = _get_player_actor()
	if player == null:
		return
	player.buy(good, _current_island.buy_prices.get(good, 0))
	_refresh_ui()


func _on_sell(good: String) -> void:
	if _current_island == null:
		return
	var player = _get_player_actor()
	if player == null:
		return
	player.sell(good, _current_island.sell_prices.get(good, 0))
	_refresh_ui()


func _on_close() -> void:
	_closed_island = _current_island
	_current_island = null
	_panel.hide()
