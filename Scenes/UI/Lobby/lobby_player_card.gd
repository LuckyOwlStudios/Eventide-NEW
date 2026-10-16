class_name LobbyPlayerCard
extends Button
## One player in the lobby panel. Clicking it opens that player's Steam page.

@onready var avatar_rect: TextureRect = %Avatar
@onready var name_label: Label = %NameLabel
@onready var role_label: Label = %RoleLabel

var steam_id := 0
var _is_owner := false
var _is_local := false


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(grab_focus)
	_refresh_labels()


## [param member] is an entry of [method SteamLobby.get_members].
func setup(member: Dictionary) -> void:
	steam_id = member["steam_id"]
	_is_owner = member["is_owner"]
	_is_local = member["is_local"]
	if is_node_ready():
		_refresh_labels()


## Picks up a name or picture Steam has sent since the card was built.
func refresh() -> void:
	_refresh_labels()


func _refresh_labels() -> void:
	var player_name := SteamProfile.display_name(steam_id)
	name_label.text = player_name if not player_name.is_empty() else "..."
	avatar_rect.texture = SteamProfile.avatar(steam_id)
	var roles: PackedStringArray = []
	if _is_owner:
		roles.append("HOST")
	if _is_local:
		roles.append("YOU")
	role_label.text = " / ".join(roles)
	role_label.visible = not roles.is_empty()
	tooltip_text = "View %s on Steam" % name_label.text


func _on_pressed() -> void:
	Steam.activateGameOverlayToUser("steamid", steam_id)
	#SteamProfile.open_profile(steam_id)
