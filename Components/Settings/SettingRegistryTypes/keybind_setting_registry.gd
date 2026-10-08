class_name KeybindSettingRegistry
extends SettingRegistry

## InputMap action controlled by this setting.
@export var action: StringName
## Heading used to group this action in the keybind menu.
@export var keybind_category: String = "General"
## Default physical keys. Multiple entries allow alternatives such as W and Up.
## This is populated from the Input Map at runtime; registry resources may leave it empty.
@export var default_physical_keys: PackedInt64Array

func get_default_value() -> Variant:
	return default_physical_keys.duplicate()

func normalize_value(value: Variant) -> Variant:
	var keys := PackedInt64Array()
	if value is PackedInt64Array:
		for keycode in value:
			if int(keycode) > 0 and not keys.has(int(keycode)):
				keys.append(int(keycode))
	elif value is Array:
		for keycode in value:
			if int(keycode) > 0 and not keys.has(int(keycode)):
				keys.append(int(keycode))
	elif value is int and int(value) > 0:
		keys.append(int(value))
	return keys if not keys.is_empty() else default_physical_keys.duplicate()

func is_valid_definition() -> bool:
	return super.is_valid_definition() and not action.is_empty()
