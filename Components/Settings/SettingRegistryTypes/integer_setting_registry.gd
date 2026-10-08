class_name IntSettingRegistry
extends SettingRegistry

@export var default_value: int = 0
@export var min_value: int = -100
@export var max_value: int = 100

func get_default_value() -> Variant:
	return normalize_value(default_value)

func normalize_value(value: Variant) -> Variant:
	return clampi(roundi(float(value)), min_value, max_value)

func is_valid_definition() -> bool:
	return super.is_valid_definition() and min_value <= max_value
