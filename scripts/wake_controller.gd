class_name WakeController
extends Node

@export var ocean_size_meters: float = 80.0
@export var viewport_resolution: int = 1024
@export var water_advection_strength: float = 0.8

var _viewport: SubViewport
var _feedback_rect: ColorRect
var _brush_rect: ColorRect
var _feedback_mat: ShaderMaterial
var _brush_mat: ShaderMaterial

var _last_ship_pos: Vector3

# Used to inject into the ocean material
var wake_texture: ViewportTexture

func _ready() -> void:
	name = "WakeController"
	
	# Create the SubViewport
	_viewport = SubViewport.new()
	_viewport.size = Vector2(viewport_resolution, viewport_resolution)
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	add_child(_viewport)
	
	# Initially force clear it to gray (0.5), so we don't start with random memory junk
	RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5, 1.0))
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	
	# Load shaders
	var feedback_shader = preload("res://shaders/wake_feedback.gdshader")
	var brush_shader = preload("res://shaders/wake_brush.gdshader")
	
	# Feedback Rect (Bottom Layer)
	_feedback_mat = ShaderMaterial.new()
	_feedback_mat.shader = feedback_shader
	_feedback_mat.set_shader_parameter("texel_size", Vector2.ONE / float(max(1, viewport_resolution)))
	_feedback_mat.set_shader_parameter("blur_radius_texels", 1.15)
	
	_feedback_rect = ColorRect.new()
	_feedback_rect.material = _feedback_mat
	_feedback_rect.size = Vector2(viewport_resolution, viewport_resolution)
	_viewport.add_child(_feedback_rect)
	
	# Procedural Brush Rect (Top Layer)
	_brush_mat = ShaderMaterial.new()
	_brush_mat.shader = brush_shader
	
	_brush_rect = ColorRect.new()
	_brush_rect.material = _brush_mat
	_brush_rect.size = Vector2(viewport_resolution, viewport_resolution)
	_viewport.add_child(_brush_rect)
	
	wake_texture = _viewport.get_texture()


func process_wake(
	ship_position: Vector3,
	ship_basis: Basis,
	ship_velocity: Vector3,
	ship_speed: float,
	h_len: float,
	h_wid: float,
	draft: float,
	contact_factor: float,
	relative_speed: float,
	water_displacement: Vector2
) -> void:
	if not _last_ship_pos:
		_last_ship_pos = ship_position
		
	# 1. Update offset for feedback scrolling
	var movement: Vector3 = ship_position - _last_ship_pos
	# Advect wake with both carrier motion and ambient water drift.
	var advect_x: float = movement.x + water_displacement.x * water_advection_strength
	var advect_z: float = movement.z + water_displacement.y * water_advection_strength
	var uv_offset_x: float = advect_x / ocean_size_meters
	var uv_offset_y: float = advect_z / ocean_size_meters 
	
	_feedback_mat.set_shader_parameter("movement_offset", Vector2(uv_offset_x, uv_offset_y))
	
	# Motion-adaptive fade: preserve history when contact + relative motion are strong.
	var wake_motion: float = clamp(max(ship_speed / 6.0, relative_speed / 6.0), 0.0, 1.0) * clamp(contact_factor, 0.0, 1.0)
	var fade_bonus = lerp(0.026, 0.003, wake_motion)
	_feedback_mat.set_shader_parameter("dynamic_fade", fade_bonus)
	
	# 2. Update brush physics variables
	_brush_mat.set_shader_parameter("ship_position", ship_position)
	
	# Convert basis to a flat array/transform for the shader mat3
	var b = ship_basis
	_brush_mat.set_shader_parameter("ship_basis", Basis(b.x, b.y, b.z)) 
	
	_brush_mat.set_shader_parameter("ship_velocity", ship_velocity)
	_brush_mat.set_shader_parameter("ship_speed", ship_speed)
	_brush_mat.set_shader_parameter("relative_speed", relative_speed)
	_brush_mat.set_shader_parameter("contact_factor", contact_factor)
	_brush_mat.set_shader_parameter("ocean_size_meters", ocean_size_meters)
	
	# Dimensions
	_brush_mat.set_shader_parameter("ship_half_length", h_len)
	_brush_mat.set_shader_parameter("ship_half_width", h_wid)
	_brush_mat.set_shader_parameter("ship_draft", draft)
	
	_last_ship_pos = ship_position
