extends Node3D

@export var ocean_material: ShaderMaterial
@export var wave_drift_scale: float = 0.45
@export var wake_footprint_meters: float = 64.0
@export var wake_buffer_resolution: int = 1536

# [steepness, amplitude, dir_degrees, frequency, speed, phase_degrees]
const _WAVES: Array = [
	[4.20, 2.8,  14.0, 0.019, 0.62,   0.0],
	[3.30, 2.1, 137.0, 0.031, 0.88,  41.0],
	[2.50, 1.5,  73.0, 0.058, 1.45,  83.0],
	[1.70, 1.0, 229.0, 0.097, 2.15,  19.0],
	[1.10, 0.7, 307.0, 0.149, 2.95, 127.0],
	[0.80, 0.4, 111.0, 0.236, 3.75, 211.0],
]

var _elapsed: float = 0.0

var s0 = null
var s1 = null

var _neutral_tex: ImageTexture


func _ready() -> void:
	add_to_group("ocean")

	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.5, 0.5, 0.5))
	_neutral_tex = ImageTexture.create_from_image(img)

	_push_wave_params()
	if ocean_material != null:
		ocean_material.set_shader_parameter("wave_time_seconds", _elapsed)


func _process(delta: float) -> void:
	_elapsed += delta
	if ocean_material != null:
		ocean_material.set_shader_parameter("wave_time_seconds", _elapsed)
	_update_ships_and_wake()


func _push_wave_params() -> void:
	if ocean_material == null:
		return

	var count := _WAVES.size()
	var st := PackedFloat32Array()
	var am := PackedFloat32Array()
	var di := PackedFloat32Array()
	var fr := PackedFloat32Array()
	var sp := PackedFloat32Array()
	var ph := PackedFloat32Array()
	for w in _WAVES:
		st.append(w[0])
		am.append(w[1])
		di.append(w[2])
		fr.append(w[3])
		sp.append(w[4])
		ph.append(w[5])

	ocean_material.set_shader_parameter("WaveCount", count)
	ocean_material.set_shader_parameter("WaveSteepnesses", st)
	ocean_material.set_shader_parameter("WaveAmplitudes", am)
	ocean_material.set_shader_parameter("WaveDirectionsDegrees", di)
	ocean_material.set_shader_parameter("WaveFrequencies", fr)
	ocean_material.set_shader_parameter("WaveSpeeds", sp)
	ocean_material.set_shader_parameter("WavePhases", ph)


func _update_ships_and_wake() -> void:
	if ocean_material == null:
		return

	s0 = null
	s1 = null
	for n in get_tree().get_nodes_in_group("ship"):
		if n.get("is_ai") == null:
			continue
		var a = n
		if not a.is_ai and s0 == null:
			s0 = a
		elif s1 == null:
			s1 = a

	if s0 == null and s1 != null:
		s0 = s1
		s1 = null

	for i in 2:
		var a = s0 if i == 0 else s1
		var pos = a.global_position if a else Vector3.ZERO
		var spd = a._wave_speed if a else 0.0
		var contact = a._wake_contact if a else 0.0
		var rel_spd = a._wake_rel_speed if a else 0.0
		var tex = a._wake_controller.wake_texture if a and a._wake_controller else _neutral_tex
		var h_len = (a.surfboard_half_length if a.actor_type == "surfboard" else 4.5) if a else 4.5
		var h_wid = (a.surfboard_half_width if a.actor_type == "surfboard" else 1.75) if a else 1.75
		var idx = str(i)
		ocean_material.set_shader_parameter("ship_pos_" + idx, pos)
		ocean_material.set_shader_parameter("ship_spd_" + idx, spd)
		ocean_material.set_shader_parameter("ship_contact_" + idx, contact)
		ocean_material.set_shader_parameter("ship_rel_spd_" + idx, rel_spd)
		ocean_material.set_shader_parameter("wake_tex_" + idx, tex)
		ocean_material.set_shader_parameter("ship_len_" + idx, h_len)
		ocean_material.set_shader_parameter("ship_wid_" + idx, h_wid)

	ocean_material.set_shader_parameter("ocean_size_meters", wake_footprint_meters)


func get_wave_height(world_pos: Vector3) -> float:
	var x := world_pos.x
	var z := world_pos.z
	var t := _elapsed
	var total := 0.0
	for w in _WAVES:
		var steepness: float = w[0]
		var dir_deg: float = w[2]
		var frequency: float = w[3]
		var speed: float = w[4]
		var phase_deg: float = w[5]
		var dir := Vector2(sin(dir_deg * TAU / 360.0), cos(dir_deg * TAU / 360.0))
		var p := phase_deg * TAU / 360.0
		total += steepness * sin(TAU * frequency * dir.dot(Vector2(x, z)) + speed * (t + p))
	return total / float(_WAVES.size())


func get_wave_velocity_xz(world_pos: Vector3) -> Vector2:
	var x := world_pos.x
	var z := world_pos.z
	var t := _elapsed
	var drift := Vector2.ZERO
	for w in _WAVES:
		var steepness: float = w[0]
		var amplitude: float = w[1]
		var dir_deg: float = w[2]
		var frequency: float = w[3]
		var speed: float = w[4]
		var phase_deg: float = w[5]
		var dir := Vector2(sin(dir_deg * TAU / 360.0), cos(dir_deg * TAU / 360.0))
		var p := phase_deg * TAU / 360.0
		var phi: float = TAU * frequency * dir.dot(Vector2(x, z)) + speed * (t + p)
		var horiz_vel: float = -steepness * amplitude * speed * sin(phi)
		drift += dir * horiz_vel
	if _WAVES.is_empty():
		return Vector2.ZERO
	return (drift / float(_WAVES.size())) * wave_drift_scale
