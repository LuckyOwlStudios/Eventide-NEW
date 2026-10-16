extends Node
## Plays the whole loop in a small world with the real Mule and Player: the Cosmic Presence closing in, the last
## countdown, the bubble, what a jump keeps and deletes, the count and seed, the presence left behind, saving,
## loading, an early jump, pausing and the HUD.
##
## godot --headless --fixed-fps 60 --path . res://Components/Jump/Testing/JumpDirectorTest.tscn

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const DIRECTOR_SCENE := preload("res://Components/Jump/JumpDirector.tscn")
const BATTERY := preload("res://Game/Registry/Items/Battery/battery_item.tres")
const Kit := preload("res://Components/Space/Testing/space_test_kit.gd")

const PHASE_NAMES := ["IN_SYSTEM", "CHARGING", "WARPING_OUT", "SWITCHING", "WARPING_IN"]
## How long the presence takes to cross the bar in the test worlds (and so how fast it goes: 1/20 of it a second).
const FILL_TIME := 20.0

var _failures := 0
var _test_root := ""
var _world: Node3D
var _mule: Mule
var _player: Player
var _director: JumpDirector
var _phases: Array[int] = []
var _warnings: Array[int] = []
var _started_jumps: Array[int] = []
var _completed_jumps: Array[int] = []
var _system_events: Array[int] = []
var _reliefs: Array[float] = []
var _tuning: SystemTuning
var _recenter := 5000.0
var _debug_template: SystemTemplate


func _ready() -> void:
	_run()


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InGameUIHandler.is_ui_open = false
	_test_root = "user://jump_director_test_%d" % Time.get_ticks_usec()
	WorldSaves.root = _test_root
	_tuning = SystemTuning.new()
	_tuning.easy_fill_time = 600.0
	_tuning.hard_fill_time = 300.0

	_test_hud_formats()
	await _test_the_real_world()
	await _test_a_full_jump()
	await _test_recentering()
	await _test_loading_a_saved_world()
	await _test_arrival_at_start()
	await _test_the_kind_of_system()
	await _test_presence_in_the_loop()
	await _test_pausing_and_debug_keys()
	await _test_without_a_ship()

	WorldSaves.active_slot = 0
	WorldSaves.root = "user://worlds"
	_remove_dir(_test_root)
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Jump director tests passed.")
	else:
		print("Jump director tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------------------------------

func _build_world(slot: int, arrive_at_start: bool, fill_time := FILL_TIME) -> void:
	WorldSaves.active_slot = slot
	_world = Node3D.new()
	_world.add_to_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP)
	# This test keeps running while the game is paused; the world it checks does not.
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	_mule = MULE_SCENE.instantiate() as Mule
	_world.add_child(_mule)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector3(0.0, 0.1, 1.5)
	_world.add_child(_player)
	_director = DIRECTOR_SCENE.instantiate() as JumpDirector
	_director.ship = _mule
	_director.tuning = _tuning
	_director.debug_fill_time = fill_time
	_director.charge_time = 3.0
	_director.warp_out_time = 0.6
	_director.minimum_hold_time = 0.3
	_director.warp_in_time = 0.6
	_director.arrive_at_start = arrive_at_start
	_director.recenter_distance = _recenter
	_director.debug_seed = 424242
	_director.debug_template = _debug_template
	_phases.clear()
	_warnings.clear()
	_started_jumps.clear()
	_completed_jumps.clear()
	_system_events.clear()
	_reliefs.clear()
	_director.phase_changed.connect(func(phase: JumpDirector.Phase) -> void: _phases.append(phase))
	_director.warning.connect(func(seconds: int) -> void: _warnings.append(seconds))
	_director.jump_started.connect(func(count: int) -> void: _started_jumps.append(count))
	_director.jump_completed.connect(func(count: int) -> void: _completed_jumps.append(count))
	_director.system_changed.connect(func(system: StarSystem) -> void: _system_events.append(system.jump_count))
	_world.add_child(_director)
	_director.presence.relieved.connect(func(amount: float) -> void: _reliefs.append(amount))


func _tear_down_world() -> void:
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_mule = null
	_player = null
	_director = null


func _make_crate(at: Vector3, parent: Node = null) -> RigidBody3D:
	var crate := RigidBody3D.new()
	crate.collision_layer = PhysicsLayers.ITEMS
	crate.collision_mask = PhysicsLayers.ITEM_MASK
	crate.mass = 20.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	crate.add_child(shape)
	(parent if parent != null else _world).add_child(crate)
	crate.global_position = at
	return crate


func _wait_for_phase(phase: JumpDirector.Phase, max_frames: int) -> bool:
	var frames := 0
	while _director.phase != phase and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	return _director.phase == phase


## The asteroids in a ring around two arrival points, far enough out that neither arrival can have changed
## them (an arrival only clears the chunks it touches) and near enough that both sessions had loaded them
## (the ship was not in quite the same place), in a fixed order.
func _far_field(streamer: ChunkStreamer, arrival_a: Vector3, arrival_b: Vector3) -> PackedVector3Array:
	var kept := PackedVector3Array()
	for position in _asteroid_signature(streamer):
		var near := minf(position.distance_to(arrival_a), position.distance_to(arrival_b))
		var far := maxf(position.distance_to(arrival_a), position.distance_to(arrival_b))
		if near > 1200.0 and far < 1400.0:
			kept.append(position)
	return kept


func _asteroid_signature(streamer: ChunkStreamer) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var coords := streamer.get_loaded_coords()
	coords.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	for coord in coords:
		var chunk := streamer.get_chunk(coord)
		if chunk != null:
			for child in chunk.get_children():
				positions.append((child as Node3D).global_position)
	return positions


# --- How the HUD writes things ------------------------------------------------------------------------

func _test_hud_formats() -> void:
	print("What the HUD writes")
	_check(JumpHud.format_multiplier(1.0) == "x1" and JumpHud.format_multiplier(2.0) == "x2" and JumpHud.format_multiplier(10.0) == "x10", "whole speeds read x1, x2, x10")
	_check(JumpHud.format_multiplier(1.5) == "x1.5" and JumpHud.format_multiplier(0.5) == "x0.5" and JumpHud.format_multiplier(2.04) == "x2", "others get one decimal, unless it would be a zero")
	var calm := JumpHud.color_for_progress(0.0)
	var late := JumpHud.color_for_progress(1.0)
	_check(calm.b > calm.r and late.r > late.b and late.r > late.g, "the bar is cool when the presence is far, and red when it is here")


# --- The level the game actually starts in ------------------------------------------------------------

func _test_the_real_world() -> void:
	print("The real InGameSession.tscn")
	var scene := DIRECTOR_SCENE.instantiate() as JumpDirector
	_check(scene.tuning != null and is_equal_approx(scene.tuning.easy_fill_time, 1200.0) and is_equal_approx(scene.tuning.hard_fill_time, 480.0), "the director scene comes with its tuning (20 minutes to fill the bar in the first system, 8 at the hardest)")
	_check(scene.get_node_or_null("CosmicPresence") is CosmicPresence and scene.get_node_or_null("StarField") is StarField and scene.get_node_or_null("ChunkStreamer") is ChunkStreamer, "with a Cosmic Presence, a star field and a chunk streamer")
	scene.free()
	WorldSaves.active_slot = 0
	var level := (load("res://Game/InGameSession.tscn") as PackedScene).instantiate() as Node3D
	var player := level.get_node("Player") as Player
	(player.get_node("Rotator") as Rotator).capture_mouse_on_start = false
	add_child(level)
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	await _frames(3)
	var director := level.get_node_or_null("Ingame Systems/JumpDirector") as JumpDirector
	_check(director != null, "the level has a jump director among its systems")
	if director == null:
		level.free()
		return
	var mule := level.get_node("Mule")
	_check(director.ship == mule and director.streamer != null and director.presence != null, "which knows the Mule is the ship")
	_check(director.world_root != null and (director.world_root == level or level.is_ancestor_of(director.world_root)), "and which part of the level a jump clears (%s)" % director.world_root.name)
	director.charge_time = 2.0
	var arrived := false
	var frames := 0
	while frames < 1200 and not arrived:
		await get_tree().process_frame
		frames += 1
		arrived = director.phase == JumpDirector.Phase.IN_SYSTEM and director.system != null
	_check(arrived and director.jump_count == 0, "the world begins in a first system (%s)" % (director.system.system_name if director.system != null else "?"))
	_check(director.presence.progress < 0.01 and is_equal_approx(director.get_fill_time(), 1200.0), "with the Cosmic Presence far behind (%.3f) and 20 minutes to cross the bar (%.0f s)" % [director.presence.progress, director.get_fill_time()])
	_check(director.streamer.get_asteroid_count() > 100, "and an asteroid field around the ship (%d)" % director.streamer.get_asteroid_count())
	_check(director.system.get_star_count() >= 1 and director.star_field.get_child_count() >= 2, "and a star, and its light, which the star field made (%d stars)" % director.system.get_star_count())
	var handler := level.get_node_or_null("Ingame Systems/TemperatureHandler") as TemperatureHandler
	_check(handler != null and InGameHandler.get_temperature_handler_or_null() == handler, "the level has a temperature handler among its systems, which is the session's")
	_check(director.system.template != null and director.system.template.get_display_name() == "Normal System" and director.system.climate == TemperatureHandler.Climate.TEMPERATE, "the first system is a normal one, and temperate (%s)" % director.system.get_description())
	_check(handler != null and is_equal_approx(handler.get_system_temperature(), director.system.temperature) and handler.get_system_word() == "Temperate", "which the temperature handler has been told (%.1f)" % (handler.get_system_temperature() if handler != null else 0.0))
	# Something lying in the part of the level a jump clears, and something outside it.
	var crate_in_space := _make_crate(director.world_root.global_position + Vector3(0.0, 6.0, 200.0), director.world_root)
	director.set_presence(0.9999)
	var jumped := false
	frames = 0
	while frames < 2400 and not jumped:
		await get_tree().process_frame
		frames += 1
		jumped = director.jump_count == 1 and director.phase == JumpDirector.Phase.IN_SYSTEM
	_check(jumped, "the presence filling the bar jumps the ship to jump 1")
	await _frames(3)
	_check(not is_instance_valid(crate_in_space), "which deletes what was lying around in space")
	_check(is_instance_valid(mule) and is_instance_valid(player), "and keeps the ship and the player")
	_check(absf(director.presence.progress - 0.5) < 0.05, "and leaves the presence behind: half of the bar is taken off (%.3f)" % director.presence.progress)
	_check(handler != null and is_equal_approx(handler.get_system_temperature(), director.system.temperature), "and the temperature handler follows the ship to the new system (%.1f, %s)" % [director.system.temperature, director.system.template.get_display_name()])
	level.free()
	await _frames(3)


# --- One whole jump -------------------------------------------------------------------------------

func _test_a_full_jump() -> void:
	print("A world at jump 0")
	var created := WorldSaves.create_world(1, "Loop")
	_build_world(1, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var streamer := _director.streamer
	var presence := _director.presence
	_check(_director.phase == JumpDirector.Phase.IN_SYSTEM and _director.jump_count == 0, "the world starts in a system at jump 0")
	_check(_director.world_seed == created["world_seed"], "built from the saved world's seed")
	_check(_director.system != null and _director.system.jump_count == 0, "in the first system (%s)" % _director.system.system_name)
	_check(presence.progress < 0.01 and is_equal_approx(_director.get_fill_time(), FILL_TIME) and is_equal_approx(presence.get_rate(), 1.0 / FILL_TIME), "with the presence far behind, crossing the bar in the debug time (%.0f s)" % _director.get_fill_time())
	_check(is_equal_approx(presence.get_speed_multiplier(), 1.0) and presence.aggression == 0.0, "at its normal speed, and not aggressive")
	_check(_phases == [JumpDirector.Phase.IN_SYSTEM] and _completed_jumps.is_empty() and _system_events == [0], "which told everyone the first system was made")
	_phases.clear()
	_check(streamer.is_settled() and streamer.get_asteroid_count() > 100, "and its asteroids built around the ship (%d)" % streamer.get_asteroid_count())
	_check(streamer.system == _director.system, "from the same system")
	_check(_director.get_bubble() != null and _director.get_bubble().get_parent() == _mule and not _director.get_bubble().is_visible_now(), "the warp bubble is on the ship, and not showing")
	_check(_director.can_jump() and not _director.is_jumping(), "and the ship could jump")
	var hud := _director.get_node("JumpHud") as JumpHud
	_check(hud.top_panel.visible and hud.jump_label.text == "0" and hud.presence_title.text == "COSMIC PRESENCE", "the HUD shows jump 0 and the Cosmic Presence")
	_check(hud.multiplier_label.text == "x1" and is_equal_approx(hud.presence_bar.max_value, 100.0), "at x1, on a bar that counts up")
	_check(hud.system_label.text == _director.system.system_name.to_upper() and hud.climate_label.text == _director.system.get_description().to_upper(), "and the system's name and kind (%s, %s)" % [hud.system_label.text, hud.climate_label.text])
	_check(not hud.banner.visible, "and no banner")
	var first_seed := _director.system.system_seed
	var first_field := _asteroid_signature(streamer)
	var old_asteroid: Node
	for coord in streamer.get_loaded_coords():
		if streamer.get_chunk(coord) != null:
			old_asteroid = streamer.get_chunk(coord).get_child(0)
			break

	# The ship has people and things in it, and the space outside has things in it.
	var crate_in := _make_crate(_mule.to_global(Vector3(0.8, 0.4, 2.0)))
	var crate_out := _make_crate(Vector3(250.0, 0.0, 40.0))
	var battery_out := BATTERY.spawn_in_world(BATTERY.create_instance(), _world, Transform3D(Basis.IDENTITY, Vector3(-200.0, 0.0, 60.0)))
	var car_out := Vehicle3D.new()
	car_out.mass = 800.0
	var car_shape := CollisionShape3D.new()
	var car_box := BoxShape3D.new()
	car_box.size = Vector3(1.4, 0.8, 2.4)
	car_shape.shape = car_box
	car_out.add_child(car_shape)
	_world.add_child(car_out)
	car_out.global_position = Vector3(0.0, 0.0, 300.0)
	var creature_out := TestCharacter.make("Creature", PhysicsLayers.CREATURES, PhysicsLayers.CREATURE_MASK)
	_world.add_child(creature_out)
	creature_out.global_position = Vector3(-120.0, 0.0, 0.0)
	var scenery := CSGBox3D.new()
	scenery.add_to_group(JumpPurge.PURGE_GROUP)
	_world.add_child(scenery)
	scenery.global_position = Vector3(60.0, 0.0, 60.0)
	var stranded := PLAYER_SCENE.instantiate() as Player
	_world.add_child(stranded)
	stranded.global_position = Vector3(500.0, 30.0, -200.0)
	await _frames(40)
	_mule.linear_velocity = Vector3(8.0, 0.0, 3.0)
	_mule.angular_velocity = Vector3(0.0, 0.1, 0.0)

	print("Counting up")
	var before := presence.progress
	await _frames(60)
	var gained := presence.progress - before
	_check(absf(gained - 1.0 / FILL_TIME) < 0.006, "the presence covers a twentieth of the bar in a second (%.4f)" % gained)
	_check(absf(hud.presence_bar.value - presence.progress * 100.0) < 1.5, "and the HUD's bar follows it (%.1f of 100)" % hud.presence_bar.value)
	# Close the gap to 5.6 seconds from the end.
	_director.set_presence(1.0 - 5.6 / FILL_TIME)
	await _frames(60)
	_check(_director.get_time_to_full() > 4.4 and _director.get_time_to_full() < 4.8, "with the bar nearly full, a second later it is a second closer (%.2f s to full)" % _director.get_time_to_full())
	_check(presence.aggression > 0.7 and presence.aggression < 1.0, "and the presence is very aggressive (%.2f)" % presence.aggression)
	_check(_director.phase == JumpDirector.Phase.IN_SYSTEM and _phases.is_empty() and not hud.banner.visible, "with more than the charge time to go it is just a bar")
	await _frames(100)
	_check(_director.phase == JumpDirector.Phase.CHARGING and _phases == [JumpDirector.Phase.CHARGING], "in the last 3 seconds the jump is charging (%s)" % str(_phases.map(func(p: int) -> String: return PHASE_NAMES[p])))
	_check(hud.banner.visible and hud.banner_title.text == "JUMP DRIVE CHARGING" and hud.banner_detail.text.begins_with("3"), "and the HUD counts down across the screen (%s)" % hud.banner_detail.text.replace("\n", " "))
	_check(_warnings == [3], "which is announced (%s)" % str(_warnings))

	print("Jumping")
	var reached := await _wait_for_phase(JumpDirector.Phase.WARPING_OUT, 400)
	_check(reached and _started_jumps == [1], "the countdown ends in the jump starting for jump 1 (%s)" % str(_started_jumps))
	_check(_warnings == [3, 2, 1], "after counting 3, 2, 1 (%s)" % str(_warnings))
	_check(_director.jump_count == 0 and _director.system.jump_count == 0, "and the system has not changed yet")
	var bar_leaving := presence.progress
	_check(bar_leaving > 0.97, "the presence is as close as it gets (%.3f)" % bar_leaving)
	await _frames(20)
	var mid_bubble := _director.get_bubble().progress
	_check(mid_bubble > 0.0 and mid_bubble < 1.0 and _director.get_bubble().is_visible_now(), "the bubble forms around the ship (%.2f)" % mid_bubble)
	_check(hud.banner_title.text == "JUMPING", "and the HUD says so")
	_check(is_equal_approx(presence.progress, bar_leaving), "the presence waits while the ship jumps")
	_check(streamer.get_asteroid_count() > 100 and is_instance_valid(crate_out), "while the space outside is still there")
	reached = await _wait_for_phase(JumpDirector.Phase.SWITCHING, 200)
	_check(reached and is_equal_approx(_director.get_bubble().progress, 1.0), "then the bubble is whole")
	_check(_director.jump_count == 1 and _system_events == [0, 1] and _director.system.jump_count == 1, "and the jump count went up the moment the world was hidden (%d)" % _director.jump_count)
	await _frames(3)
	var second_seed := _director.system.system_seed
	_check(second_seed != first_seed and second_seed == StarSystem.create(_director.world_seed, 1, _tuning).system_seed, "the new system has a new seed, worked out from the world's seed and the count")
	_check(hud.jump_label.text == "1" and hud.system_label.text == _director.system.system_name.to_upper(), "the HUD shows jump 1 and the new system's name (%s)" % hud.system_label.text)
	_check(hud.flash.color.a > 0.1, "a flash of light covers the change (%.2f)" % hud.flash.color.a)
	_check(hud.banner_detail.text.begins_with("ENTERING"), "and the banner says where the ship is going (%s)" % hud.banner_detail.text)
	_check(not is_instance_valid(crate_out) and not is_instance_valid(battery_out) and not is_instance_valid(car_out) and not is_instance_valid(creature_out) and not is_instance_valid(scenery), "everything outside the ship is deleted: crate, battery, car, creature, scenery")
	_check(is_instance_valid(crate_in) and is_instance_valid(_player) and is_instance_valid(stranded) and is_instance_valid(_mule), "the ship, its crate and both players are not")
	_check(_mule.linear_velocity.length() < 0.5 and _mule.angular_velocity.length() < 0.05, "the ship has come to rest (%.2f m/s)" % _mule.linear_velocity.length())
	var interior := JumpPurge.get_interiors(_mule)[0]
	_check(interior.contains_point(stranded.global_position) and JumpPurge.is_aboard(stranded, _mule, [interior] as Array[VehicleInterior3D]), "the player who was left outside is brought aboard")
	_check(interior.contains_point(_player.global_position), "and the one aboard still is")
	_check(streamer.system == _director.system and not is_instance_valid(old_asteroid), "the old system's asteroids are gone, and the streamer is building the new system's")
	_check(WorldSaves.read_slot(1)["jump_count"] == 1, "the jump count is saved with the world (%d)" % WorldSaves.read_slot(1)["jump_count"])
	_check(WorldSaves.read_slot(1)["world_seed"] == created["world_seed"], "and the seed did not change")
	_check(absf(presence.progress - (bar_leaving - _tuning.jump_relief)) < 0.001 and _reliefs.size() == 1 and is_equal_approx(_reliefs[0], _tuning.jump_relief), "the jump left the presence behind: half the bar came off (%.3f)" % presence.progress)
	_check(absf(WorldSaves.read_slot(1)["presence"] - presence.progress) < 0.001, "and the bar is saved with the world (%.3f)" % WorldSaves.read_slot(1)["presence"])
	_check(is_equal_approx(presence.base_speed, 1.0 / FILL_TIME), "the presence is going the new system's speed")
	_check(hud.trail_bar.value > hud.presence_bar.value + 10.0, "the HUD's bar is sliding down, leaving a red trail behind where it was (%.0f over %.0f)" % [hud.trail_bar.value, hud.presence_bar.value])
	var hold := presence.progress
	await _frames(10)
	_check(_director.phase == JumpDirector.Phase.SWITCHING and is_equal_approx(presence.progress, hold), "it stays put until the system is built")

	print("Arriving")
	reached = await _wait_for_phase(JumpDirector.Phase.WARPING_IN, 200)
	_check(reached and streamer.is_settled() and streamer.get_asteroid_count() > 100, "the bubble burns away only once the new system's asteroids are built (%d)" % streamer.get_asteroid_count())
	_check(_asteroid_signature(streamer) != first_field, "and they are not the old ones")
	await _frames(2)
	_check(hud.banner_title.text == "ARRIVING", "the HUD says the ship is arriving")
	reached = await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 200)
	_check(reached and not _director.get_bubble().is_visible_now(), "and then the bubble is gone")
	_check(_phases.map(func(p: int) -> String: return PHASE_NAMES[p]) == ["CHARGING", "WARPING_OUT", "SWITCHING", "WARPING_IN", "IN_SYSTEM"], "the phases came in order: %s" % str(_phases.map(func(p: int) -> String: return PHASE_NAMES[p])))
	_check(_completed_jumps == [1], "and the jump is reported complete (%s)" % str(_completed_jumps))
	var arrived_bar := presence.progress
	await _frames(60)
	_check(presence.progress > arrived_bar + 0.04, "the presence starts closing in again (%.3f to %.3f)" % [arrived_bar, presence.progress])
	await _frames(5)
	_check(hud.banner.visible and hud.banner_title.text == "ARRIVED" and "JUMP 1" in hud.banner_detail.text, "the HUD welcomes the crew to the new system (%s)" % hud.banner_detail.text.replace("\n", " "))
	_check(_mule.linear_velocity.length() < 0.5, "the ship is still at rest")

	print("An early jump")
	var bar_before_asking := presence.progress
	var asked := _director.request_jump()
	_check(asked, "asking for a jump works while in a system")
	_check(_director.phase == JumpDirector.Phase.CHARGING, "and the drive starts charging at once")
	_check(presence.progress - bar_before_asking < 0.001, "without the presence being moved")
	_check(not _director.request_jump(), "but a jump already under way cannot be asked for again")
	_warnings.clear()
	reached = await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 800)
	await _frames(2)
	_check(reached and _director.jump_count == 2 and _completed_jumps == [1, 2], "so it ends at jump 2 (%d)" % _director.jump_count)
	_check(_warnings == [3, 2, 1], "after the same countdown (%s)" % str(_warnings))
	_check(WorldSaves.read_slot(1)["jump_count"] == 2, "which is saved")
	_check(_director.system.system_seed == StarSystem.create(_director.world_seed, 2, _tuning).system_seed and _director.system.system_seed != second_seed, "with its own seed again")
	_check(presence.progress < bar_before_asking, "and the presence is further behind than it was (%.3f, from %.3f)" % [presence.progress, bar_before_asking])
	var arrival_two := _director.system.arrival_position
	var field_two := _far_field(streamer, arrival_two, Vector3.ZERO)
	var seed_world := _director.world_seed
	var seed_two := _director.system.system_seed
	var name_two := _director.system.system_name

	# Another few jumps, to see the field follow the difficulty.
	for _jump in 3:
		_director.request_jump()
		reached = await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 800)
		await _frames(3)
	_check(_director.jump_count == 5 and WorldSaves.read_slot(1)["jump_count"] == 5, "five jumps in all, saved (%d)" % _director.jump_count)
	_check(_director.system.difficulty > 0.15 and _director.system.asteroid_density / StarSystem.get_density_factor(_director.system.density, _tuning) > _tuning.easy_density, "and the system is harder than the first (difficulty %.2f)" % _director.system.difficulty)
	_check(crate_in != null and is_instance_valid(crate_in), "the crate inside the ship has been through every one of them")

	_tear_down_world()
	_remember = {"seed": seed_world, "system_seed": seed_two, "field": field_two, "name": name_two, "arrival": arrival_two}
	await _frames(3)


var _remember := {}


# --- A ship far from the origin -----------------------------------------------------------------------

func _jump_and_wait(count: int) -> bool:
	_director.request_jump()
	var frames := 0
	while (_director.jump_count != count or _director.phase != JumpDirector.Phase.IN_SYSTEM) and frames < 1500:
		await get_tree().process_frame
		frames += 1
	await _frames(40)
	return _director.jump_count == count and _director.phase == JumpDirector.Phase.IN_SYSTEM


func _test_recentering() -> void:
	print("A ship far from the origin")
	_recenter = 1000.0
	_build_world(0, false)
	await _frames(40)
	var crate := _make_crate(_mule.to_global(Vector3(0.8, 0.4, 2.0)))
	await _frames(20)
	var interior := JumpPurge.get_interiors(_mule)[0]
	_mule.global_transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(40000.0, 300.0, -25000.0))
	_mule.linear_velocity = Vector3.ZERO
	await _frames(30)
	_check(interior.contains_point(_player.global_position) and interior.contains_point(crate.global_position), "the player and the crate came along when the ship was moved out to %.0f km" % (_mule.global_position.length() / 1000.0))
	var player_local := _mule.to_local(_player.global_position)
	var crate_local := _mule.to_local(crate.global_position)
	var basis_before := _mule.global_basis
	# A turned ship at rest this far out: floats are only good to 4 mm here, and a carry that turned whole positions
	# about the world's origin slid everything in the ship by that much every tick (a quarter of a meter a second).
	await _frames(120)
	var slid := maxf(_mule.to_local(_player.global_position).distance_to(player_local), _mule.to_local(crate.global_position).distance_to(crate_local))
	_check(slid < 0.02, "nothing in a turned ship at rest slides, even this far out (%.1f cm in 2 s)" % (slid * 100.0))
	_check(await _jump_and_wait(1), "the ship jumps from there")
	_check(_mule.global_position.length() < 1.0, "and ends up back at the origin (%.2f m from it)" % _mule.global_position.length())
	_check(_director.system.arrival_position.length() < 1.0, "which is where the new system was built around")
	_check(_mule.global_basis.is_equal_approx(basis_before), "turned the way it was")
	_check(interior.contains_point(_player.global_position) and interior.contains_point(crate.global_position), "with the player and the crate still inside it")
	_check(_mule.to_local(_player.global_position).distance_to(player_local) < 0.1 and _mule.to_local(crate.global_position).distance_to(crate_local) < 0.1, "in the same places in it (player %.1f cm, crate %.1f cm off)" % [_mule.to_local(_player.global_position).distance_to(player_local) * 100.0, _mule.to_local(crate.global_position).distance_to(crate_local) * 100.0])
	_check(_player.is_on_floor() and _mule.linear_velocity.length() < 0.5, "the player stands on the floor and the ship is at rest")
	_check(_director.streamer.get_asteroid_count() > 100 and _director.streamer.get_focus_points().size() >= 1, "and the new field is built around it (%d asteroids)" % _director.streamer.get_asteroid_count())

	_mule.global_position = Vector3(600.0, 0.0, 0.0)
	await _frames(20)
	var stay := _mule.global_position
	_check(await _jump_and_wait(2), "a ship not far out jumps too")
	_check(_mule.global_position.distance_to(stay) < 1.0 and _director.system.arrival_position.distance_to(stay) < 1.0, "and is left where it is (%.0f m out)" % _mule.global_position.length())

	_director.recenter_distance = 0.0
	_mule.global_position = Vector3(90000.0, 0.0, 0.0)
	await _frames(20)
	var far := _mule.global_position
	_check(await _jump_and_wait(3), "with re-centering off, a ship 90 km out jumps")
	_check(_mule.global_position.distance_to(far) < 1.0, "and stays there")
	_tear_down_world()
	_recenter = 5000.0
	await _frames(3)


# --- Loading a saved world ----------------------------------------------------------------------------

func _test_loading_a_saved_world() -> void:
	print("Continuing a saved world")
	# The slot holds jump 5 from the session before. Put it back to jump 2, with the bar where it was then.
	WorldSaves.record_jump(1, 2, 0.37)
	_build_world(1, false)
	await _frames(4)
	_check(_director.jump_count == 2, "the world carries on from the jump it was at (%d)" % _director.jump_count)
	_check(_director.world_seed == _remember["seed"], "with the same world seed")
	_check(_director.system.system_seed == _remember["system_seed"] and _director.system.system_name == _remember["name"], "so it is the same system (%s)" % _director.system.system_name)
	var far_field := _far_field(_director.streamer, _remember["arrival"], Vector3.ZERO)
	_check(far_field.size() > 100 and far_field == _remember["field"], "and the same asteroids in the same places (%d of them well away from where the ship arrived, which is cleared of them)" % far_field.size())
	_check(_director.phase == JumpDirector.Phase.IN_SYSTEM and absf(_director.presence.progress - 0.37) < 0.01, "with the Cosmic Presence where the jump left it (%.3f)" % _director.presence.progress)
	_check(_director.get_node("JumpHud").jump_label.text == "2", "and the HUD shows jump 2")
	_tear_down_world()
	await _frames(3)

	print("A saved world from before the bar was saved")
	_tuning.starting_presence = 0.2
	WorldSaves.create_world(2, "Old")
	_check(is_equal_approx(WorldSaves.read_slot(2)["presence"], -1.0), "a world that never saved a bar says so")
	_build_world(2, false)
	await _frames(4)
	_check(absf(_director.presence.progress - 0.2) < 0.01, "so it starts where a new world does (%.3f)" % _director.presence.progress)
	_tear_down_world()
	_tuning.starting_presence = 0.0
	await _frames(3)

	print("A world that is not saved")
	_build_world(0, false)
	await _frames(4)
	_check(_director.jump_count == 0 and _director.world_seed == 424242, "without a slot it starts at jump 0 from the debug seed")
	_director.request_jump()
	var finished := await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 800)
	await _frames(3)
	_check(finished and _director.jump_count == 1, "and can still jump")
	_check(WorldSaves.read_slot(1)["jump_count"] == 2 and not WorldSaves.read_slot(3)["exists"], "without touching any save")
	_tear_down_world()
	await _frames(3)


# --- Arriving when the world starts ----------------------------------------------------------------------

func _test_arrival_at_start() -> void:
	print("The first arrival")
	WorldSaves.create_world(3, "Arrive")
	_build_world(3, true)
	await _frames(3)
	_check(_director.phase == JumpDirector.Phase.SWITCHING and is_equal_approx(_director.get_bubble().progress, 1.0), "a world begins inside the bubble, while its first system builds")
	_check(_director.is_first_arrival(), "which is the first arrival, not a jump")
	_check(is_zero_approx(_director.presence.progress), "the presence has not moved yet (%.4f)" % _director.presence.progress)
	var reached := await _wait_for_phase(JumpDirector.Phase.WARPING_IN, 200)
	_check(reached and _director.streamer.is_settled() and _director.streamer.get_asteroid_count() > 100, "the bubble waits for the asteroids (%d) before it burns away" % _director.streamer.get_asteroid_count())
	reached = await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 200)
	_check(reached and _completed_jumps == [0] and _director.jump_count == 0, "and the ship has arrived at jump 0")
	await _frames(30)
	_check(_director.presence.progress > 0.0 and _director.presence.progress < 0.05, "and the presence starts to close in (%.4f)" % _director.presence.progress)
	_check(WorldSaves.read_slot(3)["jump_count"] == 0 and is_equal_approx(WorldSaves.read_slot(3)["presence"], -1.0), "nothing changed in the save")
	_check(not _director.is_first_arrival(), "and it is no longer the first arrival")
	# The first real jump after that must do everything a jump does (it once did nothing but run the effect).
	var first_seed := _director.system.system_seed
	_director.request_jump()
	reached = await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 800)
	await _frames(3)
	_check(reached and _director.jump_count == 1 and _director.system.system_seed != first_seed, "the first jump after arriving goes to jump 1 in a new system")
	_check(WorldSaves.read_slot(3)["jump_count"] == 1 and WorldSaves.read_slot(3)["presence"] >= 0.0, "and is saved")
	_check(_director.presence.progress < 0.02, "with the bar all but empty: a jump took off more than there was (%.4f)" % _director.presence.progress)
	_check(_reliefs.size() == 1 and _reliefs[0] < _tuning.jump_relief, "so the relief reported is only what was there (%.3f of %.2f)" % [_reliefs[0] if not _reliefs.is_empty() else -1.0, _tuning.jump_relief])
	_tear_down_world()
	await _frames(3)


# --- The kind of system, its temperature and its own scene -------------------------------------------------------

func _test_the_kind_of_system() -> void:
	print("The kind of system")
	var handler := TemperatureHandler.new()
	add_child(handler)
	var stand_in := Node3D.new()
	stand_in.name = "BlackHole"
	stand_in.set_script(load("res://Components/Jump/Testing/special_scene_probe.gd"))
	var scene := PackedScene.new()
	scene.pack(stand_in)
	stand_in.free()
	var template := Kit.flat_template(70.0, 0.5, 2)
	template.display_name = "Test Furnace"
	template.scene = scene
	_debug_template = template
	_build_world(0, false)
	await _frames(6)
	var hud := _director.get_node("JumpHud") as JumpHud
	_check(_director.system.template == template and is_equal_approx(_director.system.temperature, 70.0), "a director with a debug template makes every system that kind, the first included")
	_check(is_equal_approx(handler.get_system_temperature(), 70.0) and handler.get_system_word() == "Hot", "and tells the temperature handler how hot it is (%s)" % handler.get_system_word())
	_check(hud.climate_label.text == "HOT · 90°C · TEST FURNACE", "the HUD says how hot, in degrees, and what kind (%s)" % hud.climate_label.text)
	var special := _director.get_special_scene()
	_check(special != null and special.get_script() != null and special.get_parent() == _director and special.is_inside_tree(), "the template's own scene is in the world")
	_check(special != null and special.get("system_seen") == _director.system and special.get("setup_calls") == 1 and not special.get("in_tree_during_setup"), "and was told which system it is for, before it entered the tree")
	_check(special != null and (special as Node3D).global_position.is_equal_approx(Vector3(0.0, 0.0, -1500.0)), "so it could place itself")
	var first_special := special
	var ok := await _jump_and_wait(1)
	_check(ok and _director.system.template == template, "a jump makes another system of the kind")
	var second_special := _director.get_special_scene()
	_check(not is_instance_valid(first_special) and second_special != null and second_special != first_special and second_special.get("system_seen") == _director.system and _director.system.jump_count == 1, "and the old system's scene is freed and a new one made for the new system")
	_tear_down_world()
	await _frames(3)
	_check(not is_instance_valid(second_special), "the scene goes with the director")

	_debug_template = null
	var plain := Kit.flat_template(-90.0, 0.5, 1)
	plain.display_name = "Cold Place"
	_debug_template = plain
	_build_world(0, false)
	await _frames(6)
	_check(_director.get_special_scene() == null and handler.get_system_word() == "Frozen", "a template with no scene of its own brings none, and the handler follows the cold")
	_check(hud_text(_director) == "FROZEN · -70°C · COLD PLACE", "(%s)" % hud_text(_director))
	_debug_template = null
	var changes := 0
	var follows := true
	for count in range(1, 4):
		_director.debug_template = null
		var jumped := await _jump_and_wait(count)
		follows = follows and jumped and is_equal_approx(handler.get_system_temperature(), _director.system.temperature)
		changes += 1
	_check(follows and changes == 3, "and with no debug template the handler follows each system the ship jumps to")
	_tear_down_world()
	handler.free()
	await _frames(3)


func hud_text(director: JumpDirector) -> String:
	return (director.get_node("JumpHud") as JumpHud).climate_label.text


# --- Things that change the presence's speed -----------------------------------------------------------------

func _test_presence_in_the_loop() -> void:
	print("What draws the presence on")
	_build_world(0, false, 100.0)
	await _frames(4)
	var presence := _director.presence
	var hud := _director.get_node("JumpHud") as JumpHud
	var rate := presence.get_rate()
	_check(is_equal_approx(rate, 0.01), "a system that gives 100 seconds has the presence at a hundredth a second (%.4f)" % rate)
	var signalled: Array[float] = []
	presence.speed_changed.connect(func(multiplier: float) -> void: signalled.append(multiplier))
	presence.add_speed_modifier("mining", 100.0)
	await _frames(2)
	_check(is_equal_approx(presence.get_speed_multiplier(), 2.0) and signalled == [2.0], "doing something that draws it on makes it twice as fast, and says so (%s)" % str(signalled))
	_check(hud.multiplier_label.text == "x2", "and the HUD shows x2 (%s)" % hud.multiplier_label.text)
	var before := presence.progress
	await _frames(60)
	_check(absf((presence.progress - before) - 0.02) < 0.002, "it covers two hundredths of the bar in a second (%.4f)" % (presence.progress - before))
	presence.add_speed_modifier("noise", 50.0)
	_check(is_equal_approx(presence.get_speed_multiplier(), 2.5), "and a second thing adds to the first (x%.1f)" % presence.get_speed_multiplier())
	await _frames(2)
	_check(hud.multiplier_label.text == "x2.5", "which the HUD shows (%s)" % hud.multiplier_label.text)
	presence.remove_speed_modifier("mining")
	presence.remove_speed_modifier("noise")
	await _frames(2)
	_check(is_equal_approx(presence.get_speed_multiplier(), 1.0) and hud.multiplier_label.text == "x1", "and stopping puts it back (%s)" % hud.multiplier_label.text)

	print("A full bar")
	_director.set_presence(0.8)
	presence.progress = 0.8
	_check(presence.aggression > 0.7, "a nearly full bar is very aggressive (%.2f)" % presence.aggression)
	_director.set_presence(0.1)
	await _frames(2)
	_check(presence.aggression == 0.0, "and one that is nearly empty is not (%.2f)" % presence.aggression)
	_tear_down_world()
	await _frames(3)


# --- Pausing, the debug keys ---------------------------------------------------------------------------------

func _test_pausing_and_debug_keys() -> void:
	print("Pausing")
	_build_world(0, false)
	await _frames(4)
	_director.set_presence(0.5)
	get_tree().paused = true
	await _frames(60)
	_check(is_equal_approx(_director.presence.progress, 0.5), "the presence does not move while the game is paused (%.4f)" % _director.presence.progress)
	get_tree().paused = false
	await _frames(30)
	_check(_director.presence.progress > 0.52, "and moves again after (%.4f)" % _director.presence.progress)

	print("The debug keys")
	var jump_key := InputEventKey.new()
	jump_key.keycode = JumpDirector.DEBUG_JUMP_KEY
	jump_key.pressed = true
	var presence_key := InputEventKey.new()
	presence_key.keycode = JumpDirector.DEBUG_PRESENCE_KEY
	presence_key.pressed = true
	_director.debug_keys = false
	_director._unhandled_key_input(jump_key)
	_director._unhandled_key_input(presence_key)
	await _frames(2)
	_check(_director.phase == JumpDirector.Phase.IN_SYSTEM and is_equal_approx(_director.presence.get_speed_multiplier(), 1.0), "with debug keys off, J and K do nothing")
	_director.debug_keys = true
	_director._unhandled_key_input(presence_key)
	_check(is_equal_approx(_director.presence.get_speed_multiplier(), 2.0), "with them on, K doubles the presence's speed")
	_director._unhandled_key_input(presence_key)
	_check(is_equal_approx(_director.presence.get_speed_multiplier(), 1.0), "and K again puts it back")
	_director._unhandled_key_input(jump_key)
	await _frames(2)
	_check(_director.phase == JumpDirector.Phase.CHARGING, "and J starts the jump")
	_tear_down_world()
	await _frames(3)


func _test_without_a_ship() -> void:
	print("A world with no ship")
	_world = Node3D.new()
	_world.add_to_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP)
	add_child(_world)
	var lonely := DIRECTOR_SCENE.instantiate() as JumpDirector
	_world.add_child(lonely)
	await _frames(5)
	_check(not lonely.can_jump() and not lonely.request_jump() and lonely.system == null, "a director with no ship does nothing, and says so, instead of failing")
	_world.free()
	_world = null
	await _frames(2)


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(dir_name))
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
