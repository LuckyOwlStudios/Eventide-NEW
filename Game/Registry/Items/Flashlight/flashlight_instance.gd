## Persistent state belonging to one flashlight. It goes wherever the flashlight goes (a pocket, a hand,
## the floor), so a flashlight dropped at 10% battery and still on lands exactly like that.
class_name FlashlightInstance
extends ItemInstance

signal power_level_changed(power_level: float)
## The light was switched on or off, by the player or because the battery ran out.
signal switched(is_on: bool)

@export_range(0.0, 100.0, 0.1) var power_level: float = 100.0:
	set(value):
		var normalized := clampf(value, 0.0, 100.0)
		if is_equal_approx(power_level, normalized):
			return
		power_level = normalized
		power_level_changed.emit(power_level)
		emit_changed()
		if power_level <= 0.0:
			is_on = false

## Whether the light is lit. It cannot be lit with no power left.
@export var is_on := false:
	set(value):
		var normalized := value and power_level > 0.0
		if is_on == normalized:
			return
		is_on = normalized
		switched.emit(is_on)
		emit_changed()

func toggle():
	is_on = !is_on
