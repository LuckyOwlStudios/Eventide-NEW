class_name SettingsMenu
extends Control

signal closed

const SETTING_ENTRY_SCENE := preload("res://Scenes/UI/Settings/Entry/SettingEntry.tscn")

@onready var title_label: Label = %Title
@onready var category_count: Label = %CategoryCount
@onready var previous_category_button: Button = %PreviousCategoryButton
@onready var next_category_button: Button = %NextCategoryButton
@onready var settings_view: ScrollContainer = %SettingsView
@onready var settings_list: VBoxContainer = %SettingsList
@onready var keybind_view: ScrollContainer = %KeybindView
@onready var keybind_list: VBoxContainer = %KeybindList
@onready var description_label: Label = %DescriptionLabel
@onready var reset_actions: HBoxContainer = %ResetActions
@onready var reset_category_button: Button = %ResetCategoryButton
@onready var reset_all_button: Button = %ResetAllButton

var _categories: Array[SettingCategoryRegistry] = []
var _category_index := 0
var _keybind_categories: Array[String] = []
var _keybind_category_index := 0
var _showing_keybinds := false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	settings_view.get_v_scroll_bar().theme_type_variation = &"SettingsVScrollBar"
	keybind_view.get_v_scroll_bar().theme_type_variation = &"SettingsVScrollBar"
	reset_category_button.pressed.connect(_reset_current_category)
	reset_all_button.pressed.connect(_reset_all)
	previous_category_button.pressed.connect(_show_previous_category)
	next_category_button.pressed.connect(_show_next_category)
	hide()

func open() -> void:
	_load_categories()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_settings_view()

func close() -> void:
	get_tree().call_group(&"keybind_setting_entries", &"cancel_keybind_capture")
	_showing_keybinds = false
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _load_categories() -> void:
	_categories.clear()
	for category in Settings.get_root_categories():
		_categories.append(category)
	if _categories.is_empty():
		_category_index = 0
	else:
		_category_index = clampi(_category_index, 0, _categories.size() - 1)

func _show_category(index: int) -> void:
	if _categories.is_empty():
		title_label.text = "OPTIONS"
		category_count.text = "0 / 0"
		reset_category_button.disabled = true
		reset_all_button.disabled = true
		_clear_list(settings_list)
		_add_empty_label(settings_list, "No setting categories are registered.")
		return
	_category_index = wrapi(index, 0, _categories.size())
	var category := _categories[_category_index]
	reset_category_button.disabled = false
	reset_all_button.disabled = false
	title_label.text = category.display_name.to_upper()
	category_count.text = "%d / %d" % [_category_index + 1, _categories.size()]
	description_label.text = category.description
	_clear_list(settings_list)
	_add_category_contents(settings_list, category, false)
	if settings_list.get_child_count() == 0:
		_add_empty_label(settings_list, "No settings are registered in this category.")
	settings_view.scroll_vertical = 0

func _add_category_contents(
		list: VBoxContainer,
		category: SettingCategoryRegistry,
		show_heading: bool
) -> void:
	if show_heading:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 8.0
		list.add_child(spacer)
		var heading := Label.new()
		heading.text = category.display_name.to_upper()
		heading.theme_type_variation = &"SettingsSectionLabel"
		list.add_child(heading)

	if category.id == &"controls":
		var keybind_button := Button.new()
		keybind_button.name = "ConfigureKeybindsButton"
		keybind_button.custom_minimum_size = Vector2(350.0, 34.0)
		keybind_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		keybind_button.theme_type_variation = &"SettingsButton"
		keybind_button.text = "KEY BINDINGS  >"
		keybind_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var keybind_description := "View, change, or reset keyboard controls."
		keybind_button.pressed.connect(_open_keybind_menu)
		keybind_button.focus_entered.connect(_set_description.bind(keybind_description))
		keybind_button.mouse_entered.connect(_set_description.bind(keybind_description))
		list.add_child(keybind_button)

	for definition in Settings.get_definitions(category.id):
		if definition is KeybindSettingRegistry:
			continue
		var entry := SETTING_ENTRY_SCENE.instantiate() as SettingEntry
		list.add_child(entry)
		entry.description_requested.connect(_set_description)
		entry.setup(definition)

	for child_category in Settings.get_child_categories(category.id):
		_add_category_contents(list, child_category, true)

func _show_previous_category() -> void:
	if _showing_keybinds:
		_show_keybind_category(_keybind_category_index - 1)
	else:
		_show_category(_category_index - 1)

func _show_next_category() -> void:
	if _showing_keybinds:
		_show_keybind_category(_keybind_category_index + 1)
	else:
		_show_category(_category_index + 1)

func _open_keybind_menu() -> void:
	_showing_keybinds = true
	_load_keybind_categories()
	settings_view.hide()
	keybind_view.show()
	reset_actions.show()
	category_count.show()
	previous_category_button.show()
	next_category_button.show()
	_show_keybind_category(_keybind_category_index)

func _show_settings_view() -> void:
	get_tree().call_group(&"keybind_setting_entries", &"cancel_keybind_capture")
	_showing_keybinds = false
	category_count.show()
	previous_category_button.show()
	next_category_button.show()
	keybind_view.hide()
	settings_view.show()
	reset_actions.show()
	if not _categories.is_empty():
		_show_category(_category_index)
	else:
		_show_category(0)

func _on_back_pressed() -> void:
	if _showing_keybinds:
		_show_settings_view()
	else:
		close()

func _load_keybind_categories() -> void:
	var previous_category := ""
	if _keybind_category_index >= 0 and _keybind_category_index < _keybind_categories.size():
		previous_category = _keybind_categories[_keybind_category_index]
	_keybind_categories.clear()
	for definition in Settings.get_keybind_definitions():
		if not _keybind_categories.has(definition.keybind_category):
			_keybind_categories.append(definition.keybind_category)
	_keybind_categories.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0
	)
	var previous_index := _keybind_categories.find(previous_category)
	if previous_index >= 0:
		_keybind_category_index = previous_index
	elif _keybind_categories.is_empty():
		_keybind_category_index = 0
	else:
		_keybind_category_index = clampi(_keybind_category_index, 0, _keybind_categories.size() - 1)

func _show_keybind_category(index: int) -> void:
	if _keybind_categories.is_empty():
		title_label.text = "KEY BINDINGS"
		category_count.text = "0 / 0"
		_clear_list(keybind_list)
		_add_empty_label(keybind_list, "No project actions were found in the Input Map.")
		reset_category_button.disabled = true
		reset_all_button.disabled = true
		return
	_keybind_category_index = wrapi(index, 0, _keybind_categories.size())
	var keybind_category := _keybind_categories[_keybind_category_index]
	title_label.text = "KEY BINDINGS / %s" % keybind_category.to_upper()
	category_count.text = "%d / %d" % [_keybind_category_index + 1, _keybind_categories.size()]
	description_label.text = "Select a binding, then press a new key. Escape returns to Controls."
	reset_category_button.disabled = false
	reset_all_button.disabled = false
	_rebuild_keybind_list(keybind_category)

func _rebuild_keybind_list(keybind_category: String) -> void:
	_clear_list(keybind_list)
	for definition in Settings.get_keybind_definitions():
		if definition.keybind_category != keybind_category:
			continue
		var entry := SETTING_ENTRY_SCENE.instantiate() as SettingEntry
		keybind_list.add_child(entry)
		entry.description_requested.connect(_set_description)
		entry.setup(definition)

	if keybind_list.get_child_count() == 0:
		_add_empty_label(keybind_list, "No key bindings are registered in this category.")
	keybind_view.scroll_vertical = 0

func _reset_current_category() -> void:
	if _showing_keybinds:
		if _keybind_categories.is_empty():
			return
		var keybind_category := _keybind_categories[_keybind_category_index]
		Settings.reset_keybind_category(keybind_category)
		_rebuild_keybind_list(keybind_category)
		description_label.text = "%s key bindings restored to their defaults." % keybind_category
		return
	if _categories.is_empty():
		return
	var category := _categories[_category_index]
	Settings.reset_category(category.id)
	_show_category(_category_index)
	description_label.text = "%s settings restored to their defaults." % category.display_name

func _reset_all() -> void:
	if _showing_keybinds:
		Settings.reset_all_keybinds()
		if not _keybind_categories.is_empty():
			_rebuild_keybind_list(_keybind_categories[_keybind_category_index])
		description_label.text = "All key bindings restored to their defaults."
		return
	Settings.reset_all_settings()
	_show_category(_category_index)
	description_label.text = "All settings restored to their defaults."

func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _add_empty_label(list: VBoxContainer, text: String) -> void:
	var empty_label := Label.new()
	empty_label.theme_type_variation = &"SettingsLabel"
	empty_label.text = text
	list.add_child(empty_label)

func _set_description(text: String) -> void:
	description_label.text = text if not text.is_empty() else "No description available."
