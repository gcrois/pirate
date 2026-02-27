extends MeshInstance3D

# These must match the shader uniforms exactly.
@export var wave_height: float = 0.8
@export var wave_speed:  float = 1.0
@export var wave_scale:  float = 0.25

# Matches MAX_WAKES in shader
const MAX_WAKES = 2

# Accumulated time that matches the shader's TIME built-in.
var _elapsed: float = 0.0

var _ocean_mat: ShaderMaterial
var _inner_ocean: MeshInstance3D
var _inner_mat: ShaderMaterial

# Publicly accessible ships for inner meshes to follow
var s0: ShipController = null
var s1: ShipController = null

# Fallback neutral texture (0.5 gray) to prevent shader artifacts in empty array slots
var _neutral_tex: ImageTexture

func _ready() -> void:
	add_to_group("ocean")
	
	# Create a 1x1 neutral gray texture for empty wake slots
	var img = Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.5, 0.5, 0.5))
	_neutral_tex = ImageTexture.create_from_image(img)
	
	_ocean_mat = ShipController._get_shader_material(self)
	_inner_ocean = get_tree().get_first_node_in_group("inner_ocean") as MeshInstance3D

func _process(delta: float) -> void:
	_elapsed += delta
	_update_shader_params()

func _update_shader_params() -> void:
	if _ocean_mat == null:
		_ocean_mat = ShipController._get_shader_material(self)
	
	var ships = get_tree().get_nodes_in_group("ship")
	
	# Determine slot 0 and 1 deterministically
	s0 = null
	s1 = null
	
	# Priority 1: The player-controlled vessel (not AI)
	# Priority 2: The surfboard (if both are AI)
	for s in ships:
		if not s is ShipController: continue
		if not s.is_ai:
			s0 = s
		elif s.is_surfboard:
			s1 = s
		else:
			if s1 == null: s1 = s
			elif s0 == null: s0 = s
	
	# Flip if s0 is still empty but s1 has something
	if s0 == null and s1 != null:
		s0 = s1
		s1 = null
	
	# Collect all inner ocean materials
	var inner_mats: Array[ShaderMaterial] = []
	var inners = get_tree().get_nodes_in_group("inner_ocean")
	for inn in inners:
		var m = ShipController._get_shader_material(inn as MeshInstance3D)
		if m: inner_mats.append(m)
		# Update the individual follow_ship_index for each inner material
		# based on the node's script property
		if m and inn.get("follow_index") != null:
			m.set_shader_parameter("follow_ship_index", inn.get("follow_index"))

	for i in 2:
		var s = s0 if i == 0 else s1
		var pos = s.global_position if s else Vector3.ZERO
		var spd = s._wave_speed if s else 0.0
		var tex = s._wake_controller.wake_texture if (s and s._wake_controller) else _neutral_tex
		var h_len = 0.0
		var h_wid = 0.0
		if s:
			h_len = s.surfboard_half_length if s.is_surfboard else 4.5
			h_wid = s.surfboard_half_width if s.is_surfboard else 1.75
		
		var s_idx = str(i)
		
		# Push to outer ocean
		if _ocean_mat:
			_ocean_mat.set_shader_parameter("ship_pos_" + s_idx, pos)
			_ocean_mat.set_shader_parameter("ship_spd_" + s_idx, spd)
			_ocean_mat.set_shader_parameter("wake_tex_" + s_idx, tex)
			_ocean_mat.set_shader_parameter("ship_len_" + s_idx, h_len)
			_ocean_mat.set_shader_parameter("ship_wid_" + s_idx, h_wid)
			_ocean_mat.set_shader_parameter("ocean_size_meters", 100.0)
			
		# Push to ALL inner oceans
		for im in inner_mats:
			im.set_shader_parameter("ship_pos_" + s_idx, pos)
			im.set_shader_parameter("ship_spd_" + s_idx, spd)
			im.set_shader_parameter("wake_tex_" + s_idx, tex)
			im.set_shader_parameter("ship_len_" + s_idx, h_len)
			im.set_shader_parameter("ship_wid_" + s_idx, h_wid)
			im.set_shader_parameter("ocean_size_meters", 100.0)

## Returns the wave surface height at a world-space position.
func get_wave_height(world_pos: Vector3) -> float:
	var t: float = _elapsed * wave_speed
	var p: Vector2 = Vector2(world_pos.x, world_pos.z)
	var s: float   = wave_scale
	var amp: float = wave_height
	var w: float   = 0.0
	w += sin(Vector2( 0.800,  0.600).dot(p) * s * 1.00 + t * 1.00) * amp * 1.000
	w += sin(Vector2( 0.980,  0.200).dot(p) * s * 1.60 + t * 0.80) * amp * 0.600
	w += sin(Vector2( 0.195,  0.981).dot(p) * s * 2.20 + t * 1.30) * amp * 0.350
	w += sin(Vector2(-0.686,  0.728).dot(p) * s * 3.80 + t * 2.00) * amp * 0.180
	w += sin(Vector2( 0.530, -0.848).dot(p) * s * 6.50 + t * 2.60) * amp * 0.090
	w += sin(Vector2(-0.978,  0.208).dot(p) * s * 10.0 + t * 1.50) * amp * 0.045
	return w
