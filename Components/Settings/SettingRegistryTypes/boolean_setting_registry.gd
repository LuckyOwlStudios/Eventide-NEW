class_name BooleanSettingRegistry
extends SettingRegistry

@export var default_value: bool

func get_default_value() -> Variant:
	return default_value

func normalize_value(value: Variant) -> Variant:
	return bool(value)
