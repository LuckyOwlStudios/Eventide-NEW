extends Node

## Discovers setting definitions, stores player values, and applies keybinds.
## Mods should namespace definition IDs and place resources in the registry path.

signal registry_reloaded
signal setting_registered(definition: SettingRegistry)
signal setting_changed(id: StringName, value: Variant)
signal voice_chat_mode_changed(mode: VoiceChatMode)
signal keybind_changed(action: StringName, event: InputEventKey)

enum VoiceChatMode { DISABLED, OPEN_MIC, PUSH_TO_TALK }

const SETTINGS_REGISTRY_PATH := "res://Game/Registry/Settings"
const CATEGORY_REGISTRY_PATH := "res://Game/Registry/SettingCategories"
const SETTINGS_PATH := "user://settings.cfg"
const VOICE_CHAT_MODE_ID: StringName = &"voice.chat_mode"
const VOICE_CHAT_ACTION: StringName = &"voice_chat"
const RADIO_CHAT_ACTION: StringName = &"radio_chat"
const DISPLAY_MODE_ID: StringName = &"graphics.display_mode"
const VSYNC_ID: StringName = &"graphics.vsync"
const FPS_LIMIT_ID: StringName = &"graphics.fps_limit"
const MASTER_VOLUME_ID: StringName = &"master_volume"

var _definitions: Dictionary[StringName, SettingRegistry] = {}
var _categories: Dictionary[StringName, SettingCategoryRegistry] = {}
var _explicit_category_ids: Dictionary[StringName, bool] = {}
var _values: Dictionary[StringName, Variant] = {}
var _enum_option_providers: Dictionary[StringName, Callable] = {}
## Original keyboard bindings captured from Project Settings before saved settings are applied.
var _keybind_defaults: Dictionary[StringName, PackedInt64Array] = {}
var _config := ConfigFile.new()
var _loaded := false

var voice_chat_mode: VoiceChatMode:
	get:
		match StringName(get_setting(VOICE_CHAT_MODE_ID, &"push_to_talk")):
			&"disabled": return VoiceChatMode.DISABLED
			&"open_mic": return VoiceChatMode.OPEN_MIC
			_: return VoiceChatMode.PUSH_TO_TALK
	set(value):
		set_voice_chat_mode(value)

func _ready() -> void:
	register_enum_option_provider(&"audio_input_devices", _get_audio_input_options)
	reload_registry()
	load_settings()

func reload_registry() -> void:
	_definitions.clear()
	_categories.clear()
	_explicit_category_ids.clear()
	_scan_registry_directory(CATEGORY_REGISTRY_PATH)
	_scan_registry_directory(SETTINGS_REGISTRY_PATH)
	_discover_input_map_keybinds()
	for definition in _definitions.values():
		_ensure_category(definition.category_id)
	registry_reloaded.emit()

func register_definition(definition: SettingRegistry) -> bool:
	if definition == null or not definition.is_valid_definition():
		push_warning("[Settings] Ignored an invalid setting definition.")
		return false
	if _definitions.has(definition.id):
		push_warning("[Settings] Duplicate setting ID ignored: %s" % definition.id)
		return false
	_definitions[definition.id] = definition
	_ensure_category(definition.category_id)
	setting_registered.emit(definition)
	return true

func register_category(category: SettingCategoryRegistry) -> bool:
	if category == null or not category.is_valid_definition():
		push_warning("[Settings] Ignored an invalid settings category.")
		return false
	if _explicit_category_ids.has(category.id):
		push_warning("[Settings] Duplicate category ID ignored: %s" % category.id)
		return false
	_categories[category.id] = category
	_explicit_category_ids[category.id] = true
	return true

func register_enum_option_provider(provider_id: StringName, provider: Callable) -> void:
	if not provider_id.is_empty() and provider.is_valid():
		_enum_option_providers[provider_id] = provider

func get_definition(id: StringName) -> SettingRegistry:
	return _definitions.get(id)

func get_setting(id: StringName, fallback: Variant = null) -> Variant:
	if _values.has(id):
		return _values[id]
	var definition := get_definition(id)
	return definition.get_default_value() if definition != null else fallback

func set_setting(id: StringName, value: Variant, save := true) -> bool:
	var definition := get_definition(id)
	if definition == null:
		push_warning("[Settings] Unknown setting ID: %s" % id)
		return false
	var normalized: Variant = definition.normalize_value(value)
	if definition is EnumSettingRegistry:
		normalized = _normalize_enum_value(definition, normalized)
	_values[id] = normalized
	if definition is KeybindSettingRegistry:
		_apply_keybind(definition, normalized)
	_apply_runtime_setting(id, normalized)
	setting_changed.emit(id, normalized)
	if id == VOICE_CHAT_MODE_ID:
		voice_chat_mode_changed.emit(voice_chat_mode)
	if save and _loaded:
		save_settings()
	return true

func reset_setting(id: StringName) -> bool:
	var definition := get_definition(id)
	return false if definition == null else set_setting(id, definition.get_default_value())

func reset_all_settings() -> void:
	for id in _definitions:
		set_setting(id, _definitions[id].get_default_value(), false)
	save_settings()

func reset_category(category_id: StringName) -> void:
	var category_ids: Array[StringName] = []
	_collect_category_ids(category_id, category_ids)
	for definition in _definitions.values():
		if definition.category_id in category_ids:
			set_setting(definition.id, definition.get_default_value(), false)
	save_settings()

func reset_keybind_category(keybind_category: String) -> void:
	for definition in get_keybind_definitions():
		if definition.keybind_category == keybind_category:
			set_setting(definition.id, definition.get_default_value(), false)
	save_settings()

func reset_all_keybinds() -> void:
	for definition in get_keybind_definitions():
		set_setting(definition.id, definition.get_default_value(), false)
	save_settings()

func _collect_category_ids(category_id: StringName, result: Array[StringName]) -> void:
	if category_id in result:
		return
	result.append(category_id)
	for child_category in get_child_categories(category_id):
		_collect_category_ids(child_category.id, result)

func get_categories() -> Array[SettingCategoryRegistry]:
	var result: Array[SettingCategoryRegistry] = []
	result.assign(_categories.values())
	result.sort_custom(func(a: SettingCategoryRegistry, b: SettingCategoryRegistry) -> bool:
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else a.display_name < b.display_name
	)
	return result

func get_root_categories() -> Array[SettingCategoryRegistry]:
	var result: Array[SettingCategoryRegistry] = []
	for category in get_categories():
		if category.parent_id.is_empty() or not _categories.has(category.parent_id):
			result.append(category)
	return result

func get_child_categories(parent_id: StringName) -> Array[SettingCategoryRegistry]:
	var result: Array[SettingCategoryRegistry] = []
	for category in get_categories():
		if category.parent_id == parent_id:
			result.append(category)
	return result

func get_definitions(category_id: StringName = &"") -> Array[SettingRegistry]:
	var result: Array[SettingRegistry] = []
	for definition in _definitions.values():
		if category_id.is_empty() or definition.category_id == category_id:
			result.append(definition)
	result.sort_custom(func(a: SettingRegistry, b: SettingRegistry) -> bool:
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else a.display_name < b.display_name
	)
	return result

func get_keybind_definitions() -> Array[KeybindSettingRegistry]:
	# Pick up actions added to Project Settings after this autoload initialized.
	_discover_input_map_keybinds()
	var result: Array[KeybindSettingRegistry] = []
	for definition in _definitions.values():
		if definition is KeybindSettingRegistry:
			result.append(definition)
	result.sort_custom(func(a: KeybindSettingRegistry, b: KeybindSettingRegistry) -> bool:
		if a.keybind_category != b.keybind_category:
			return a.keybind_category.naturalnocasecmp_to(b.keybind_category) < 0
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return result

func get_enum_options(id: StringName) -> Array[Dictionary]:
	var definition := get_definition(id) as EnumSettingRegistry
	if definition == null:
		return []
	if definition.options_provider_id.is_empty():
		return definition.get_static_options()
	var provider: Callable = _enum_option_providers.get(definition.options_provider_id, Callable())
	return provider.call() if provider.is_valid() else []

func set_voice_chat_mode(mode: VoiceChatMode) -> void:
	var option_id: StringName = &"push_to_talk"
	if mode == VoiceChatMode.DISABLED:
		option_id = &"disabled"
	elif mode == VoiceChatMode.OPEN_MIC:
		option_id = &"open_mic"
	set_setting(VOICE_CHAT_MODE_ID, option_id)

func set_keybind(action: StringName, physical_keycode: Key) -> void:
	var definition := _find_keybind_definition(action)
	if definition == null:
		push_warning("[Settings] No keybind definition exists for action: %s" % action)
		return
	set_setting(definition.id, PackedInt64Array([int(physical_keycode)]))

func get_keybind(action: StringName) -> InputEventKey:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event
	return null

func save_settings() -> void:
	var config := ConfigFile.new()
	for id in _definitions:
		config.set_value("settings", String(id), get_setting(id))
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("[Settings] Could not save settings: %s" % error_string(error))

func load_settings() -> void:
	var error := _config.load(SETTINGS_PATH)
	for id in _definitions:
		var definition: SettingRegistry = _definitions[id]
		var value: Variant = definition.get_default_value()
		if error == OK:
			value = _config.get_value("settings", String(id), value)
			value = _get_legacy_value(definition, value)
		set_setting(id, value, false)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("[Settings] Could not load settings: %s" % error_string(error))
	_loaded = true

func _scan_registry_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_warning("[Settings] Registry directory could not be opened: %s" % path)
		return
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() not in ["tres", "res"]:
			continue
		var resource := ResourceLoader.load(path.path_join(file_name))
		if resource is SettingCategoryRegistry:
			register_category(resource)
		elif resource is SettingRegistry:
			register_definition(resource)
	for directory_name in directory.get_directories():
		_scan_registry_directory(path.path_join(directory_name))

func _discover_input_map_keybinds() -> void:
	for action in InputMap.get_actions():
		# Godot injects a large set of built-in UI navigation actions into every
		# project. They are engine controls, not player keybinds.
		if String(action).begins_with("ui_"):
			continue
		var keys := _capture_action_keys(action)
		if not _keybind_defaults.has(action):
			_keybind_defaults[action] = keys.duplicate()
		var definition := _find_keybind_definition(action)
		if definition == null:
			definition = KeybindSettingRegistry.new()
			definition.id = StringName("keybind.%s" % action)
			definition.display_name = _humanize_action_name(action)
			definition.description = "Input Map action: %s" % action
			definition.category_id = &"controls"
			definition.action = action
			definition.keybind_category = _infer_keybind_category(action)
			register_definition(definition)
		definition.default_physical_keys = _keybind_defaults[action].duplicate()

func _capture_action_keys(action: StringName) -> PackedInt64Array:
	var keys := PackedInt64Array()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keycode: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if keycode != KEY_NONE and not keys.has(int(keycode)):
				keys.append(int(keycode))
	return keys

func _humanize_action_name(action: StringName) -> String:
	return String(action).replace("_", " ").capitalize()

func _infer_keybind_category(action: StringName) -> String:
	var action_text := String(action)
	if action_text.begins_with("move_") or action in [
		&"jump",
		&"crouch",
		&"sprint",
		&"stroll",
		&"roll_left",
		&"roll_right",
	]:
		return "Movement"
	if action_text.contains("voice") or action_text.contains("radio") or action_text.contains("chat"):
		return "Communication"
	return "General"

func _ensure_category(id: StringName) -> void:
	if id.is_empty() or _categories.has(id):
		return
	var category := SettingCategoryRegistry.new()
	category.id = id
	category.display_name = String(id).replace("_", " ").capitalize()
	_categories[id] = category

func _normalize_enum_value(definition: EnumSettingRegistry, value: Variant) -> StringName:
	var option_id := StringName(value)
	var options := get_enum_options(definition.id)
	if options.is_empty():
		return definition.default_option_id
	for option in options:
		if StringName(option.get("id", &"")) == option_id:
			return option_id
	return definition.default_option_id

func _apply_keybind(definition: KeybindSettingRegistry, value: Variant) -> void:
	if not InputMap.has_action(definition.action):
		InputMap.add_action(definition.action)
	for event in InputMap.action_get_events(definition.action):
		if event is InputEventKey:
			InputMap.action_erase_event(definition.action, event)
	for keycode in definition.normalize_value(value):
		var event := InputEventKey.new()
		event.physical_keycode = int(keycode) as Key
		InputMap.action_add_event(definition.action, event)
		keybind_changed.emit(definition.action, event)

func _apply_runtime_setting(id: StringName, value: Variant) -> void:
	match id:
		DISPLAY_MODE_ID:
			_apply_display_mode(StringName(value))
		VSYNC_ID:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED
			)
		FPS_LIMIT_ID:
			Engine.max_fps = maxi(int(String(value)), 0)
		MASTER_VOLUME_ID:
			var bus_index := AudioServer.get_bus_index(&"Master")
			if bus_index >= 0:
				var linear_volume := clampf(float(value) / 100.0, 0.0, 1.0)
				AudioServer.set_bus_mute(bus_index, is_zero_approx(linear_volume))
				AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear_volume))

func _apply_display_mode(mode: StringName) -> void:
	match mode:
		&"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		&"exclusive_fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _find_keybind_definition(action: StringName) -> KeybindSettingRegistry:
	for definition in _definitions.values():
		if definition is KeybindSettingRegistry and definition.action == action:
			return definition
	return null

func _get_legacy_value(definition: SettingRegistry, fallback: Variant) -> Variant:
	if definition.id == VOICE_CHAT_MODE_ID and _config.has_section_key("voice", "mode"):
		match int(_config.get_value("voice", "mode")):
			VoiceChatMode.DISABLED: return &"disabled"
			VoiceChatMode.OPEN_MIC: return &"open_mic"
			_: return &"push_to_talk"
	if definition is KeybindSettingRegistry and _config.has_section_key("keybinds", String(definition.action)):
		return PackedInt64Array([int(_config.get_value("keybinds", String(definition.action)))])
	return fallback

func _get_audio_input_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for device in AudioServer.get_input_device_list():
		options.append({"id": StringName(device), "name": device})
	return options
