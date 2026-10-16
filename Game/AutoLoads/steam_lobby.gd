extends Node
## The player's Steam lobby. On the menus it is a party: friends gather in it, and the
## lobby's owner hosts a world. Starting a world turns the lobby into the game session
## (the lobby becomes public, and everyone in it connects to the owner). Everything here
## is a no-op when Steam did not start, so the menus still work offline.
##
## [member SteamNetwork.lobby_id] stays the single place that says which lobby is current.

## The members, the owner, or which lobby we are in changed.
signal members_changed
## The lobby's own data (the world being played, whether it has started) changed.
signal lobby_data_changed
## A member's Steam name or picture arrived or changed.
signal profile_changed(steam_id: int)
## Answer to [method request_lobby_list]. Each entry has [code]lobby_id[/code],
## [code]host_name[/code], [code]world[/code], [code]members[/code] and [code]max_members[/code].
signal lobby_list_received(lobbies: Array[Dictionary])
## Joining a lobby, or connecting to its game, did not work. [param message] is for the player.
signal join_failed(message: String)
## This client connected to the host's running game: load the world now.
signal world_connected

const GAME_KEY := "game"
const GAME_TAG := "eventide"
const HOST_KEY := "host"
const WORLD_KEY := "world"
const STATE_KEY := "state"
const STATE_MENU := "menu"
const STATE_PLAYING := "playing"

## Players that fit in a lobby, the host included.
const MAX_MEMBERS := 4
const LIST_LIMIT := 50
const CREATE_TIMEOUT := 10.0
const JOIN_TIMEOUT := 10.0
const CONNECT_TIMEOUT := 15.0

var _creating := false
var _join_target := 0
var _connecting := false
## Bumped for every attempt of each kind, so a timeout belonging to an earlier attempt cannot
## end a later one.
var _create_serial := 0
var _join_serial := 0
var _connect_serial := 0

signal _create_finished(success: bool)
signal _join_finished(error: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not SteamNetwork.is_active:
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.join_requested.connect(_on_join_requested)
	Steam.persona_state_change.connect(_on_persona_state_change)
	NetworkSession.connected_to_server.connect(_on_connected_to_server)
	NetworkSession.connection_failed.connect(_on_connection_failed)


func _exit_tree() -> void:
	# The Steam peer talks to Steam while it closes, so it must go before SteamNetwork shuts
	# Steam down. Autoloads leave the tree last to first, which puts this ahead of it.
	if not SteamNetwork.is_active:
		return
	_close_game_peer()
	if has_lobby():
		Steam.leaveLobby(SteamNetwork.lobby_id)


func is_available() -> bool:
	return SteamNetwork.is_active


func has_lobby() -> bool:
	return SteamNetwork.has_lobby()


func is_lobby_owner() -> bool:
	return has_lobby() and Steam.getLobbyOwner(SteamNetwork.lobby_id) == SteamNetwork.steam_id


## True once the lobby's owner has started a world.
func is_game_running() -> bool:
	return has_lobby() and Steam.getLobbyData(SteamNetwork.lobby_id, STATE_KEY) == STATE_PLAYING


func get_max_members() -> int:
	if not has_lobby():
		return MAX_MEMBERS
	return maxi(Steam.getLobbyMemberLimit(SteamNetwork.lobby_id), 1)


## Everyone in the lobby, the owner first. Each entry has [code]steam_id[/code],
## [code]name[/code] (empty until Steam sends it), [code]is_owner[/code] and [code]is_local[/code].
func get_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	if not has_lobby():
		return members
	var lobby := SteamNetwork.lobby_id
	var owner_id: int = Steam.getLobbyOwner(lobby)
	for index in Steam.getNumLobbyMembers(lobby):
		var member_id: int = Steam.getLobbyMemberByIndex(lobby, index)
		members.append({
			"steam_id": member_id,
			"name": SteamProfile.display_name(member_id),
			"is_owner": member_id == owner_id,
			"is_local": member_id == SteamNetwork.steam_id,
		})
	# The owner leads; everyone else keeps the order Steam gave.
	for index in members.size():
		if members[index]["is_owner"]:
			members.insert(0, members.pop_at(index))
			break
	return members


## Makes sure we are in a lobby of our own, creating a friends-only one if not.
## Returns whether we are in a lobby afterwards. Takes a few seconds at worst.
func create_lobby() -> bool:
	if not SteamNetwork.is_active:
		return false
	if has_lobby():
		return true
	if _creating:
		return await _create_finished
	_creating = true
	_create_serial += 1
	var serial := _create_serial
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_MEMBERS)
	get_tree().create_timer(CREATE_TIMEOUT).timeout.connect(func() -> void:
		if serial == _create_serial:
			_finish_create(false)
	)
	return await _create_finished


## Leaves the current lobby for a new one of our own.
func leave_lobby() -> void:
	if not has_lobby():
		return
	_close_game_peer()
	Steam.leaveLobby(SteamNetwork.lobby_id)
	SteamNetwork.clear_lobby()
	members_changed.emit()
	lobby_data_changed.emit()
	await create_lobby()


## Joins another player's lobby and leaves ours once that worked. Failures are reported
## through [signal join_failed]. Returns whether we are now in [param target].
func join_lobby(target: int) -> bool:
	if not SteamNetwork.is_active:
		join_failed.emit("Steam is not available.")
		return false
	if target == SteamNetwork.lobby_id:
		return true
	if _join_target != 0:
		return false
	_join_target = target
	_join_serial += 1
	var serial := _join_serial
	Steam.joinLobby(target)
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if serial == _join_serial:
			_finish_join("Timed out while joining the lobby.")
	)
	var error: String = await _join_finished
	if not error.is_empty():
		join_failed.emit(error)
		return false
	return true


## Asks Steam for the games that can be joined. Answered by [signal lobby_list_received].
func request_lobby_list() -> void:
	if not SteamNetwork.is_active:
		lobby_list_received.emit([] as Array[Dictionary])
		return
	Steam.addRequestLobbyListStringFilter(GAME_KEY, GAME_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(LIST_LIMIT)
	Steam.requestLobbyList()


## Marks the lobby as running [param world_name] and opens it to everyone, then starts
## listening for the players who join. The caller loads the world afterwards.
## Without a lobby (offline) this does nothing and returns [constant OK], so a single-player
## world starts the same way.
func host_world(world_name: String) -> Error:
	if not has_lobby():
		return OK
	if not is_lobby_owner():
		return ERR_UNAUTHORIZED
	if _has_game_peer():
		return ERR_ALREADY_IN_USE
	var lobby := SteamNetwork.lobby_id
	var peer := SteamMultiplayerPeer.new()
	var error := peer.host_with_lobby(lobby)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	Steam.setLobbyData(lobby, WORLD_KEY, world_name)
	Steam.setLobbyData(lobby, STATE_KEY, STATE_PLAYING)
	Steam.setLobbyType(lobby, Steam.LOBBY_TYPE_PUBLIC)
	Steam.setLobbyJoinable(lobby, true)
	return OK


func _enter_lobby(lobby: int, as_owner: bool) -> void:
	SteamNetwork.set_lobby(lobby)
	if as_owner:
		Steam.setLobbyData(lobby, GAME_KEY, GAME_TAG)
		Steam.setLobbyData(lobby, HOST_KEY, SteamNetwork.persona_name)
		Steam.setLobbyData(lobby, STATE_KEY, STATE_MENU)
		Steam.setLobbyJoinable(lobby, true)
	members_changed.emit()
	lobby_data_changed.emit()


func _finish_create(success: bool) -> void:
	if not _creating:
		return
	_creating = false
	_create_finished.emit(success)


func _finish_join(error: String) -> void:
	if _join_target == 0:
		return
	_join_target = 0
	_join_finished.emit(error)


func _on_lobby_created(result: int, lobby: int) -> void:
	if result != Steam.RESULT_OK:
		push_warning("[SteamLobby] Could not create a lobby (result %d)." % result)
		_finish_create(false)
		return
	if has_lobby():
		# Arrived after a timeout, and we have found a lobby since.
		Steam.leaveLobby(lobby)
		_finish_create(true)
		return
	_enter_lobby(lobby, true)
	_finish_create(true)


func _on_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if lobby != _join_target:
		return
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_finish_join(_describe_enter_response(response))
		return
	var previous := SteamNetwork.lobby_id
	_enter_lobby(lobby, false)
	if previous > 0:
		Steam.leaveLobby(previous)
	_finish_join("")
	_connect_to_running_game()


func _on_lobby_chat_update(lobby: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if lobby == SteamNetwork.lobby_id:
		members_changed.emit()


func _on_lobby_data_update(_success: int, lobby: int, member: int) -> void:
	if lobby != SteamNetwork.lobby_id:
		return
	if member == lobby:
		lobby_data_changed.emit()
		_connect_to_running_game()
	members_changed.emit()


func _on_lobby_match_list(lobbies: Array) -> void:
	var found: Array[Dictionary] = []
	for lobby: int in lobbies:
		if lobby == SteamNetwork.lobby_id:
			continue
		found.append({
			"lobby_id": lobby,
			"host_name": Steam.getLobbyData(lobby, HOST_KEY),
			"world": Steam.getLobbyData(lobby, WORLD_KEY),
			"members": Steam.getNumLobbyMembers(lobby),
			"max_members": Steam.getLobbyMemberLimit(lobby),
		})
	lobby_list_received.emit(found)


func _on_join_requested(lobby: int, _friend_id: int) -> void:
	# An invite or a friend's "Join Game". Inside a world there is nowhere to show the new
	# lobby yet, so it is left to the menus.
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.is_in_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP):
		return
	join_lobby(lobby)


func _on_persona_state_change(steam_id: int, _flags: int) -> void:
	profile_changed.emit(steam_id)


## When the lobby's owner has a world running and we are a guest, connect to it.
func _connect_to_running_game() -> void:
	if _connecting or not has_lobby() or is_lobby_owner() or not is_game_running():
		return
	if _has_game_peer():
		return
	var peer := SteamMultiplayerPeer.new()
	var error := peer.connect_to_lobby(SteamNetwork.lobby_id)
	if error != OK:
		join_failed.emit("Could not connect to the host's game (error %d)." % error)
		return
	_connecting = true
	_connect_serial += 1
	var serial := _connect_serial
	multiplayer.multiplayer_peer = peer
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func() -> void:
		if _connecting and serial == _connect_serial:
			_on_connection_failed()
	)


func _on_connected_to_server() -> void:
	if not _connecting:
		return
	_connecting = false
	world_connected.emit()


func _on_connection_failed() -> void:
	if not _connecting:
		return
	_connecting = false
	_close_game_peer()
	join_failed.emit("Could not connect to the host's game.")


## Godot always has a peer; without a game it is an offline one that reports "connected".
func _has_game_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


func _close_game_peer() -> void:
	if _has_game_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _describe_enter_response(response: int) -> String:
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
			return "That game no longer exists."
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
			return "You are not allowed to join that game."
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
			return "That game is full."
		Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:
			return "You are banned from that game."
		Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED:
			return "Limited Steam accounts cannot join that game."
		Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU, Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER:
			return "A player in that game has blocked you, or you blocked them."
		Steam.CHAT_ROOM_ENTER_RESPONSE_RATE_LIMIT_EXCEEDED:
			return "You are joining games too quickly. Try again in a moment."
	return "Could not join that game (error %d)." % response


## Ends the running game and returns to being a party. The owner's lobby goes back to
## friends-only with no world; a guest leaves the host's lobby for a fresh one of their own.
func end_game() -> void:
	_connecting = false
	if not has_lobby():
		_close_game_peer()
		return
	if is_lobby_owner():
		_close_game_peer()
		var lobby := SteamNetwork.lobby_id
		Steam.setLobbyData(lobby, WORLD_KEY, "")
		Steam.setLobbyData(lobby, STATE_KEY, STATE_MENU)
		Steam.setLobbyType(lobby, Steam.LOBBY_TYPE_FRIENDS_ONLY)
		lobby_data_changed.emit()
	else:
		leave_lobby()
