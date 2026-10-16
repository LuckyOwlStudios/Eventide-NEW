extends SceneTree
## Plays the real start of the game: the studio title fades in and out, the boot menu waits
## for a button, setup runs, and the main menu opens. Takes about half a minute in real time.
##
## godot --headless --path . -s res://Scenes/UI/Testing/startup_flow_test.gd
##
## With a window (no --headless) and SHOTS set to a folder, it also saves screenshots of
## every screen there:
## SHOTS=C:/some/folder godot --path . --resolution 1980x1080 -s res://Scenes/UI/Testing/startup_flow_test.gd
##
## Steam cannot load in a second process while the editor has the project open: run it from
## a copy of the project.

const MAIN_SCENE := "res://Scenes/UI/main.tscn"

var _failures := 0
var _shots_dir := ""


func _initialize() -> void:
	_shots_dir = OS.get_environment("SHOTS")
	_run()


func _run() -> void:
	# The autoloads and the root are not ready until the first frame.
	await process_frame
	# ONLY=flow, splash or world runs just that case.
	var only := OS.get_environment("ONLY")
	if only.is_empty() or only == "flow":
		await _test_full_flow()
	if only.is_empty() or only == "splash":
		await _test_skipping_the_splash()
	if only.is_empty() or only == "world":
		await _test_launching_a_world()
	if _failures == 0:
		print("Startup flow tests passed.")
	else:
		print("Startup flow tests FAILED: %d check(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _test_full_flow() -> void:
	print("-- full flow")
	var startup := _start()
	var splash: Label = startup.get_node("%SplashLabel")
	var boot_page: Control = startup.get_node("%BootPage")
	var prompt: Label = startup.get_node("%PromptLabel")
	var status: Label = startup.get_node("%StatusLabel")

	_check(splash.modulate.a < 0.1 and not boot_page.visible, "the game opens on a black screen (title alpha %.2f, boot page shown: %s)" % [splash.modulate.a, boot_page.visible])
	_check(splash.text == "A LuckyOwl Game", "with the studio title waiting to appear")
	await _wait(0.9)
	_check(splash.modulate.a > 0.1 and splash.modulate.a < 0.95, "the title fades in (%.2f)" % splash.modulate.a)
	await _wait(1.4)
	_shot("1_splash")
	_check(is_equal_approx(splash.modulate.a, 1.0) and not boot_page.visible, "and holds at full strength")
	await _wait(1.4)
	_check(splash.modulate.a < 1.0 and splash.modulate.a > 0.0, "then fades out (%.2f)" % splash.modulate.a)
	var reached_boot := await _wait_until(func() -> bool: return startup.get("_phase") == 2, 8.0)
	_check(reached_boot, "the boot menu comes up after the title")
	_check(boot_page.visible and not is_instance_valid(splash), "with the intro removed")
	await _wait(0.3)
	_shot("2_boot_waiting")
	_check(prompt.text == "PRESS ANY BUTTON" and status.text.is_empty(), "it asks for any button and has nothing to report yet")

	# Mouse movement and held keys must not count.
	var motion := InputEventMouseMotion.new()
	root.push_input(motion)
	await _wait(0.3)
	_check(startup.get("_phase") == 2, "moving the mouse does nothing")

	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	root.push_input(press)
	await _wait(0.1)
	_check(startup.get("_phase") == 3, "pressing a button starts the setup")
	var seen := ""
	var waited := 0.0
	while waited < 20.0 and is_instance_valid(startup):
		if not status.text.is_empty():
			seen = status.text
		if waited > 0.6 and waited < 0.8:
			_shot("3_boot_running")
		await _wait(0.05)
		waited += 0.05
	var changed := not is_instance_valid(startup)
	_check(changed, "the setup finishes and hands over (%.1fs)" % waited)
	var lines := seen.split("\n")
	_check(lines.size() == 3, "it reported each of its three steps")
	if SteamNetworkProbe.is_active(root):
		_check(lines[0].begins_with("STEAM: CONNECTED AS "), "Steam: %s" % lines[0])
		_check(lines[1] == "LOBBY: READY", "lobby: %s" % lines[1])
	else:
		_check(lines[0].begins_with("STEAM: OFFLINE"), "Steam: %s" % lines[0])
	_check(lines[2] == "MENU: READY", "menu: %s" % lines[2])

	var menu := current_scene
	_check(menu != null and menu.name == "MainMenu", "the main menu is now showing")
	await _wait(1.6)
	_shot("4_main_menu")
	var host_button: Button = menu.get_node("%HostButton")
	_check(menu.get_viewport().gui_get_focus_owner() == host_button, "with the first option selected")

	for page in [["%HostButton", "%HostGameMenu", "5_host_game"], ["%JoinButton", "%JoinGameMenu", "6_join_game"], ["%OptionsButton", "%SettingsMenu", "7_options"]]:
		menu.get_node(page[0]).pressed.emit()
		await _wait(1.2 if page[1] == "%JoinGameMenu" else 0.6)
		_shot(page[2])
		_check(menu.get_node(page[1]).visible, "%s opens" % page[1].trim_prefix("%"))
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		root.push_input(escape)
		await _wait(0.5)
	menu.queue_free()
	await _wait(0.2)


func _test_skipping_the_splash() -> void:
	print("-- skipping the splash")
	var startup := _start()
	var splash: Label = startup.get_node("%SplashLabel")
	await _wait(0.8)
	_check(startup.get("_phase") == 0 and splash.modulate.a > 0.0, "the title is showing")
	var press := InputEventKey.new()
	press.keycode = KEY_ENTER
	press.pressed = true
	root.push_input(press)
	await _wait(0.05)
	var reached_boot := await _wait_until(func() -> bool: return startup.get("_phase") == 2, 3.0)
	_check(reached_boot, "pressing a button skips straight to the boot menu")
	_check(not is_instance_valid(splash) and startup.get_node("%BootPage").modulate.a == 1.0, "with no fade: the intro is gone and the boot menu fully shown")
	startup.queue_free()
	await _wait(0.2)


func _test_launching_a_world() -> void:
	print("-- launching a world")
	var temp_root := "user://startup_flow_test_%d" % Time.get_ticks_usec()
	WorldSaves.root = temp_root
	if SteamNetworkProbe.is_active(root):
		# The boot menu normally does this.
		_check(await root.get_node("SteamLobby").call("create_lobby"), "the player has a lobby to host from")
	var menu := (load("res://Scenes/UI/MainMenu/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _wait(1.5)
	menu.get_node("%HostButton").pressed.emit()
	await _wait(0.5)
	var card := menu.get_node("%HostGameMenu/PanelContainer/Layout/SlotList").get_child(0) as WorldSlotCard
	_check(card.tag_label.text == "NEW WORLD", "the first slot is empty")
	card.pressed.emit()
	await _wait(0.3)
	_check(menu.get_node("%FadeRect").color.a > 0.0, "choosing it fades the menu out")
	var in_world := await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "World", 30.0)
	_check(in_world, "the world loads")
	if in_world:
		await _wait(1.0)
		var info := WorldSaves.read_slot(1)
		_check(info["exists"] and info["name"] == "World 1" and WorldSaves.active_slot == 1, "a world was made in slot 1 and is the active one")
		if SteamNetworkProbe.is_active(root):
			_check(root.get_node("SteamLobby").call("is_game_running"), "the lobby says a game is running")
		var handler := root.get_node("InGameUIHandler")
		_check(handler.call("is_pause_permitted"), "the pause menu is available in the world")
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "and the mouse is captured for play")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		root.push_input(escape)
		await _wait(0.6)
		_check(handler.get("pause_menu").visible, "Escape opens the pause menu")
		_shot("8_pause_in_world")

		var pause_menu: Node = handler.get("pause_menu")
		var main_button: Button = pause_menu.get_node("%MainMenuButton")
		var quit_button: Button = pause_menu.get_node("%QuitButton")
		_check(ConfirmationButton.new().confirmation_message == "Are you sure?", "a confirmation button asks 'Are you sure?' by default")
		_check(quit_button.get("confirmation_message") == "Quit to desktop?" and str(main_button.get("confirmation_message")).begins_with("Return to the main menu?"), "the pause menu buttons carry their own messages")
		main_button.pressed.emit()
		await _wait(0.4)
		var prompt := pause_menu.get_parent().get_node_or_null("ConfirmPrompt")
		_check(prompt != null, "pressing Return to Main Menu opens a prompt")
		if prompt != null:
			_check(prompt.get_node("%MessageLabel").text.begins_with("Return to the main menu?"), "showing that button's message")
			_check(prompt.get_node("%NoButton").has_focus(), "with No selected")
			_shot("11_confirm_prompt")
			root.push_input(escape)
			await _wait(0.4)
			_check(not is_instance_valid(prompt) or prompt.is_queued_for_deletion(), "Escape closes the prompt")
			_check(current_scene.name == "World" and pause_menu.visible, "and stays in the paused game")
			main_button.pressed.emit()
			await _wait(0.4)
			prompt = pause_menu.get_parent().get_node_or_null("ConfirmPrompt")
			prompt.get_node("%YesButton").pressed.emit()
			var back := await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "MainMenu", 10.0)
			_check(back, "answering Yes returns to the main menu")
			_check(not handler.get("pause_menu").visible and not get_root_paused(), "with the game unpaused")
			if SteamNetworkProbe.is_active(root):
				_check(not root.get_node("SteamLobby").call("is_game_running"), "and the lobby back to not running a game")
	WorldSaves.root = "user://worlds"
	WorldSaves.active_slot = 0
	_remove_dir(temp_root)


func get_root_paused() -> bool:
	return paused


func _start() -> Node:
	var startup := (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(startup)
	current_scene = startup
	return startup


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


## Asks the SteamNetwork autoload without naming it, which this script cannot do at compile time.
class SteamNetworkProbe:
	static func is_active(tree_root: Node) -> bool:
		return bool(tree_root.get_node("SteamNetwork").get("is_active"))
