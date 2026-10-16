extends Node
## What a jump feels like to someone aboard: the view slowly zooms in while the drive charges and springs back when
## the jump begins, and the ship hums for whoever is inside it.
##
## godot --headless --fixed-fps 60 --path . res://Components/Jump/Testing/JumpFeelTest.tscn

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const DIRECTOR_SCENE := preload("res://Components/Jump/JumpDirector.tscn")

var _failures := 0
var _world: Node3D
var _mule: Mule
var _player: Player
var _director: JumpDirector


func _ready() -> void:
	await _run()


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InGameUIHandler.is_ui_open = false
	WorldSaves.active_slot = 0
	await _test_camera_multipliers()
	await _build_world()
	await _test_zoom_while_charging()
	await _test_other_cameras()
	await _test_ambience()
	_world.free()
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Jump feel tests passed.")
	else:
		print("Jump feel tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- The camera -------------------------------------------------------------------------------------------

func _test_camera_multipliers() -> void:
	print("Zooming a camera")
	var camera := BaseCamera3D.new()
	add_child(camera)
	var base := camera.get_base_field_of_view()
	_check(is_equal_approx(camera.fov, base) and base >= 60.0 and base <= 110.0, "a camera starts at the field of view the player chose (%.0f)" % base)
	camera.set_field_of_view_multiplier(&"a", 0.8)
	_check(is_equal_approx(camera.fov, base * 0.8), "an effect narrows it (%.1f)" % camera.fov)
	camera.set_field_of_view_multiplier(&"b", 0.9)
	_check(is_equal_approx(camera.fov, base * 0.72) and is_equal_approx(camera.get_field_of_view_multiplier(&"a"), 0.8), "two effects both count (%.1f)" % camera.fov)
	camera.set_field_of_view_multiplier(&"a", 1.0)
	_check(is_equal_approx(camera.fov, base * 0.9) and is_equal_approx(camera.get_field_of_view_multiplier(&"a"), 1.0), "and one can be taken away without the other")
	camera.set_field_of_view_multiplier(&"a", 0.8)
	Settings.setting_changed.emit(BaseCamera3D.FIELD_OF_VIEW_SETTING, 100.0)
	_check(is_equal_approx(camera.get_base_field_of_view(), 100.0) and is_equal_approx(camera.fov, 100.0 * 0.8 * 0.9), "changing the setting while they run keeps them running (%.1f)" % camera.fov)
	camera.set_field_of_view_multiplier(&"b", 0.01)
	_check(camera.fov >= BaseCamera3D.MINIMUM_FIELD_OF_VIEW - 0.001, "the view never closes to nothing (%.1f)" % camera.fov)
	camera.set_field_of_view_multiplier(&"b", 5.0)
	camera.set_field_of_view_multiplier(&"a", 5.0)
	_check(camera.fov <= BaseCamera3D.MAXIMUM_FIELD_OF_VIEW + 0.001, "or opens past the widest (%.1f)" % camera.fov)
	camera.free()


# --- The jump ----------------------------------------------------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	_world.add_to_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP)
	add_child(_world)
	_mule = MULE_SCENE.instantiate() as Mule
	_world.add_child(_mule)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector3(0.0, 0.1, 1.5)
	_world.add_child(_player)
	_director = DIRECTOR_SCENE.instantiate() as JumpDirector
	_director.ship = _mule
	_director.debug_fill_time = 600.0
	_director.charge_time = 4.0
	_director.warp_out_time = 1.5
	_director.minimum_hold_time = 0.3
	_director.warp_in_time = 0.6
	_director.arrive_at_start = false
	_director.debug_seed = 99
	_world.add_child(_director)
	await _frames(5)


func _player_camera() -> BaseCamera3D:
	return _player.find_children("*", "BaseCamera3D", true, false)[0] as BaseCamera3D


func _test_zoom_while_charging() -> void:
	print("Zooming in while the drive charges")
	var effect := _director.get_node("CameraEffect") as JumpCameraEffect
	_check(effect != null and effect.director == _director, "the director has a camera effect")
	var camera := _player_camera()
	camera.make_current()
	await _frames(15)
	var base := camera.get_base_field_of_view()
	_check(is_equal_approx(camera.fov, base) and is_equal_approx(effect.get_multiplier(), 1.0), "in the system the view is as it should be (%.1f)" % camera.fov)
	_check(VehicleAboard.is_viewer_aboard(camera, _mule, VehicleAboard.get_interiors(_mule)), "and the player's camera is aboard the ship")

	_director.request_jump()
	var samples: Array[float] = []
	for second in 4:
		await _frames(30 if second == 0 else 60)
		samples.append(camera.fov / base)
	print("  info the view while charging, as a share of normal: %s" % str(samples.map(func(value: float) -> String: return "%.3f" % value)))
	_check(samples[0] > 0.97, "it starts the charge unchanged (%.3f)" % samples[0])
	_check(samples[1] < samples[0] and samples[2] < samples[1] and samples[3] < samples[2], "and narrows more every second")
	_check(samples[3] < 0.85 and samples[3] > 0.7, "ending a good deal narrower, but nowhere near a tunnel (%.3f)" % samples[3])
	var slow_start := samples[0] - samples[1]
	var fast_end := samples[2] - samples[3]
	_check(fast_end > slow_start, "slowly at first and faster as the jump gets near (%.3f, then %.3f a second)" % [slow_start, fast_end])
	_check(effect.get_multiplier() < 1.0 and is_equal_approx(camera.get_field_of_view_multiplier(JumpCameraEffect.SOURCE), effect.get_multiplier()), "the zoom is the effect's, on the camera")

	var reached := false
	var frames := 0
	while _director.phase != JumpDirector.Phase.WARPING_OUT and frames < 400:
		await get_tree().process_frame
		frames += 1
	reached = _director.phase == JumpDirector.Phase.WARPING_OUT
	_check(reached, "then the jump begins")
	var peak := camera.fov / base
	await _frames(6)
	var quarter := camera.fov / base
	await _frames(30)
	var half_second := camera.fov / base
	_check(quarter > peak + 0.05, "and the view lets go at once (%.3f, then %.3f a tenth of a second later)" % [peak, quarter])
	_check(half_second > 0.98 and half_second < 1.02, "and is back to normal within half a second (%.3f)" % half_second)
	_check(camera.get_field_of_view_multiplier(JumpCameraEffect.SOURCE) > 0.97, "with the effect gone from the camera")
	reached = await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 800)
	await _frames(20)
	_check(reached and is_equal_approx(camera.fov, base), "and stays normal through the jump and after it (%.2f against %.2f)" % [camera.fov, base])


func _test_other_cameras() -> void:
	print("Who feels it")
	var effect := _director.get_node("CameraEffect") as JumpCameraEffect
	# A camera outside the ship, a long way off: someone watching.
	var watcher := BaseCamera3D.new()
	_world.add_child(watcher)
	watcher.global_position = Vector3(400.0, 20.0, 60.0)
	watcher.make_current()
	await _frames(15)
	_director.request_jump()
	await _frames(150)
	_check(_director.phase == JumpDirector.Phase.CHARGING, "the drive is charging")
	_check(is_equal_approx(watcher.fov, watcher.get_base_field_of_view()) and is_equal_approx(effect.get_target(), 1.0), "someone outside, watching, sees a normal view (%.2f)" % watcher.fov)
	# Now they come aboard, in the middle of the charge.
	watcher.global_position = _mule.to_global(Vector3(0.0, 1.8, 0.0))
	await _frames(40)
	_check(watcher.fov < watcher.get_base_field_of_view() - 0.5, "and once aboard the view zooms (%.1f of %.1f)" % [watcher.fov, watcher.get_base_field_of_view()])
	# They switch to the player's camera: the watcher goes back to normal.
	var camera := _player_camera()
	camera.make_current()
	await _frames(5)
	_check(is_equal_approx(watcher.get_field_of_view_multiplier(JumpCameraEffect.SOURCE), 1.0) and is_equal_approx(watcher.fov, watcher.get_base_field_of_view()), "the camera they are no longer looking through is put right")
	_check(camera.get_field_of_view_multiplier(JumpCameraEffect.SOURCE) < 1.0, "and the one they are looking through carries the zoom")
	var reached := await _wait_for_phase(JumpDirector.Phase.IN_SYSTEM, 800)
	await _frames(30)
	_check(reached and is_equal_approx(camera.fov, camera.get_base_field_of_view()), "all back to normal at the end")
	# The ship's own camera, riding on it.
	var rig_camera := _mule.camera_rig.camera as BaseCamera3D
	_check(rig_camera != null and VehicleAboard.is_viewer_aboard(rig_camera, _mule, VehicleAboard.get_interiors(_mule)), "the pilot's camera, which is part of the ship, counts as aboard")
	watcher.free()


# --- The hum -----------------------------------------------------------------------------------------------

func _test_ambience() -> void:
	print("The ship's hum")
	var ambience := _mule.get_node_or_null("InteriorAmbience") as VehicleAmbience
	# Whatever the player has set for ambient volume, the test starts from full.
	Settings.setting_changed.emit(VehicleAmbience.AMBIENT_VOLUME_SETTING, 100)
	_check(ambience != null, "the Mule has an interior ambience")
	if ambience == null:
		return
	var stream := ambience.stream as AudioStreamWAV
	_check(stream != null and stream.resource_path.ends_with("main_ship_interior_loop.wav"), "playing the ship's loop")
	var player := ambience.get_player()
	var played := player.stream as AudioStreamWAV
	_check(played != null and played.loop_mode != AudioStreamWAV.LOOP_DISABLED, "set to repeat")

	# Someone outside: silence.
	var outside := BaseCamera3D.new()
	_world.add_child(outside)
	outside.global_position = Vector3(300.0, 10.0, 0.0)
	outside.make_current()
	await _frames(120)
	_check(not ambience.is_listener_aboard() and ambience.get_gain() == 0.0 and not ambience.is_audible() and player.stream_paused, "outside the ship it is silent")
	# They step aboard.
	outside.global_position = _mule.to_global(Vector3(0.0, 1.8, 0.0))
	await _frames(20)
	_check(ambience.is_listener_aboard() and ambience.get_gain() > 0.0 and ambience.get_gain() < 1.0, "coming aboard it starts to fade in (%.2f)" % ambience.get_gain())
	_check(ambience.is_audible() and not player.stream_paused and player.playing, "and plays")
	await _frames(100)
	_check(is_equal_approx(ambience.get_gain(), 1.0), "reaching full volume after the fade (%.2f)" % ambience.get_gain())
	_check(is_equal_approx(player.volume_db, ambience.volume_db), "at the volume it was given (%.1f dB)" % player.volume_db)
	# And off again.
	outside.global_position = Vector3(300.0, 10.0, 0.0)
	await _frames(25)
	_check(ambience.get_gain() < 1.0 and ambience.get_gain() > 0.0 and player.volume_db < ambience.volume_db, "leaving, it fades out (%.2f)" % ambience.get_gain())
	await _frames(60)
	_check(ambience.get_gain() == 0.0 and player.stream_paused, "to nothing, and stops mixing")

	print("Ambient volume setting")
	outside.global_position = _mule.to_global(Vector3(0.0, 1.8, 0.0))
	await _frames(150)
	var full := player.volume_db
	Settings.setting_changed.emit(VehicleAmbience.AMBIENT_VOLUME_SETTING, 50)
	_check(absf((player.volume_db - full) - linear_to_db(0.5)) < 0.01, "half the Ambient Volume is 6 dB quieter (%.1f dB)" % (player.volume_db - full))
	Settings.setting_changed.emit(VehicleAmbience.AMBIENT_VOLUME_SETTING, 0)
	_check(not ambience.is_audible() and player.stream_paused, "and none is silent")
	Settings.setting_changed.emit(VehicleAmbience.AMBIENT_VOLUME_SETTING, 100)
	_check(ambience.is_audible() and is_equal_approx(player.volume_db, full), "and back to full")

	print("Looping")
	# Play the last moments of the sound and carry on for a while: it must still be playing after the end.
	var length := played.get_length()
	player.seek(length - 0.25)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 900:
		await get_tree().process_frame
	_check(player.playing and player.get_playback_position() < length - 0.3, "past the end of the sound it goes round again (at %.2f of %.2f s)" % [player.get_playback_position(), length])
	outside.free()


func _wait_for_phase(phase: JumpDirector.Phase, max_frames: int) -> bool:
	var frames := 0
	while _director.phase != phase and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	return _director.phase == phase


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
