class_name BaseCamera3D
extends Camera3D

const FIELD_OF_VIEW_SETTING: StringName = &"controls.field_of_view"

func _ready() -> void:
	_apply_field_of_view(Settings.get_setting(FIELD_OF_VIEW_SETTING, 75.0))
	Settings.setting_changed.connect(_on_setting_changed)

func _on_setting_changed(id: StringName, value: Variant) -> void:
	if id == FIELD_OF_VIEW_SETTING:
		_apply_field_of_view(value)

func _apply_field_of_view(value: Variant) -> void:
	fov = clampf(float(value), 60.0, 110.0)
