@tool
class_name BlurOverlay
extends ColorRect

## Full-screen blur with a normalized amount and pause-safe transitions.

const BLUR_SHADER_MATERIAL := preload("res://Assets/Shaders/blur_shader_material.tres")

@export_range(0.0, 1.0, 0.01) var blur_amount := 0.0:
	set(value):
		blur_amount = clampf(value, 0.0, 1.0)
		_apply_blur_amount()

@export_range(0.0, 8.0, 0.1) var maximum_blur_lod := 3.5:
	set(value):
		maximum_blur_lod = maxf(value, 0.0)
		_apply_blur_amount()

@export_range(0.0, 2.0, 0.01, "or_greater") var fade_duration := 0.2

var _target_amount := 0.0
var _fade_speed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if material == null or not material is ShaderMaterial:
		material = BLUR_SHADER_MATERIAL.duplicate()
	elif not Engine.is_editor_hint():
		material = material.duplicate()
	_apply_blur_amount()
	set_process(false)

func _process(delta: float) -> void:
	blur_amount = move_toward(blur_amount, _target_amount, _fade_speed * delta)
	if is_equal_approx(blur_amount, _target_amount):
		blur_amount = _target_amount
		set_process(false)
		if is_zero_approx(blur_amount):
			hide()

func fade_in(duration := -1.0) -> void:
	_fade_to(1.0, fade_duration if duration < 0.0 else duration)

func fade_out(duration := -1.0) -> void:
	_fade_to(0.0, fade_duration if duration < 0.0 else duration)

func set_blur_immediate(amount: float) -> void:
	set_process(false)
	_target_amount = clampf(amount, 0.0, 1.0)
	blur_amount = _target_amount
	visible = blur_amount > 0.0

func _fade_to(target: float, duration: float) -> void:
	_target_amount = clampf(target, 0.0, 1.0)
	if duration <= 0.0 or is_equal_approx(blur_amount, _target_amount):
		set_blur_immediate(_target_amount)
		return
	show()
	_fade_speed = absf(_target_amount - blur_amount) / duration
	set_process(true)

func _apply_blur_amount() -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(
			&"blur_lod",
			blur_amount * maximum_blur_lod
		)
