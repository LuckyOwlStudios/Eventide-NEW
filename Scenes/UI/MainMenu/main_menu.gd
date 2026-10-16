class_name MainMenu
extends Control
## The game's main menu: Host Game, Join Game, Options and Exit Game over a space backdrop,
## with the Steam lobby shown in the top left.

const WORLD_SCENE := "res://Game/InGameSession.tscn"
const FADE_IN_TIME := 0.9
const FADE_OUT_TIME := 0.6

@onready var main_panel: Control = %MainPanel
@onready var dimmer: DimmerOverlay = %Dimmer
@onready var fade_rect: ColorRect = %FadeRect
@onready var loading_label: Label = %LoadingLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var options_button: Button = %OptionsButton
@onready var exit_button: Button = %ExitButton
@onready var description_label: Label = %DescriptionLabel
@onready var host_menu: HostGameMenu = %HostGameMenu
@onready var join_menu: JoinGameMenu = %JoinGameMenu
@onready var settings_menu: SettingsMenu = %SettingsMenu

var _buttons: Array[Button] = []
var _button_descriptions: Dictionary[Button, String] = {}
var _return_focus: Button
var _launching := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_buttons = [host_button, join_button, options_button, exit_button]
	_button_descriptions = {
		host_button: "Start a new world or continue a saved one",
		join_button: "Find a game hosted by another player",
		options_button: "Adjust game, video, audio, and control settings",
		exit_button: "Exit " + ProjectSettings.get_setting("application/config/name"),
	}
	for button in _buttons:
		button.focus_entered.connect(_show_button_description.bind(button))
		button.mouse_entered.connect(_show_button_description.bind(button))

	host_button.pressed.connect(_open_page.bind(host_menu, host_button))
	join_button.pressed.connect(_open_page.bind(join_menu, join_button))
	options_button.pressed.connect(_open_page.bind(settings_menu, options_button))
	exit_button.pressed.connect(get_tree().quit)

	host_menu.closed.connect(_on_page_closed)
	join_menu.closed.connect(_on_page_closed)
	settings_menu.closed.connect(_on_page_closed)
	host_menu.world_chosen.connect(_on_world_chosen)
	join_menu.joined.connect(join_menu.close)

	SteamLobby.members_changed.connect(_refresh_buttons)
	SteamLobby.join_failed.connect(_show_notice)
	SteamLobby.world_connected.connect(_launch_world)

	dimmer.set_dim_immediate(0.0)
	loading_label.hide()
	_refresh_buttons()
	_show_button_description(host_button if not host_button.disabled else join_button)
	_fade_in()


## Fades up from black when the menu appears. Clicks wait until it has finished.
func _fade_in() -> void:
	fade_rect.show()
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	fade_rect.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 0.0, FADE_IN_TIME)
	await tween.finished
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.hide()
	_focus_first_button()


func _focus_first_button() -> void:
	for button in _buttons:
		if not button.disabled:
			button.grab_focus()
			return


## Hosting is for the owner of the lobby. A guest in someone else's lobby has to leave first.
func _refresh_buttons() -> void:
	var guest := SteamLobby.has_lobby() and not SteamLobby.is_lobby_owner()
	host_button.disabled = guest
	_button_descriptions[host_button] = "Leave the lobby you joined to host your own game" if guest \
			else "Start a new world or continue a saved one"
	# Focus wraps from the last button to the first, skipping any that are disabled.
	var enabled: Array[Button] = _buttons.filter(func(button: Button) -> bool: return not button.disabled)
	for index in enabled.size():
		var previous := enabled[(index - 1 + enabled.size()) % enabled.size()]
		var next := enabled[(index + 1) % enabled.size()]
		enabled[index].focus_neighbor_top = enabled[index].get_path_to(previous)
		enabled[index].focus_neighbor_bottom = enabled[index].get_path_to(next)
	var focused := get_viewport().gui_get_focus_owner()
	if guest and focused == host_button:
		call_deferred("_focus_first_button")
	if focused is Button and focused in _buttons:
		_show_button_description(focused as Button)


func _open_page(page: Control, opener: Button) -> void:
	if _launching:
		return
	_return_focus = opener
	main_panel.hide()
	dimmer.fade_in()
	page.open()


func _on_page_closed() -> void:
	if _launching:
		return
	main_panel.show()
	dimmer.fade_out()
	if is_instance_valid(_return_focus) and not _return_focus.disabled:
		_return_focus.call_deferred("grab_focus")
	else:
		call_deferred("_focus_first_button")


func _on_world_chosen(slot: int) -> void:
	if _launching:
		return
	var info := WorldSaves.read_slot(slot)
	if info["corrupt"]:
		return
	if not info["exists"]:
		info = WorldSaves.create_world(slot)
		if info.is_empty():
			host_menu.set_description("Could not create a world in slot %d. Check that the game can write to its save folder." % slot)
			return
	var error := SteamLobby.host_world(info["name"])
	if error != OK:
		host_menu.set_description("Could not open your game to the lobby (error %d)." % error)
		return
	WorldSaves.mark_played(slot)
	WorldSaves.active_slot = slot
	_launch_world()


func _launch_world() -> void:
	if _launching:
		return
	_launching = true
	fade_rect.show()
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, FADE_OUT_TIME)
	await tween.finished
	loading_label.show()
	# Loading the world blocks the game for a moment; let the label draw first.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(WORLD_SCENE)


func _show_button_description(button: Button) -> void:
	description_label.text = _button_descriptions.get(button, "")


## Shows a message from Steam, such as a game that could not be joined, on the main page.
func _show_notice(message: String) -> void:
	description_label.text = message
