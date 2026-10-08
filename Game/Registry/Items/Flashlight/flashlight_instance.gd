## Persistent state belonging to one flashlight.
class_name FlashlightInstance
extends ItemInstance

signal power_level_changed(power_level: float)

@export_range(0.0, 100.0, 0.1) var power_level: float = 100.0:
	set(value):
		var normalized := clampf(value, 0.0, 100.0)
		if is_equal_approx(power_level, normalized):
			return
		power_level = normalized
		power_level_changed.emit(power_level)
		emit_changed()
