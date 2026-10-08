@tool
class_name DimmerOverlay
extends ColorRect

## Full-screen color overlay. Set ColorRect.color to the desired final color.

@export_range(0.0, 1.0, 0.01) var dim_amount := 0.0:
	set(value):
		dim_amount = clampf(value, 0.0, 1.0)
		_apply_dim_amount()

@export_range(0.0, 2.0, 0.01, "or_greater") var fade_duration := 0.2

var _target_amount := 0.0
var _fade_speed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_dim_amount()
	set_process(false)

func _process(delta: float) -> void:
	dim_amount = move_toward(dim_amount, _target_amount, _fade_speed * delta)
	if is_equal_approx(dim_amount, _target_amount):
		dim_amount = _target_amount
		set_process(false)
		if is_zero_approx(dim_amount):
			hide()

func fade_in(duration := -1.0) -> void:
	_fade_to(1.0, fade_duration if duration < 0.0 else duration)

func fade_out(duration := -1.0) -> void:
	_fade_to(0.0, fade_duration if duration < 0.0 else duration)

func set_dim_immediate(amount: float) -> void:
	set_process(false)
	_target_amount = clampf(amount, 0.0, 1.0)
	dim_amount = _target_amount
	visible = dim_amount > 0.0

func _fade_to(target: float, duration: float) -> void:
	_target_amount = clampf(target, 0.0, 1.0)
	if duration <= 0.0 or is_equal_approx(dim_amount, _target_amount):
		set_dim_immediate(_target_amount)
		return
	show()
	_fade_speed = absf(_target_amount - dim_amount) / duration
	set_process(true)

func _apply_dim_amount() -> void:
	self_modulate.a = dim_amount
