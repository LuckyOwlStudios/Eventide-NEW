class_name BaseCamera3D
extends Camera3D
## A camera whose field of view is the one the player chose in the settings, and which things in the game can zoom.
##
## An effect (the jump drive charging, say) zooms the view with [method set_field_of_view_multiplier]: the
## field of view is the player's setting times every effect's multiplier. Each effect has a name of its own, so
## two of them never undo each other, and a change in the setting while one is running keeps it running.

const FIELD_OF_VIEW_SETTING: StringName = &"controls.field_of_view"
## However much effects zoom, the field of view stays between these (in degrees).
const MINIMUM_FIELD_OF_VIEW := 20.0
const MAXIMUM_FIELD_OF_VIEW := 130.0

var _base_field_of_view := 75.0
var _multipliers: Dictionary[StringName, float] = {}


func _ready() -> void:
	_apply_field_of_view(Settings.get_setting(FIELD_OF_VIEW_SETTING, 75.0))
	Settings.setting_changed.connect(_on_setting_changed)


## The field of view the player chose, before any effect, in degrees.
func get_base_field_of_view() -> float:
	return _base_field_of_view


## Zooms the view for [param source]: [param multiplier] under 1 narrows the field of view (zooms in) and over 1 widens
## it. A multiplier of 1 takes the effect away.
func set_field_of_view_multiplier(source: StringName, multiplier: float) -> void:
	if is_equal_approx(multiplier, 1.0):
		_multipliers.erase(source)
	else:
		_multipliers[source] = maxf(multiplier, 0.05)
	_refresh_field_of_view()


## What [param source] is multiplying the field of view by now (1 for none).
func get_field_of_view_multiplier(source: StringName) -> float:
	return _multipliers.get(source, 1.0)


func _on_setting_changed(id: StringName, value: Variant) -> void:
	if id == FIELD_OF_VIEW_SETTING:
		_apply_field_of_view(value)


func _apply_field_of_view(value: Variant) -> void:
	_base_field_of_view = clampf(float(value), 60.0, 110.0)
	_refresh_field_of_view()


func _refresh_field_of_view() -> void:
	var zoomed := _base_field_of_view
	for multiplier in _multipliers.values():
		zoomed *= multiplier
	fov = clampf(zoomed, MINIMUM_FIELD_OF_VIEW, MAXIMUM_FIELD_OF_VIEW)
