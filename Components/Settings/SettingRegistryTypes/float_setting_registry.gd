class_name FloatSettingRegistry
extends SettingRegistry

@export var default_value: float
@export var min_value: float
@export var max_value: float
@export_range(0.001, 1.0, 0.001, "or_greater") var step: float = 0.001

func get_default_value() -> Variant:
	return normalize_value(default_value)

func normalize_value(value: Variant) -> Variant:
	var number := clampf(float(value), min_value, max_value)
	if step > 0.0:
		number = snappedf(number, step)
	return number

func is_valid_definition() -> bool:
	return super.is_valid_definition() and min_value <= max_value and step > 0.0
