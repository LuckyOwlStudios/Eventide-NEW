class_name BlinkingOmniLight3D
extends OmniLight3D

@export var Enabled: bool = true
## Number of times the gradient is played per second.
@export_range(0.01, 20.0, 0.01) var Frequency: float = 1.0

## Controls the intensity of the light over one blink cycle.
## The RED channel represents the intensity (0-1).
@export var Pulse: Gradient = Gradient.new()

var _base_energy: float

func _ready() -> void:
	_base_energy = light_energy

func _process(_delta: float) -> void:
	if not Enabled:
		light_energy = 0.0
		return

	var time := Time.get_ticks_msec() / 1000.0
	@warning_ignore("shadowed_variable_base_class")
	var position := fmod(time * Frequency, 1.0)

	var color := Pulse.sample(position)
	var intensity := color.r

	light_energy = _base_energy * intensity
