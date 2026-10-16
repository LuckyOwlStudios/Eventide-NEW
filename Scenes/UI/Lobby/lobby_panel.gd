class_name LobbyPanel
extends PanelContainer
## Shows everyone in the player's Steam lobby. Used by the main menu and the host menu,
## and keeps itself up to date from [SteamLobby].

const CARD_SCENE := preload("res://Scenes/UI/Lobby/LobbyPlayerCard.tscn")

@onready var count_label: Label = %CountLabel
@onready var cards: VBoxContainer = %Cards
@onready var status_label: Label = %StatusLabel
@onready var invite_button: Button = %InviteButton
@onready var leave_button: Button = %LeaveButton

var _cards_by_id: Dictionary[int, LobbyPlayerCard] = {}


func _ready() -> void:
	SteamLobby.members_changed.connect(_rebuild)
	SteamLobby.lobby_data_changed.connect(_refresh_status)
	SteamLobby.profile_changed.connect(_on_profile_changed)
	leave_button.pressed.connect(SteamLobby.leave_lobby)
	_rebuild()


func _rebuild() -> void:
	for card in cards.get_children():
		cards.remove_child(card)
		card.queue_free()
	_cards_by_id.clear()

	var members := SteamLobby.get_members()
	for member in members:
		var card := CARD_SCENE.instantiate() as LobbyPlayerCard
		cards.add_child(card)
		card.setup(member)
		_cards_by_id[member["steam_id"]] = card
	count_label.text = "%d / %d" % [members.size(), SteamLobby.get_max_members()] if not members.is_empty() else ""
	count_label.visible = not members.is_empty()
	invite_button.visible = SteamLobby.has_lobby()
	leave_button.visible = SteamLobby.has_lobby() and not SteamLobby.is_lobby_owner()
	_refresh_status()


func _refresh_status() -> void:
	var text := ""
	if not SteamLobby.is_available():
		text = "Steam is offline. Multiplayer is unavailable."
	elif not SteamLobby.has_lobby():
		text = "No lobby. Friends cannot join you right now."
	elif not SteamLobby.is_lobby_owner():
		text = "Connecting to the host's game..." if SteamLobby.is_game_running() \
				else "Waiting for the host to start a world."
	elif _cards_by_id.size() <= 1:
		text = "Invite friends to play together."
	status_label.text = text
	status_label.visible = not text.is_empty()
	leave_button.visible = SteamLobby.has_lobby() and not SteamLobby.is_lobby_owner()


func _on_profile_changed(steam_id: int) -> void:
	if _cards_by_id.has(steam_id):
		_cards_by_id[steam_id].refresh()
