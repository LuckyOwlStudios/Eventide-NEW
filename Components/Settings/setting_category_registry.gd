class_name SettingCategoryRegistry
extends Resource

## Stable category ID referenced by SettingRegistry resources.
@export var id: StringName
## Name shown on the settings tab or section heading.
@export var display_name: String
## Optional help text shown beneath the category name in the settings menu.
@export_multiline var description: String
## Empty for a top-level tab; otherwise this category appears inside its parent.
@export var parent_id: StringName
## Lower values appear first. Categories with the same value are ordered by name.
@export var sort_order: int = 0

func is_valid_definition() -> bool:
	return not id.is_empty() and not display_name.is_empty() and parent_id != id
