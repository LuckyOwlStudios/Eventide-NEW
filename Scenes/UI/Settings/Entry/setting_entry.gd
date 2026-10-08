class_name SettingEntry
extends HBoxContainer

signal description_requested(text: String)

@onready var focus_indicator: ColorRect = %FocusIndicator
@onready var name_label: Label = %NameLabel
@onready var value_container: HBoxContainer = %ValueContainer
@onready var add_keybind_button: Button = %AddKeybindButton
@onready var reset_button: Button = %ResetButton

var definition: SettingRegistry
var _value_control: Control
var _value_label: Label
var _capturing_keybind := false
var _capture_appends_key := false
var _updating_control := false
var _hovered := false
var _pointer_focused_control: Control

func _ready() -> void:
	set_process_input(false)
	add_keybind_button.hide()
	add_keybind_button.pressed.connect(_begin_additive_keybind_capture)
	reset_button.pressed.connect(_reset_to_default)
	_register_interactive(add_keybind_button)
	_register_interactive(reset_button)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	Settings.setting_changed.connect(_on_setting_changed)

func setup(setting_definition: SettingRegistry) -> void:
	definition = setting_definition
	if definition is KeybindSettingRegistry:
		add_to_group(&"keybind_setting_entries")
		add_keybind_button.show()
	else:
		add_keybind_button.hide()
	name_label.text = definition.display_name
	_build_value_control()
	_refresh_from_setting()

func focus_value_control() -> void:
	if is_instance_valid(_value_control):
		_value_control.grab_focus()

func _build_value_control() -> void:
	for child in value_container.get_children():
		child.queue_free()
	_value_control = null
	_value_label = null

	if definition is BooleanSettingRegistry:
		_build_stepper(_on_boolean_previous, _on_boolean_next)
	elif definition is IntSettingRegistry:
		var slider := _build_numeric_slider(
			float(definition.min_value),
			float(definition.max_value),
			1.0,
			_on_int_changed
		)
		_value_control = slider
	elif definition is FloatSettingRegistry:
		var slider := _build_numeric_slider(
			definition.min_value,
			definition.max_value,
			definition.step,
			_on_float_changed
		)
		_value_control = slider
	elif definition is EnumSettingRegistry:
		_build_stepper(_on_enum_previous, _on_enum_next)
	elif definition is KeybindSettingRegistry:
		var button := Button.new()
		button.custom_minimum_size.x = 250.0
		button.theme_type_variation = &"SettingsButton"
		button.pressed.connect(_begin_replacement_keybind_capture)
		_value_control = button
		value_container.add_child(button)
		_register_interactive(button)
	else:
		var unsupported := Label.new()
		unsupported.theme_type_variation = &"SettingsLabel"
		unsupported.text = "Unsupported setting type"
		_value_control = unsupported
		value_container.add_child(unsupported)

func _build_numeric_slider(
		min_value: float,
		max_value: float,
		step: float,
		value_changed_callback: Callable
) -> HSlider:
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 220.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.theme_type_variation = &"SettingsSlider"
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value_changed.connect(value_changed_callback)
	value_container.add_child(slider)
	_register_interactive(slider)
	_value_label = Label.new()
	_value_label.custom_minimum_size.x = 72.0
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.theme_type_variation = &"SettingsLabel"
	value_container.add_child(_value_label)
	return slider

func _build_stepper(previous_callback: Callable, next_callback: Callable) -> void:
	var previous := Button.new()
	previous.custom_minimum_size = Vector2(30.0, 30.0)
	previous.theme_type_variation = &"SettingsButton"
	previous.text = "<"
	previous.pressed.connect(previous_callback)
	value_container.add_child(previous)
	_register_interactive(previous)

	_value_label = Label.new()
	_value_label.custom_minimum_size.x = 220.0
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.theme_type_variation = &"SettingsLabel"
	value_container.add_child(_value_label)

	var next := Button.new()
	next.custom_minimum_size = Vector2(30.0, 30.0)
	next.theme_type_variation = &"SettingsButton"
	next.text = ">"
	next.pressed.connect(next_callback)
	value_container.add_child(next)
	_register_interactive(next)
	_value_control = previous

func _refresh_from_setting() -> void:
	if definition == null or not is_instance_valid(_value_control):
		return
	var value: Variant = Settings.get_setting(definition.id)
	_updating_control = true
	if definition is BooleanSettingRegistry:
		_value_label.text = "On" if bool(value) else "Off"
	elif definition is IntSettingRegistry:
		(_value_control as HSlider).value = int(value)
		_update_int_label(int(value))
	elif definition is FloatSettingRegistry:
		(_value_control as HSlider).value = float(value)
		_update_float_label(float(value), definition.step)
	elif definition is EnumSettingRegistry:
		_value_label.text = _enum_option_name(StringName(value))
	elif definition is KeybindSettingRegistry and not _capturing_keybind:
		(_value_control as Button).text = _keybind_text(value)
	_updating_control = false
	_update_reset_button(value)

func _on_boolean_previous() -> void:
	Settings.set_setting(definition.id, not bool(Settings.get_setting(definition.id)))

func _on_boolean_next() -> void:
	_on_boolean_previous()

func _on_int_changed(value: float) -> void:
	var int_value := roundi(value)
	_update_int_label(int_value)
	if not _updating_control:
		Settings.set_setting(definition.id, int_value)

func _on_float_changed(value: float) -> void:
	_update_float_label(value, definition.step)
	if not _updating_control:
		Settings.set_setting(definition.id, value)

func _on_enum_previous() -> void:
	_step_enum(-1)

func _on_enum_next() -> void:
	_step_enum(1)

func _step_enum(direction: int) -> void:
	var options: Array = Settings.get_enum_options(definition.id)
	if options.is_empty():
		return
	var current := StringName(Settings.get_setting(definition.id))
	var current_index := 0
	for index in options.size():
		if StringName(options[index].get("id", &"")) == current:
			current_index = index
			break
	var next_index := wrapi(current_index + direction, 0, options.size())
	Settings.set_setting(definition.id, StringName(options[next_index].get("id", &"")))

func _enum_option_name(option_id: StringName) -> String:
	for option in Settings.get_enum_options(definition.id):
		if StringName(option.get("id", &"")) == option_id:
			return String(option.get("name", option_id))
	return String(option_id)

func _begin_replacement_keybind_capture() -> void:
	_begin_keybind_capture(false)

func _begin_additive_keybind_capture() -> void:
	_begin_keybind_capture(true)

func _begin_keybind_capture(append_key: bool) -> void:
	for entry in get_tree().get_nodes_in_group(&"keybind_setting_entries"):
		if entry != self and entry.has_method(&"cancel_keybind_capture"):
			entry.cancel_keybind_capture()
	_capturing_keybind = true
	_capture_appends_key = append_key
	if _capture_appends_key:
		add_keybind_button.text = "PRESS..."
	else:
		(_value_control as Button).text = "Press a key..."
	set_process_input(true)

func cancel_keybind_capture() -> void:
	if not _capturing_keybind:
		return
	_capturing_keybind = false
	_capture_appends_key = false
	add_keybind_button.text = "ADD"
	set_process_input(false)
	_refresh_from_setting()

func _input(event: InputEvent) -> void:
	if not _capturing_keybind or not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var keycode: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if keycode != KEY_ESCAPE and keycode != KEY_NONE:
		var updated_keys := PackedInt64Array()
		if _capture_appends_key:
			var current_value: Variant = Settings.get_setting(definition.id)
			if current_value is PackedInt64Array:
				updated_keys = current_value.duplicate()
		if not updated_keys.has(int(keycode)):
			updated_keys.append(int(keycode))
		Settings.set_setting(definition.id, updated_keys)
	cancel_keybind_capture()

func _reset_to_default() -> void:
	if definition != null:
		Settings.reset_setting(definition.id)

func _on_setting_changed(id: StringName, _value: Variant) -> void:
	if definition != null and id == definition.id:
		_refresh_from_setting()

func _update_reset_button(value: Variant) -> void:
	var is_modified: bool = value != definition.get_default_value()
	reset_button.disabled = not is_modified
	reset_button.mouse_filter = Control.MOUSE_FILTER_STOP if is_modified else Control.MOUSE_FILTER_IGNORE
	reset_button.modulate.a = 1.0 if is_modified else 0.0

func _update_float_label(value: float, step: float) -> void:
	if not is_instance_valid(_value_label):
		return
	var decimals := 0
	var scaled_step := step
	while decimals < 4 and not is_equal_approx(scaled_step, roundf(scaled_step)):
		decimals += 1
		scaled_step *= 10.0
	_value_label.text = String.num(value, decimals)

func _update_int_label(value: int) -> void:
	if is_instance_valid(_value_label):
		_value_label.text = str(value)

func _keybind_text(value: Variant) -> String:
	if not value is PackedInt64Array:
		return "Unbound"
	var names := PackedStringArray()
	for keycode in value:
		var event := InputEventKey.new()
		event.physical_keycode = int(keycode) as Key
		names.append(event.as_text_physical_keycode())
	return " / ".join(names) if not names.is_empty() else "Unbound"

func _register_interactive(control: Control) -> void:
	control.focus_entered.connect(_on_interactive_focus_entered)
	control.focus_exited.connect(_on_interactive_focus_exited)
	control.mouse_entered.connect(_request_description)
	control.gui_input.connect(_on_interactive_gui_input.bind(control))

func _on_interactive_gui_input(event: InputEvent, control: Control) -> void:
	if event is InputEventMouseButton and event.pressed:
		_pointer_focused_control = control
	elif event is InputEventKey and event.pressed:
		# Once the player uses the keyboard/controller, preserve focus when the
		# pointer leaves so navigation still has a visible selection.
		_pointer_focused_control = null

func _on_interactive_focus_entered() -> void:
	focus_indicator.modulate.a = 1.0
	name_label.add_theme_color_override(&"font_color", Color.WHITE)
	_request_description()

func _on_interactive_focus_exited() -> void:
	_refresh_focus_state.call_deferred()

func _on_mouse_entered() -> void:
	_hovered = true
	focus_indicator.modulate.a = 1.0
	name_label.add_theme_color_override(&"font_color", Color.WHITE)
	_request_description()

func _on_mouse_exited() -> void:
	_hovered = false
	if is_instance_valid(_pointer_focused_control) and _pointer_focused_control.has_focus():
		_pointer_focused_control.release_focus()
	_pointer_focused_control = null
	_refresh_focus_state.call_deferred()

func _refresh_focus_state() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var focus_owner := viewport.gui_get_focus_owner()
	var contains_focus := focus_owner != null and is_ancestor_of(focus_owner)
	var is_highlighted := _hovered or contains_focus
	focus_indicator.modulate.a = 1.0 if is_highlighted else 0.0
	if not is_highlighted:
		name_label.remove_theme_color_override(&"font_color")

func _request_description() -> void:
	if definition != null:
		description_requested.emit(definition.description)
