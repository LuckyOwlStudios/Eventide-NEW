extends Node

## Starts Steamworks before the first game scene and owns its lifetime.
## Lobby and gameplay systems can wait for initialized before using Steam.

## Emitted when the steam network is initialized
signal initialized(steam_id: int, persona_name: String)
## Emitted when the steam network initialization fails
signal initialization_failed(status: int, message: String)
signal lobby_changed(lobby_id: int)

var is_active := false
var steam_id: int = 0
var persona_name := ""
var lobby_id: int = 0
var last_error := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

	if not Engine.has_singleton("Steam"):
		_fail(-1, "GodotSteam failed to load, so Steam networking is unavailable.")
		return

	var app_id := int(ProjectSettings.get_setting(
		"steam/initialization/app_data/app_id",
		480
	))
	var response: Dictionary = Steam.steamInitEx(app_id, false)
	var status := int(response.get("status", -1))

	if status != 0:
		_fail(status, str(response.get("verbal", "Steamworks initialization failed.")))
		return

	is_active = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	Steam.initRelayNetworkAccess()
	set_process(true)
	print("Steam networking ready: %s (%s), App ID %s" % [persona_name, steam_id, app_id])
	initialized.emit(steam_id, persona_name)

func _process(_delta: float) -> void:
	if is_active:
		Steam.run_callbacks()

func _exit_tree() -> void:
	if is_active:
		Steam.steamShutdown()
		is_active = false


func has_lobby() -> bool:
	return is_active and lobby_id > 0


func set_lobby(lobby: int) -> void:
	var normalized := maxi(lobby, 0)
	if lobby_id == normalized:
		return
	lobby_id = normalized
	lobby_changed.emit(lobby_id)


func clear_lobby() -> void:
	set_lobby(0)

func _fail(status: int, message: String) -> void:
	last_error = message
	push_warning("Steam networking did not start: %s" % message)
	initialization_failed.emit(status, message)
