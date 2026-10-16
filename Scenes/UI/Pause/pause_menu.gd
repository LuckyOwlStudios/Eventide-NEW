class_name PauseMenu
extends Control

signal resume_requested
signal main_menu_requested
signal quit_requested

@onready var resume_button: Button = %ResumeButton
@onready var options_button: Button = %OptionsButton
@onready var main_menu_button: ConfirmationButton = %MainMenuButton
@onready var quit_button: ConfirmationButton = %QuitButton
@onready var menu_panel: Control = %MenuPanel
@onready var description_label: Label = %DescriptionLabel
@onready var settings_menu: SettingsMenu = %SettingsMenu

var _button_descriptions: Dictionary[Button, String] = {}

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	close()
	resume_button.pressed.connect(resume_requested.emit)
	options_button.pressed.connect(_open_settings)
	main_menu_button.confirmed.connect(main_menu_requested.emit)
	quit_button.confirmed.connect(quit_requested.emit)
	settings_menu.closed.connect(_on_settings_closed)
	_button_descriptions = {
		resume_button: "Return to the game",
		options_button: "Adjust game, video, audio, and control settings",
		main_menu_button: "Leave this game and return to the main menu",
		quit_button: "Exit " + ProjectSettings.get_setting("application/config/name"),
	}
	for button in _button_descriptions:
		button.focus_entered.connect(_show_button_description.bind(button))
		button.mouse_entered.connect(_show_button_description.bind(button))


func open() -> void:
	show()
	menu_panel.show()
	settings_menu.hide()
	_show_button_description(resume_button)
	resume_button.call_deferred("grab_focus")


func close() -> void:
	hide()
	menu_panel.show()
	settings_menu.hide()


func is_settings_open() -> bool:
	return settings_menu.visible

func _open_settings() -> void:
	menu_panel.hide()
	settings_menu.open()

func _on_settings_closed() -> void:
	if visible:
		menu_panel.show()
		options_button.call_deferred("grab_focus")


func _show_button_description(button: Button) -> void:
	description_label.text = _button_descriptions.get(button, "")
