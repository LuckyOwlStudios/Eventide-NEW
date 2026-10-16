class_name ServerRow
extends Button
## One joinable game in the join menu.

signal description_requested(text: String)

@onready var host_label: Label = %HostLabel
@onready var world_label: Label = %WorldLabel
@onready var players_label: Label = %PlayersLabel
@onready var tag_label: Label = %TagLabel

var lobby_id := 0
var _description := ""


func _ready() -> void:
	mouse_entered.connect(grab_focus)
	mouse_entered.connect(_request_description)
	focus_entered.connect(_request_description)


## [param info] is an entry of [signal SteamLobby.lobby_list_received].
func setup(info: Dictionary) -> void:
	lobby_id = info["lobby_id"]
	var host_name: String = info["host_name"]
	var world: String = info["world"]
	host_label.text = "%s's game" % host_name if not host_name.is_empty() else "Unnamed game"
	world_label.text = world if not world.is_empty() else "World not named"
	players_label.text = "%d / %d" % [info["members"], info["max_members"]]
	tag_label.text = "JOIN"
	_description = "Join %s." % host_label.text


func _request_description() -> void:
	description_requested.emit(_description)
