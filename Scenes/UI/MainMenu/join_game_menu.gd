class_name JoinGameMenu
extends Control
## Lists the games other players are hosting and joins the one that is chosen.

## Joined a lobby. The main menu takes over from here.
signal joined
signal closed

const ROW_SCENE := preload("res://Scenes/UI/MainMenu/ServerRow.tscn")

@onready var server_view: ScrollContainer = %ServerView
@onready var server_list: VBoxContainer = %ServerList
@onready var state_label: Label = %StateLabel
@onready var refresh_button: Button = %RefreshButton
@onready var description_label: Label = %DescriptionLabel
@onready var back_hint: Button = %BackHint

var _searching := false
var _joining := false


func _ready() -> void:
	server_view.get_v_scroll_bar().theme_type_variation = &"SettingsVScrollBar"
	back_hint.pressed.connect(close)
	refresh_button.pressed.connect(refresh)
	refresh_button.focus_entered.connect(set_description.bind("Search for games again."))
	refresh_button.mouse_entered.connect(set_description.bind("Search for games again."))
	SteamLobby.lobby_list_received.connect(_on_lobby_list_received)
	SteamLobby.join_failed.connect(_on_join_failed)
	hide()


func open() -> void:
	_joining = false
	show()
	refresh()
	(back_hint if refresh_button.disabled else refresh_button).call_deferred("grab_focus")


func close() -> void:
	hide()
	closed.emit()


func refresh() -> void:
	_clear_rows()
	if not SteamLobby.is_available():
		_set_state("Steam is offline, so there are no games to join.")
		refresh_button.disabled = true
		set_description("Start Steam and restart the game to play with others.")
		return
	_searching = true
	_set_state("Searching for games...")
	set_description("Looking for games hosted by other players.")
	SteamLobby.request_lobby_list()


func set_description(text: String) -> void:
	description_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_lobby_list_received(lobbies: Array[Dictionary]) -> void:
	if not _searching:
		return
	_searching = false
	refresh_button.disabled = not SteamLobby.is_available()
	_clear_rows()
	for info in lobbies:
		var row := ROW_SCENE.instantiate() as ServerRow
		server_list.add_child(row)
		row.setup(info)
		row.description_requested.connect(set_description)
		row.pressed.connect(_join.bind(info["lobby_id"], row.host_label.text))
	if lobbies.is_empty():
		_set_state("No games found.")
		set_description("Nobody is hosting right now. Refresh to look again, or host your own game.")
	else:
		_set_state("")
		set_description("Choose a game to join.")
		if visible:
			(server_list.get_child(0) as Button).call_deferred("grab_focus")


func _join(lobby_id: int, host_text: String) -> void:
	if _joining:
		return
	_joining = true
	set_description("Joining %s..." % host_text)
	var success := await SteamLobby.join_lobby(lobby_id)
	_joining = false
	if success and visible:
		joined.emit()


func _on_join_failed(message: String) -> void:
	if visible:
		set_description(message)


func _set_state(text: String) -> void:
	state_label.text = text
	state_label.visible = not text.is_empty()


func _clear_rows() -> void:
	for row in server_list.get_children():
		server_list.remove_child(row)
		row.queue_free()
