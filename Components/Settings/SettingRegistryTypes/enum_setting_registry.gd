class_name EnumSettingRegistry
extends SettingRegistry

## Stable saved values. Reordering these does not change a player's selection.
@export var option_ids: PackedStringArray
## User-facing labels corresponding to option_ids.
@export var option_names: PackedStringArray
@export var default_option_id: StringName
## Optional runtime provider for choices such as audio input devices.
@export var options_provider_id: StringName

func get_default_value() -> Variant:
	return default_option_id

func normalize_value(value: Variant) -> Variant:
	var option_id := StringName(value)
	if not options_provider_id.is_empty():
		return option_id
	return option_id if option_ids.has(String(option_id)) else default_option_id

func get_static_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for index in option_ids.size():
		options.append({
			"id": StringName(option_ids[index]),
			"name": option_names[index] if index < option_names.size() else option_ids[index],
		})
	return options

func is_valid_definition() -> bool:
	if not super.is_valid_definition():
		return false
	if not options_provider_id.is_empty():
		return not default_option_id.is_empty()
	return (
		not option_ids.is_empty()
		and option_ids.has(String(default_option_id))
		and (option_names.is_empty() or option_names.size() == option_ids.size())
	)
