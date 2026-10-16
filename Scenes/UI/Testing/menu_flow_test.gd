extends Node
## Headless checks for the world slots, the Steam lobby, and the main, host and join menus.
## The lobby checks use the real Steam client and are skipped when Steam did not start.
##
## godot --headless --fixed-fps 60 --path . res://Scenes/UI/Testing/MenuFlowTest.tscn
## (Steam cannot load in a second process while the editor has the project open: run it
## from a copy of the project.)

var _failures := 0
var _test_root := ""


func _ready() -> void:
	_test_root = "user://menu_flow_test_%d" % Time.get_ticks_usec()
	WorldSaves.root = _test_root
	SteamProfile.open_override = Callable()

	_test_world_saves()
	await _test_steam_lobby()
	await _test_host_menu()
	await _test_main_menu()
	await _test_lobby_panel()

	_remove_dir(_test_root)
	if _failures == 0:
		print("Menu flow tests passed.")
	else:
		print("Menu flow tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- World slots --------------------------------------------------------------

func _test_world_saves() -> void:
	print("-- world saves")
	var slots := WorldSaves.list_slots()
	_check(slots.size() == WorldSaves.SLOT_COUNT and WorldSaves.SLOT_COUNT == 4, "there are four slots")
	_check(slots.all(func(info: Dictionary) -> bool: return not info["exists"]), "a fresh install has no worlds")
	_check(WorldSaves.read_slot(1)["slot"] == 1 and WorldSaves.read_slot(4)["slot"] == 4, "slots are numbered from 1")

	var created := WorldSaves.create_world(2, "Alpha")
	_check(not created.is_empty() and created["exists"] and created["name"] == "Alpha", "a world can be created in an empty slot")
	_check(created["created"] > 0 and created["last_played"] == created["created"], "a new world records when it was made")
	_check(WorldSaves.read_slot(2)["name"] == "Alpha", "and it reads back")
	_check(WorldSaves.create_world(2, "Beta").is_empty(), "a taken slot refuses a new world")
	_check(WorldSaves.read_slot(2)["name"] == "Alpha", "and keeps the world it had")
	_check(WorldSaves.create_world(0).is_empty() and WorldSaves.create_world(5).is_empty(), "slots outside 1 to 4 do not exist")
	_check(WorldSaves.create_world(3)["name"] == "World 3", "an unnamed world is named after its slot")
	_check(WorldSaves.create_world(1, "   ")["name"] == "World 1", "a blank name counts as unnamed")

	_write_text("%s/slot_2/%s" % [_test_root, WorldSaves.META_FILE], JSON.stringify({
		"version": 1, "name": "Alpha", "created": 1000, "last_played": 2000,
	}))
	WorldSaves.mark_played(2)
	var played := WorldSaves.read_slot(2)
	_check(played["last_played"] > 2000 and played["created"] == 1000 and played["name"] == "Alpha", "playing a world updates only when it was last played")

	_write_text("%s/slot_4/%s" % [_test_root, WorldSaves.META_FILE], "{ this is not json")
	var broken := WorldSaves.read_slot(4)
	_check(broken["exists"] and broken["corrupt"], "a save with unreadable metadata is flagged, not hidden")
	_check(WorldSaves.create_world(4, "Gamma").is_empty(), "and is never overwritten by a new world")
	WorldSaves.mark_played(4)
	_check(FileAccess.get_file_as_string("%s/slot_4/%s" % [_test_root, WorldSaves.META_FILE]) == "{ this is not json", "or touched by playing")

	_check(WorldSaves.format_time(0) == "", "an unknown time shows nothing")
	var now := Time.get_datetime_dict_from_system()
	var expected := "%04d-%02d-%02d %02d:%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"]]
	_check(WorldSaves.format_time(int(Time.get_unix_time_from_system())) == expected, "times are shown in local time (%s)" % expected)


# --- Steam lobby ----------------------------------------------------------------

func _test_steam_lobby() -> void:
	print("-- steam lobby")
	_check(SteamProfile.profile_url(76561198231935932) == "https://steamcommunity.com/profiles/76561198231935932", "a profile link points at the Steam community page")
	_check(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "before hosting there is only Godot's offline peer")
	if not SteamNetwork.is_active:
		print("   (Steam is not running; lobby checks skipped)")
		_check(not SteamLobby.is_available() and not SteamLobby.has_lobby(), "offline, there is no lobby")
		_check(not await SteamLobby.create_lobby(), "and creating one reports failure instead of hanging")
		_check(SteamLobby.get_members().is_empty(), "with nobody in it")
		_check(SteamLobby.host_world("Offline World") == OK, "hosting offline just succeeds, so single player starts the same way")
		var offline_list: Array = await _await_lobby_list()
		_check(offline_list.is_empty(), "and the game list is empty")
		return

	_check(SteamLobby.is_available() and not SteamLobby.has_lobby(), "Steam is up and there is no lobby yet")
	var created := await SteamLobby.create_lobby()
	_check(created and SteamLobby.has_lobby(), "a lobby is created")
	_check(SteamLobby.is_lobby_owner(), "we own it")
	_check(await SteamLobby.create_lobby(), "asking again keeps the same lobby")
	var lobby := SteamNetwork.lobby_id
	_check(lobby > 0, "SteamNetwork knows which lobby it is")
	_check(Steam.getLobbyData(lobby, SteamLobby.GAME_KEY) == SteamLobby.GAME_TAG, "it is tagged as this game's lobby")
	_check(Steam.getLobbyData(lobby, SteamLobby.STATE_KEY) == SteamLobby.STATE_MENU, "and has not started a world")
	_check(Steam.getLobbyData(lobby, SteamLobby.HOST_KEY) == SteamNetwork.persona_name, "and names its host")
	_check(not SteamLobby.is_game_running(), "so no game is running")
	var members := SteamLobby.get_members()
	_check(members.size() == 1 and members[0]["steam_id"] == SteamNetwork.steam_id, "we are its only member")
	_check(members[0]["is_owner"] and members[0]["is_local"], "marked as the host and as us")
	_check(members[0]["name"] == SteamNetwork.persona_name, "with our Steam name (%s)" % members[0]["name"])
	_check(SteamLobby.get_max_members() == SteamLobby.MAX_MEMBERS, "it holds %d players" % SteamLobby.MAX_MEMBERS)

	var list: Array = await _await_lobby_list()
	_check(list.all(func(info: Dictionary) -> bool: return info["lobby_id"] != lobby), "the game list never offers our own lobby")
	print("   (%d other eventide game(s) are listed right now)" % list.size())

	var failures_seen: Array[String] = []
	var on_failed := func(message: String) -> void: failures_seen.append(message)
	SteamLobby.join_failed.connect(on_failed)
	var joined := await SteamLobby.join_lobby(1)
	_check(not joined and not failures_seen.is_empty(), "joining a lobby that does not exist fails with a message (%s)" % ("" if failures_seen.is_empty() else failures_seen[0]))
	_check(SteamNetwork.lobby_id == lobby, "and leaves us in our own lobby")
	SteamLobby.join_failed.disconnect(on_failed)

	var error := SteamLobby.host_world("Test World")
	_check(error == OK, "hosting a world works")
	_check(multiplayer.multiplayer_peer is SteamMultiplayerPeer, "the game now runs on the Steam peer")
	_check(NetworkSession.is_server() and not NetworkSession.has_remote_peers(), "as a server waiting for players")
	_check(Steam.getLobbyData(lobby, SteamLobby.WORLD_KEY) == "Test World", "the lobby names the world")
	_check(SteamLobby.is_game_running(), "and says it has started")
	_check(SteamLobby.host_world("Again") != OK, "a second world cannot be hosted over the first")

	SteamLobby.leave_lobby()
	await get_tree().process_frame
	_check(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "leaving the lobby closes the game")
	_check(await SteamLobby.create_lobby() and SteamNetwork.lobby_id != lobby, "and we end up in a fresh lobby of our own")
	_check(Steam.getLobbyData(SteamNetwork.lobby_id, SteamLobby.STATE_KEY) == SteamLobby.STATE_MENU, "which has not started a world")


# --- Host menu ---------------------------------------------------------------------

func _test_host_menu() -> void:
	print("-- host menu")
	# Slot 1 and 2 hold worlds, slot 3 is empty and slot 4 is damaged.
	_remove_dir(WorldSaves.slot_dir(3))
	var menu := (load("res://Scenes/UI/MainMenu/HostGameMenu.tscn") as PackedScene).instantiate() as HostGameMenu
	add_child(menu)
	var closed_count := [0]
	menu.closed.connect(func() -> void: closed_count[0] += 1)
	var chosen: Array[int] = []
	menu.world_chosen.connect(chosen.append)
	menu.open()
	await get_tree().process_frame
	await get_tree().process_frame

	var cards := _slot_cards(menu)
	_check(menu.visible and cards.size() == 4, "the menu lists four slots")
	_check(cards[2].name_label.text == "EMPTY SLOT" and cards[2].tag_label.text == "NEW WORLD", "an empty slot offers a new world")
	_check(cards[1].name_label.text == "Alpha" and cards[1].tag_label.text == "CONTINUE", "a saved world shows its name and offers to continue")
	_check(cards[0].name_label.text == "World 1" and not cards[0].disabled, "worlds never named get their slot's name")
	_check(cards[1].detail_label.text.begins_with("Last played 20"), "with when it was last played (%s)" % cards[1].detail_label.text)
	_check(cards[3].disabled and cards[3].name_label.text == "UNREADABLE SAVE", "a damaged save is shown but cannot be chosen")
	_check(cards[0].number_label.text == "01" and cards[3].number_label.text == "04", "slots are numbered")

	cards[1].pressed.emit()
	cards[2].pressed.emit()
	_check(chosen == [2, 3], "choosing a slot reports its number")

	cards[1].focus_entered.emit()
	_check(menu.description_label.text.begins_with("Continue Alpha"), "focusing a slot describes it")
	menu.set_description("Could not start.")
	_check(menu.description_label.text == "Could not start.", "the main menu can report a failure here")

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	_check(not menu.visible and closed_count[0] == 1, "Escape closes the menu")
	menu.queue_free()


# --- Main menu -------------------------------------------------------------------------

func _test_main_menu() -> void:
	print("-- main menu")
	var menu := (load("res://Scenes/UI/MainMenu/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await get_tree().create_timer(1.3).timeout

	_check(is_zero_approx(menu.fade_rect.color.a), "the menu fades up from black")
	_check(menu.main_panel.visible and not menu.host_menu.visible and not menu.join_menu.visible and not menu.settings_menu.visible, "it opens on the main page")
	var labels := [menu.host_button.text, menu.join_button.text, menu.options_button.text, menu.exit_button.text]
	_check(labels == ["HOST GAME", "JOIN GAME", "OPTIONS", "EXIT GAME"], "with the four options")
	_check(menu.get_viewport().gui_get_focus_owner() == menu.host_button, "and Host Game is selected")
	var title := menu.get_node("MainPanel/GameTitle")
	_check(title.get_node("Name").text + title.get_node("Subtitle").text == "EVENTIDE: The last voyage", "the title reads EVENTIDE: The last voyage")
	_check(menu.get_node("SpaceBackdrop/Camera3D").current, "a space backdrop is behind it")

	for page_case in [
		["host", menu.host_button, menu.host_menu],
		["join", menu.join_button, menu.join_menu],
		["options", menu.options_button, menu.settings_menu],
	]:
		var opener: Button = page_case[1]
		var page: Control = page_case[2]
		opener.pressed.emit()
		await get_tree().process_frame
		_check(page.visible and not menu.main_panel.visible, "%s opens its page" % page_case[0])
		_check(menu.dimmer.dim_amount > 0.0 or menu.dimmer.visible, "and dims the backdrop")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		menu.get_viewport().push_input(escape)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not page.visible and menu.main_panel.visible, "Escape returns from %s" % page_case[0])
		_check(menu.get_viewport().gui_get_focus_owner() == opener, "with %s selected again" % opener.text)

	# Focus wraps around the four buttons.
	menu.host_button.grab_focus()
	_check(menu.host_button.get_node(menu.host_button.focus_neighbor_top) == menu.exit_button, "focus wraps from Host Game up to Exit Game")
	_check(menu.exit_button.get_node(menu.exit_button.focus_neighbor_bottom) == menu.host_button, "and from Exit Game down to Host Game")

	# Without a lobby of our own to host from, Host Game is unavailable.
	if SteamNetwork.is_active:
		_check(not menu.host_button.disabled, "as the owner of the lobby, we can host")
	menu.queue_free()


# --- Lobby panel ---------------------------------------------------------------------------

func _test_lobby_panel() -> void:
	print("-- lobby panel")
	var panel := (load("res://Scenes/UI/Lobby/LobbyPanel.tscn") as PackedScene).instantiate() as LobbyPanel
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	if not SteamNetwork.is_active:
		_check(panel.cards.get_child_count() == 0, "offline, no one is listed")
		_check(panel.status_label.visible and panel.status_label.text.begins_with("Steam is offline"), "and it says why")
		_check(not panel.invite_button.visible and not panel.leave_button.visible, "with nothing to invite to or leave")
		panel.queue_free()
		return

	_check(panel.cards.get_child_count() == 1, "our own card is listed")
	var card := panel.cards.get_child(0) as LobbyPlayerCard
	_check(card.steam_id == SteamNetwork.steam_id, "it is ours")
	_check(card.name_label.text == SteamNetwork.persona_name, "with our name")
	_check(card.role_label.text == "HOST / YOU", "marked as host and as us")
	_check(panel.count_label.text == "1 / 4", "the count reads 1 / 4")
	_check(panel.invite_button.visible and not panel.leave_button.visible, "we can invite friends but have no lobby to leave")
	_check(panel.status_label.text.begins_with("Invite friends"), "and the panel suggests inviting friends")

	var opened: Array[int] = []
	SteamProfile.open_override = func(steam_id: int) -> void: opened.append(steam_id)
	card.pressed.emit()
	_check(opened == [SteamNetwork.steam_id], "clicking a player card opens that player's Steam page")
	SteamProfile.open_override = Callable()

	await get_tree().create_timer(2.0).timeout
	print("   (avatar loaded: %s)" % (card.avatar_rect.texture != null))
	panel.queue_free()


# --- Helpers -------------------------------------------------------------------------------

func _slot_cards(menu: HostGameMenu) -> Array[WorldSlotCard]:
	var cards: Array[WorldSlotCard] = []
	for child in menu.slot_list.get_children():
		cards.append(child as WorldSlotCard)
	return cards


## Asks for the game list and waits for the answer, or gives up after a few seconds.
func _await_lobby_list() -> Array:
	var result := []
	var received := [false]
	var on_list := func(lobbies: Array[Dictionary]) -> void:
		result.assign(lobbies)
		received[0] = true
	SteamLobby.lobby_list_received.connect(on_list)
	SteamLobby.request_lobby_list()
	var waited := 0.0
	while not received[0] and waited < 25.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	SteamLobby.lobby_list_received.disconnect(on_list)
	_check(received[0], "Steam answers a request for the game list")
	return result


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _remove_dir(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		_remove_dir("%s/%s" % [path, dir])
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file])
	DirAccess.remove_absolute(path)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)
