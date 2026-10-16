extends SceneTree
## Plays the real game's way in: main menu, host a new world, play (jump), go back to the menu, see the
## jump count on the world's card, and continue the world from where it was. The whole loop, through
## the real scenes and the real save files (in a temporary folder).
##
## godot --headless --path . -s res://Components/Jump/Testing/jump_flow_test.gd
##
## With a window and SHOTS set to a folder it also saves screenshots. Steam cannot load in a second
## process while the editor has the project open: run it from a copy of the project.
##
## (A script run with -s cannot name the autoloads or the classes that use them, so the director is
## reached through get() and call().)

var _failures := 0
var _shots_dir := ""
var _temp_root := ""


func _initialize() -> void:
	_shots_dir = OS.get_environment("SHOTS")
	_run()


func _run() -> void:
	await process_frame
	_temp_root = "user://jump_flow_test_%d" % Time.get_ticks_usec()
	WorldSaves.root = _temp_root
	WorldSaves.active_slot = 0
	if bool(root.get_node("SteamNetwork").get("is_active")):
		# The boot menu normally does this.
		await root.get_node("SteamLobby").call("create_lobby")

	print("-- a new world")
	var menu := await _open_main_menu()
	await _open_host_menu(menu)
	var card := _slot_card(menu, 0)
	_check(card.tag_label.text == "NEW WORLD" and not card.jump_box.visible, "slot 1 is empty, and shows no jump count")
	card.pressed.emit()
	var in_world := await _wait_until(func() -> bool: return current_scene != null and current_scene.is_in_group("gameplay_scene"), 30.0)
	_check(in_world, "the world loads")
	if not in_world:
		_finish()
		return
	var director := await _find_director()
	_check(director != null, "with a jump director in it")
	if director == null:
		_finish()
		return
	_check(WorldSaves.active_slot == 1, "slot 1 is the active world")
	var saved := WorldSaves.read_slot(1)
	_check(saved["world_seed"] > 0 and saved["jump_count"] == 0, "its save has a seed (%d) and no jumps" % saved["world_seed"])
	_check(await _wait_until(func() -> bool: return director.get("system") != null, 10.0), "the first system is made")
	_check(director.get("world_seed") == saved["world_seed"] and director.get("jump_count") == 0, "from the seed the save holds, at jump 0")
	var first_system_seed: int = director.get("system").system_seed
	_check(first_system_seed == StarSystem.create(saved["world_seed"], 0).system_seed, "from the seed and jump 0")
	_check(await _wait_until(func() -> bool: return director.get("phase") == 0, 40.0), "the ship arrives in it (the bubble burns away)")
	_shot("1_arrived")
	_check(root.get_node_or_null("InGameUIHandler") != null and bool(root.get_node("InGameUIHandler").call("is_pause_permitted")), "and the game can be paused")

	print("-- jumping")
	director.set("charge_time", 2.0)
	director.set("warp_out_time", 0.8)
	director.set("minimum_hold_time", 0.5)
	director.set("warp_in_time", 0.8)
	_check(bool(director.call("request_jump")), "the jump is started")
	_check(await _wait_until(func() -> bool: return director.get("jump_count") == 1 and director.get("phase") == 0, 60.0), "the ship jumps and arrives at jump 1")
	_shot("2_after_the_jump")
	var second_system_seed: int = director.get("system").system_seed
	_check(second_system_seed != first_system_seed and second_system_seed == StarSystem.create(saved["world_seed"], 1).system_seed, "in a new system")
	_check(WorldSaves.read_slot(1)["jump_count"] == 1, "and the save says jump 1")
	var saved_bar: float = WorldSaves.read_slot(1)["presence"]
	_check(saved_bar >= 0.0 and saved_bar <= 1.0, "with the Cosmic Presence's bar saved too (%.3f)" % saved_bar)

	print("-- back to the menu")
	root.get_node("InGameUIHandler").call("return_to_main_menu")
	var back := await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "MainMenu", 10.0)
	_check(back, "the main menu opens")
	menu = current_scene
	await _wait(1.5)
	await _open_host_menu(menu)
	card = _slot_card(menu, 0)
	_check(card.jump_box.visible and card.jump_label.text == "1", "the world's card shows jump 1 (%s)" % card.jump_label.text)
	_check(card.tag_label.text == "CONTINUE", "and offers to continue")
	_shot("3_world_card")

	print("-- continuing")
	card.pressed.emit()
	in_world = await _wait_until(func() -> bool: return current_scene != null and current_scene.is_in_group("gameplay_scene"), 30.0)
	_check(in_world, "the world loads again")
	director = await _find_director()
	_check(director != null and await _wait_until(func() -> bool: return director.get("system") != null, 10.0), "the first system of the saved world is made")
	_check(director.get("jump_count") == 1 and director.get("world_seed") == saved["world_seed"], "at jump 1, with the same seed")
	_check(director.get("system").system_seed == second_system_seed, "in the same system as before")
	_check(await _wait_until(func() -> bool: return director.get("phase") == 0, 40.0), "and the ship arrives in it")
	_check(absf(director.get("presence").progress - saved_bar) < 0.02, "with the presence where the jump left it (%.3f)" % director.get("presence").progress)
	_check(WorldSaves.read_slot(1)["jump_count"] == 1, "nothing was lost from the save")
	root.get_node("InGameUIHandler").call("return_to_main_menu")
	await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "MainMenu", 10.0)
	_finish()


func _finish() -> void:
	WorldSaves.root = "user://worlds"
	WorldSaves.active_slot = 0
	_remove_dir(_temp_root)
	if _failures == 0:
		print("Jump flow tests passed.")
	else:
		print("Jump flow tests FAILED: %d check(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _open_main_menu() -> Node:
	var menu := (load("res://Scenes/UI/MainMenu/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _wait(1.5)
	return menu


func _open_host_menu(menu: Node) -> void:
	menu.get_node("%HostButton").pressed.emit()
	await _wait(0.5)


func _slot_card(menu: Node, index: int) -> WorldSlotCard:
	return menu.get_node("%HostGameMenu/PanelContainer/Layout/SlotList").get_child(index) as WorldSlotCard


func _find_director() -> Node:
	for _attempt in 100:
		var found := get_nodes_in_group(&"jump_director")
		if not found.is_empty():
			return found[0]
		await _wait(0.1)
	return null


func _remove_dir(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		_remove_dir("%s/%s" % [path, dir])
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file])
	DirAccess.remove_absolute(path)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if condition.call():
			return true
		await _wait(0.05)
		waited += 0.05
	return false


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	root.get_texture().get_image().save_png("%s/%s.png" % [_shots_dir, shot_name])


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)
