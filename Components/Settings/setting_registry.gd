class_name SettingRegistry
extends Resource

## Stable, unique ID. Mod settings should use a namespace, e.g. "my_mod.camera_shake".
@export var id: StringName
## Name shown in the settings UI.
@export var display_name: String
@export_multiline var description: String
## Stable category ID. A matching SettingCategoryRegistry is optional.
@export var category_id: StringName = &"general"
@export var sort_order: int = 0

func get_default_value() -> Variant:
	return null

func normalize_value(value: Variant) -> Variant:
	return value

func is_valid_definition() -> bool:
	return not id.is_empty() and not display_name.is_empty()
