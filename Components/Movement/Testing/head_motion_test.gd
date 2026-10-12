extends Node
## Headless checks for HeadMotion, HeadBobProfile and FootstepPlayer on real physics.
##
## godot --headless --fixed-fps 60 --path . res://Components/Movement/Testing/HeadMotionTest.tscn

const WALK := preload("res://Components/Movement/Character/HeadMotion/Profiles/WalkBob.tres")
const SPRINT := preload("res://Components/Movement/Character/HeadMotion/Profiles/SprintBob.tres")
const STROLL := preload("res://Components/Movement/Character/HeadMotion/Profiles/StrollBob.tres")
const CROUCH := preload("res://Components/Movement/Character/HeadMotion/Profiles/CrouchBob.tres")
const LIMP := preload("res://Components/Movement/Character/HeadMotion/Profiles/LimpBob.tres")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const CHARACTER_SOUND := preload("res://Assets/Audio/Footsteps/Characters/footstep00.ogg")

var physics_frame: Signal
var _world: Node3D
var _failures := 0


class Walker extends CharacterController:
	var move := Vector2.ZERO
	var yaw := 0.0
	var sprint := false
	var stroll := false
	var crouch := false
	var jump_once := false

	func poll_intent(_delta: float) -> MoveIntent:
		var intent := MoveIntent.new()
		intent.move = move
		intent.yaw = yaw
		intent.sprint = sprint
		intent.stroll = stroll
		intent.crouch = crouch
		intent.jump_pressed = jump_once
		jump_once = false
		return intent


## Runs after HeadMotion each frame, so it sees the camera as HeadMotion left it.
class Recorder extends Node:
	var camera: Camera3D
	var walker: Walker
	var heights: Array[float] = []
	var grounded: Array[bool] = []

	func _process(_delta: float) -> void:
		heights.append(camera.position.y)
		grounded.append(walker.is_grounded())


class Rig:
	var body: CharacterBody3D
	var walker: Walker
	var yaw_pivot: Node3D
	var camera: Camera3D
	var motion: HeadMotion
	var recorder: Recorder
	var steps: Array[Dictionary] = []


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in [
		"profile_sampling", "tilt_directions", "tilt_follows_the_view", "tilt_limits_and_speed",
		"bob_and_footstep_sync", "gait_profiles", "airborne_and_idle", "limp_override",
		"jump_tilt", "landing_impact", "first_step_is_immediate", "landing_step", "quiet_steps",
		"footstep_player", "player_scene",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Head motion tests passed.")
	else:
		print("Head motion tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_profile_sampling() -> void:
	var at_left := WALK.sample(0.0)
	var between := WALK.sample(0.25)
	var at_right := WALK.sample(0.5)
	_check(is_equal_approx(at_left.offset.y, -WALK.vertical), "the head is lowest as a foot lands (%.4f)" % at_left.offset.y)
	_check(is_equal_approx(between.offset.y, WALK.vertical), "and highest between steps (%.4f)" % between.offset.y)
	_check(is_equal_approx(at_right.offset.y, -WALK.vertical), "lowest again for the other foot")
	_check(at_left.rotation.x < 0.0, "the view nods down as a foot lands")
	_check(WALK.sample(0.0).offset.is_equal_approx(WALK.sample(0.99999).offset), "the cycle joins up with itself")
	_check(WALK.sample(0.25).offset.x < -0.02, "the head sways toward the left foot after it lands (%.4f)" % WALK.sample(0.25).offset.x)
	_check(WALK.sample(0.75).offset.x > 0.02, "and toward the right foot after that")
	_check(WALK.sample(0.25).rotation.z > 0.0 and WALK.sample(0.75).rotation.z < 0.0, "rolling with the sway")

	_check(is_equal_approx(LIMP.sample(0.0).offset.y, -LIMP.vertical), "a limp lands hard on the bad leg")
	_check(is_equal_approx(LIMP.sample(0.62).offset.y, -LIMP.vertical * 0.45), "and lightly on the good one (%.4f)" % LIMP.sample(0.62).offset.y)

	var unsorted := HeadBobProfile.new()
	unsorted.footfalls = [Footfall.create(0.5, 1.0, 1.0), Footfall.create(0.0, 1.0, -1.0)]
	_check(unsorted.get_footfalls()[0].phase == 0.0, "footfalls may be listed in any order")
	var four_legs := HeadBobProfile.new()
	four_legs.footfalls = [Footfall.create(0.0), Footfall.create(0.25), Footfall.create(0.5), Footfall.create(0.75)]
	_check(is_equal_approx(four_legs.sample(0.5).offset.y, -four_legs.vertical), "any number of feet works")
	_check(is_equal_approx(four_legs.sample(0.375).offset.y, four_legs.vertical), "four feet make four dips per cycle")

	var custom := HeadBobProfile.new()
	custom.vertical_curve = Curve.new()
	custom.vertical_curve.add_point(Vector2(0.0, 0.5))
	custom.vertical_curve.add_point(Vector2(1.0, 0.5))
	_check(is_equal_approx(custom.sample(0.0).offset.y, 0.5 * custom.vertical), "a custom curve replaces the built-in motion (%.4f)" % custom.sample(0.0).offset.y)
	_check(is_equal_approx(custom.sample(0.0).offset.x, 0.0), "for its own channel only")
	await physics_frame


func _test_tilt_directions() -> void:
	_begin_world()
	var rig := _make_rig()
	rig.motion.bob_enabled = false
	await _ticks(30)
	var max_roll := rig.motion.max_roll_degrees

	rig.walker.move = Vector2(1.0, 0.0)
	await _ticks(60)
	var right_roll := rad_to_deg(rig.camera.rotation.z)
	_check(right_roll < -1.0, "moving right leans the camera right (%.2f degrees)" % right_roll)
	_check(absf(rad_to_deg(rig.camera.rotation.x)) < 0.1, "without nodding (%.2f)" % rad_to_deg(rig.camera.rotation.x))

	rig.walker.move = Vector2(-1.0, 0.0)
	await _ticks(60)
	var left_roll := rad_to_deg(rig.camera.rotation.z)
	_check(left_roll > 1.0, "moving left leans it left (%.2f degrees)" % left_roll)

	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(60)
	var forward_pitch := rad_to_deg(rig.camera.rotation.x)
	_check(forward_pitch < -0.2 and forward_pitch >= -rig.motion.max_forward_pitch_degrees - 0.01, "moving forward tips the view down, very slightly (%.2f degrees)" % forward_pitch)
	_check(absf(rad_to_deg(rig.camera.rotation.z)) < 0.1, "without rolling (%.2f)" % rad_to_deg(rig.camera.rotation.z))

	rig.walker.move = Vector2(0.0, 1.0)
	await _ticks(60)
	var back_pitch := rad_to_deg(rig.camera.rotation.x)
	_check(back_pitch > 0.15 and back_pitch <= rig.motion.max_backward_pitch_degrees + 0.01, "moving back tips it up, very slightly (%.2f degrees)" % back_pitch)

	rig.walker.move = Vector2.ZERO
	await _ticks(90)
	_check(absf(rad_to_deg(rig.camera.rotation.z)) < 0.05 and absf(rad_to_deg(rig.camera.rotation.x)) < 0.05, "standing still levels the camera again")
	_check(max_roll > 0.0, "tilt has a limit to speak of")
	_end_world()


## Left, right and forward are the way the player looks, not the way the body faces.
func _test_tilt_follows_the_view() -> void:
	_begin_world()
	var rig := _make_rig()
	rig.motion.bob_enabled = false
	await _ticks(30)
	# Look 90 degrees to the left and steer along that heading.
	rig.yaw_pivot.rotation.y = PI / 2.0
	rig.walker.yaw = PI / 2.0
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(60)
	_check(rig.body.velocity.x < -4.0, "walking forward along the view (%s)" % rig.body.velocity)
	_check(rad_to_deg(rig.camera.rotation.x) < -0.2, "is still forward, so the view tips down (%.2f)" % rad_to_deg(rig.camera.rotation.x))
	_check(absf(rad_to_deg(rig.camera.rotation.z)) < 0.2, "and does not roll (%.2f)" % rad_to_deg(rig.camera.rotation.z))
	rig.walker.move = Vector2(1.0, 0.0)
	await _ticks(60)
	_check(rad_to_deg(rig.camera.rotation.z) < -1.0, "strafing right of the view leans right (%.2f)" % rad_to_deg(rig.camera.rotation.z))

	# Looking steeply up or down changes nothing about what is left and right.
	rig.camera.get_parent_node_3d().rotation.x = deg_to_rad(80.0)
	await _ticks(30)
	_check(rad_to_deg(rig.camera.rotation.z) < -1.0, "even when looking almost straight up (%.2f)" % rad_to_deg(rig.camera.rotation.z))
	_end_world()


func _test_tilt_limits_and_speed() -> void:
	_begin_world()
	var rig := _make_rig()
	rig.motion.bob_enabled = false
	await _ticks(30)
	rig.walker.move = Vector2(1.0, 0.0)
	await _ticks(60)
	var walking := absf(rad_to_deg(rig.camera.rotation.z))
	_check(walking > 1.5 and walking < rig.motion.max_roll_degrees, "walking sideways leans part of the way (%.2f of %.1f)" % [walking, rig.motion.max_roll_degrees])

	rig.walker.sprint = true
	await _ticks(60)
	var sprinting := absf(rad_to_deg(rig.camera.rotation.z))
	_check(sprinting > walking + 0.3, "going faster leans more (%.2f > %.2f)" % [sprinting, walking])
	_check(sprinting <= rig.motion.max_roll_degrees + 0.01, "but never past the maximum (%.2f)" % sprinting)

	rig.walker.sprint = false
	rig.motion.full_tilt_speed = 3.0
	await _ticks(90)
	var absurd := absf(rad_to_deg(rig.camera.rotation.z))
	_check(absurd <= rig.motion.max_roll_degrees + 0.01, "past the full-tilt speed (%.1f m/s) the lean stops at the maximum (%.2f)" % [rig.body.velocity.length(), absurd])
	_check(absurd > rig.motion.max_roll_degrees - 0.05, "and does reach it")

	rig.motion.tilt_strength = 0.0
	await _ticks(30)
	_check(absf(rad_to_deg(rig.camera.rotation.z)) < 0.001, "a tilt strength of zero switches it off")
	_end_world()

	# Drifting through zero gravity has nothing to lean into.
	_begin_world(false)
	rig = _make_rig(Vector3(1000.0, 10.0, 0.0))
	rig.motion.bob_enabled = false
	rig.body.velocity = Vector3(3.0, 0.0, 0.0)
	await _ticks(60)
	_check(absf(rad_to_deg(rig.camera.rotation.z)) < 0.01, "no lean while floating in zero gravity (%.3f)" % rad_to_deg(rig.camera.rotation.z))
	_end_world()


func _test_bob_and_footstep_sync() -> void:
	_begin_world()
	var rig := _make_rig()
	await _ticks(60)
	_check(rig.steps.is_empty(), "no steps while standing")
	_check(rig.camera.position.length() < 0.0001, "and the camera sits at rest")

	var start := rig.body.global_position
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(240)
	var distance := start.distance_to(rig.body.global_position)
	var expected := distance / (WALK.distance_per_cycle / 2.0) + 1.0
	_check(absf(float(rig.steps.size()) - expected) <= 1.5, "a step to start with, then one every half cycle of walking: %d steps over %.1f m (about %.1f)" % [rig.steps.size(), distance, expected])

	var lowest := true
	var worst := -INF
	var highest := -INF
	for step in rig.steps.slice(1):
		var height: float = rig.recorder.heights[step["frame"]]
		worst = maxf(worst, height)
		if height > -WALK.vertical * 0.85:
			lowest = false
	for height in rig.recorder.heights.slice(rig.recorder.heights.size() - 100):
		highest = maxf(highest, height)
	_check(lowest, "the head is at the bottom of its dip on every step (shallowest %.4f of %.4f)" % [worst, -WALK.vertical])
	_check(highest > WALK.vertical * 0.85, "and rises between them (%.4f)" % highest)
	var strengths_ok := true
	for step in rig.steps.slice(2):
		if absf(step["strength"] - 1.0) > 0.1:
			strengths_ok = false
	_check(strengths_ok, "steps at walking speed are full strength")

	rig.walker.move = Vector2.ZERO
	var steps_before := rig.steps.size()
	await _ticks(90)
	_check(rig.steps.size() == steps_before, "stopping stops the steps")
	_check(rig.camera.position.length() < 0.001, "and the bob settles back to rest (%.5f)" % rig.camera.position.length())
	_end_world()


func _test_gait_profiles() -> void:
	_begin_world()
	var rig := _make_rig()
	await _ticks(30)
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(45)
	_check(rig.motion.get_active_profile() == WALK, "walking uses the walk profile")

	rig.steps.clear()
	var start := rig.body.global_position
	await _ticks(120)
	var walk_steps_per_second := float(rig.steps.size()) / 2.0

	rig.walker.sprint = true
	await _ticks(45)
	_check(rig.motion.get_active_profile() == SPRINT, "sprinting switches to the sprint profile")
	rig.steps.clear()
	start = rig.body.global_position
	await _ticks(120)
	var sprint_steps_per_second := float(rig.steps.size()) / 2.0
	_check(sprint_steps_per_second > walk_steps_per_second * 1.1, "a sprint still steps faster (%.2f steps a second against %.2f)" % [sprint_steps_per_second, walk_steps_per_second])
	_check(rig.motion.get_bob_intensity() > 1.3, "and bobs harder (%.2f)" % rig.motion.get_bob_intensity())
	var quick_steps := 0
	for step in rig.steps:
		if step["strength"] > 1.3:
			quick_steps += 1
	_check(quick_steps > rig.steps.size() / 2, "and steps heavier")

	rig.walker.sprint = false
	await _ticks(45)
	_check(rig.motion.get_active_profile() == WALK, "dropping back to a walk returns to the walk profile")

	rig.walker.stroll = true
	await _ticks(60)
	_check(rig.motion.get_active_profile() == STROLL, "strolling uses the stroll profile")
	rig.walker.stroll = false
	await _ticks(45)

	rig.walker.crouch = true
	await _ticks(45)
	_check(rig.motion.get_active_profile() == CROUCH, "crouching uses the crouch profile")
	rig.walker.crouch = false
	await _ticks(60)
	_check(rig.motion.get_active_profile() == WALK, "and standing up goes back")
	_end_world()


func _test_airborne_and_idle() -> void:
	_begin_world()
	var rig := _make_rig()
	await _ticks(30)
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(60)
	rig.steps.clear()
	rig.walker.jump_once = true
	var airborne_frames := 0
	var stepped_in_air := 0
	var before := rig.steps.size()
	for tick in 90:
		await physics_frame
		if not rig.walker.is_grounded():
			airborne_frames += 1
	for step in rig.steps:
		if not rig.recorder.grounded[step["frame"]]:
			stepped_in_air += 1
	_check(airborne_frames > 20, "the character really was in the air for a while (%d frames)" % airborne_frames)
	_check(stepped_in_air == 0, "no footsteps while off the ground (%d)" % stepped_in_air)
	_check(rig.steps.size() > before, "and steps carry on after landing (%d)" % rig.steps.size())

	# Locked in place, like on a ladder or in a seat: no steps, no bob.
	rig.walker.movement_blocker.add(99, "test")
	await _ticks(30)
	rig.steps.clear()
	await _ticks(60)
	_check(rig.steps.is_empty(), "a locked character makes no steps")
	rig.walker.movement_blocker.remove(99)
	_end_world()


func _test_limp_override() -> void:
	_begin_world()
	var rig := _make_rig()
	await _ticks(30)
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(60)
	rig.motion.push_profile_override(&"broken_leg", LIMP, 10)
	await _ticks(60)
	_check(rig.motion.get_active_profile() == LIMP, "an override takes over the bobbing")
	rig.walker.sprint = true
	await _ticks(60)
	_check(rig.motion.get_active_profile() == LIMP, "whatever the character is doing")
	rig.walker.sprint = false
	await _ticks(60)

	rig.steps.clear()
	await _ticks(300)
	_check(rig.steps.size() >= 8, "a limping character still steps (%d)" % rig.steps.size())
	var hard := 0.0
	var soft := 0.0
	var hard_count := 0
	var soft_count := 0
	var gap_after_bad := 0.0
	var gap_after_good := 0.0
	var gap_count := 0
	for index in range(1, rig.steps.size() - 1):
		var step: Dictionary = rig.steps[index]
		if step["foot"] == 0:
			hard += step["strength"]
			hard_count += 1
			gap_after_bad += float(rig.steps[index + 1]["frame"] - step["frame"])
			gap_count += 1
		else:
			soft += step["strength"]
			soft_count += 1
			gap_after_good += float(rig.steps[index + 1]["frame"] - step["frame"])
	hard /= float(maxi(hard_count, 1))
	soft /= float(maxi(soft_count, 1))
	_check(soft < hard * 0.6, "the good leg lands lighter than the bad one (%.2f against %.2f)" % [soft, hard])
	var ratio := (gap_after_bad / float(maxi(hard_count, 1))) / maxf(gap_after_good / float(maxi(soft_count, 1)), 0.001)
	_check(ratio > 1.3 and ratio < 2.0, "and the rhythm is uneven (%.2f)" % ratio)

	rig.motion.remove_profile_override(&"broken_leg")
	await _ticks(60)
	_check(rig.motion.get_active_profile() == WALK, "removing the override brings the walk back")

	# The most important override wins.
	rig.motion.push_profile_override(&"minor", STROLL, 1)
	rig.motion.push_profile_override(&"major", LIMP, 5)
	await _ticks(10)
	_check(rig.motion.get_active_profile() == LIMP, "the higher priority wins")
	rig.motion.remove_profile_override(&"major")
	await _ticks(10)
	_check(rig.motion.get_active_profile() == STROLL, "and the next one takes over when it goes")
	_end_world()


func _test_footstep_player() -> void:
	var character_stream: AudioStream = CHARACTER_SOUND
	var metal_stream: AudioStream = load("res://Assets/Audio/Footsteps/Surfaces/metal/step_metal_00.ogg")
	var dirt_stream: AudioStream = load("res://Assets/Audio/Footsteps/Characters/footstep01.ogg")
	var metal := SurfaceMaterial.new()
	metal.step_sound = metal_stream
	var dirt := SurfaceMaterial.new()
	dirt.step_sound = dirt_stream

	# Metal for the first 6 m, then a CSG floor that gets its surface from metadata.
	_begin_world()
	_world.get_child(1).free()
	var metal_floor := _add_floor(Vector3(0.0, -0.5, 97.0), Vector3(400.0, 1.0, 206.0))
	metal_floor.physics_material_override = metal
	var dirt_floor := CSGBox3D.new()
	dirt_floor.size = Vector3(400.0, 1.0, 194.0)
	dirt_floor.position = Vector3(0.0, -0.5, -103.0)
	dirt_floor.use_collision = true
	dirt_floor.set_meta(SurfaceMaterial.META_NAME, dirt)
	_world.add_child(dirt_floor)
	var rig := _make_rig()
	var player := FootstepPlayer.new()
	player.character_sound = character_stream
	rig.body.add_child(player)
	var played: Array[Dictionary] = []
	player.step_played.connect(func(character: AudioStream, surface_sound: AudioStream, surface: SurfaceMaterial) -> void:
		played.append({"character": character, "surface_sound": surface_sound, "surface": surface, "z": rig.body.global_position.z})
	)
	await _ticks(30)
	_check(player.get_surface_underfoot() == metal, "standing on a body with a surface material finds it")
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(240)
	_check(rig.steps.size() >= 8, "the character stepped (%d)" % rig.steps.size())
	_check(played.size() == rig.steps.size(), "and every step made a sound (%d of %d)" % [played.size(), rig.steps.size()])
	_check(played.all(func(step: Dictionary) -> bool: return step["character"] == character_stream), "each with the character's own sound")
	var on_metal := played.filter(func(step: Dictionary) -> bool: return step["z"] > -5.0)
	var on_dirt := played.filter(func(step: Dictionary) -> bool: return step["z"] < -7.0)
	_check(not on_metal.is_empty() and on_metal.all(func(step: Dictionary) -> bool: return step["surface_sound"] == metal_stream), "and the sound of metal while on metal (%d steps)" % on_metal.size())
	_check(not on_dirt.is_empty() and on_dirt.all(func(step: Dictionary) -> bool: return step["surface_sound"] == dirt_stream), "then dirt once on the CSG floor with a surface in its metadata (%d steps)" % on_dirt.size())
	_end_world()

	# Ground with no surface of its own sounds like the default surface.
	var default_surface := SurfaceMaterial.get_default()
	_check(default_surface != null and default_surface.step_sound != null, "there is a default surface with a sound")
	_begin_world()
	rig = _make_rig()
	player = FootstepPlayer.new()
	rig.body.add_child(player)
	played.clear()
	player.step_played.connect(func(character: AudioStream, surface_sound: AudioStream, surface: SurfaceMaterial) -> void:
		played.append({"character": character, "surface_sound": surface_sound, "surface": surface})
	)
	await _ticks(30)
	_check(player.get_surface_underfoot() == default_surface, "plain ground is the default surface")
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(180)
	_check(not played.is_empty() and played.all(func(step: Dictionary) -> bool: return step["surface_sound"] == default_surface.step_sound and step["character"] == null), "so with no character sound, only the ground is heard (%d steps)" % played.size())
	_end_world()

	# What counts as a surface.
	var rigid := RigidBody3D.new()
	rigid.physics_material_override = metal
	_check(SurfaceMaterial.from_collider(rigid) == metal, "a rigid body's physics material can be a surface")
	rigid.physics_material_override = PhysicsMaterial.new()
	_check(SurfaceMaterial.from_collider(rigid) == default_surface, "an ordinary physics material is not, so it is the default")
	rigid.free()
	_check(SurfaceMaterial.from_collider(null) == default_surface, "nothing at all is the default too")
	await physics_frame


func _test_player_scene() -> void:
	_begin_world()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.05, 0.0)
	_world.add_child(player)
	var motion := player.get_node("HeadMotion") as HeadMotion
	var footsteps := player.get_node("FootstepPlayer") as FootstepPlayer
	var camera := player.get_node("HeadRoot/YawPivot/PitchPivot/Camera3D") as Camera3D
	var steps := [0]
	var heard := [0]
	motion.footstep.connect(func(_foot: int, _strength: float, _profile: HeadBobProfile) -> void: steps[0] += 1)
	footsteps.step_played.connect(func(_character: AudioStream, _surface_sound: AudioStream, _surface: SurfaceMaterial) -> void: heard[0] += 1)
	await _ticks(40)
	_check(motion.walk_profile != null and motion.target == camera, "the player scene wires the head motion to the camera")

	Input.action_press("move_forward")
	var biggest_bob := 0.0
	for tick in 150:
		await physics_frame
		biggest_bob = maxf(biggest_bob, absf(camera.position.y))
	_check(steps[0] >= 5, "walking forward makes steps (%d)" % steps[0])
	_check(heard[0] == steps[0], "each with a sound (%d)" % heard[0])
	_check(biggest_bob > 0.02, "and bobs the camera (%.3f m)" % biggest_bob)
	Input.action_release("move_forward")

	Input.action_press("move_right")
	await _ticks(60)
	_check(rad_to_deg(camera.rotation.z) < -1.0, "strafing right leans the real camera right (%.2f)" % rad_to_deg(camera.rotation.z))
	Input.action_release("move_right")
	await _ticks(60)
	await _ticks(60)

	# A real jump: the view tips with the jump and takes a knock on landing.
	var landings: Array[Vector2] = []
	motion.landed.connect(func(speed: float, strength: float) -> void: landings.append(Vector2(speed, strength)))
	var jump_event := InputEventAction.new()
	jump_event.action = &"jump"
	jump_event.pressed = true
	Input.parse_input_event(jump_event)
	Input.action_press("jump")
	var lowest := 0.0
	var highest := 0.0
	var dipped := 0.0
	for tick in 120:
		await physics_frame
		var pitch := rad_to_deg(camera.rotation.x)
		lowest = minf(lowest, pitch)
		highest = maxf(highest, pitch)
		dipped = minf(dipped, camera.position.y)
		if tick == 2:
			Input.action_release("jump")
	_check(landings.size() == 1, "jumping and landing is one landing (%d)" % landings.size())
	_check(highest > 0.3, "the view tips up while falling (%.2f)" % highest)
	_check(lowest < -0.8, "and down for the jump and the landing (%.2f)" % lowest)
	_check(dipped < -0.01, "and the view drops on landing (%.3f m)" % dipped)
	await _ticks(60)
	_check(absf(rad_to_deg(camera.rotation.x)) < 0.05, "then settles level")
	_end_world()


# --- Helpers -----------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _begin_world(with_floor := true) -> void:
	_world = Node3D.new()
	_world.name = "TestWorld"
	add_child(_world)
	if with_floor:
		var field := DirectionalGravityField3D.new()
		var field_shape := CollisionShape3D.new()
		var field_box := BoxShape3D.new()
		field_box.size = Vector3(300.0, 200.0, 300.0)
		field_shape.shape = field_box
		field_shape.position = Vector3(0.0, 80.0, 0.0)
		field.add_child(field_shape)
		_world.add_child(field)
		var floor_body := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(400.0, 1.0, 400.0)
		floor_shape.shape = floor_box
		floor_body.add_child(floor_shape)
		floor_body.position = Vector3(0.0, -0.5, 0.0)
		_world.add_child(floor_body)


func _end_world() -> void:
	_world.free()
	_world = null


func _make_rig(position := Vector3(0.0, 0.05, 0.0)) -> Rig:
	var rig := Rig.new()
	var body := CharacterBody3D.new()
	body.collision_layer = PhysicsLayers.PLAYERS
	body.collision_mask = PhysicsLayers.PLAYER_MASK
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)

	var head := Node3D.new()
	head.position = Vector3(0.0, 1.6, 0.0)
	body.add_child(head)
	var yaw_pivot := Node3D.new()
	head.add_child(yaw_pivot)
	var pitch_pivot := Node3D.new()
	yaw_pivot.add_child(pitch_pivot)
	var camera := Camera3D.new()
	pitch_pivot.add_child(camera)

	var stats := MovementAttribute.new()
	stats.base_movement_speed = 5.0
	body.add_child(stats)
	var orientor := Orientator.new()
	body.add_child(orientor)
	var walker := Walker.new()
	body.add_child(walker)

	var motion := HeadMotion.new()
	motion.target = camera
	motion.controller = walker
	motion.walk_profile = WALK
	motion.sprint_profile = SPRINT
	motion.stroll_profile = STROLL
	motion.crouch_profile = CROUCH
	body.add_child(motion)

	var recorder := Recorder.new()
	recorder.camera = camera
	recorder.walker = walker
	body.add_child(recorder)

	motion.footstep.connect(func(index: int, strength: float, profile: HeadBobProfile) -> void:
		rig.steps.append({
			"frame": recorder.heights.size(),
			"foot": index,
			"strength": strength,
			"profile": profile,
		})
	)

	body.position = position
	_world.add_child(body)
	rig.body = body
	rig.walker = walker
	rig.yaw_pivot = yaw_pivot
	rig.camera = camera
	rig.motion = motion
	rig.recorder = recorder
	return rig


## Rising tips the view down, falling tips it up, each by how fast.
func _test_jump_tilt() -> void:
	_begin_world()
	var rig := _make_rig()
	rig.motion.bob_enabled = false
	rig.motion.impact_enabled = false
	await _ticks(30)
	var rise_limit := rig.motion.rise_pitch_degrees
	var fall_limit := rig.motion.fall_pitch_degrees
	_check(absf(rad_to_deg(rig.camera.rotation.x)) < 0.01, "level on the ground")

	var pitches: Array[float] = []
	var heights: Array[float] = []
	rig.walker.jump_once = true
	for tick in 70:
		await physics_frame
		pitches.append(rad_to_deg(rig.camera.rotation.x))
		heights.append(rig.body.global_position.y)
	var lowest := INF
	var lowest_at := 0
	var highest := -INF
	var highest_at := 0
	for index in pitches.size():
		if pitches[index] < lowest:
			lowest = pitches[index]
			lowest_at = index
		if pitches[index] > highest:
			highest = pitches[index]
			highest_at = index
	_check(lowest < -0.8 and lowest >= -rise_limit - 0.01, "rising tips the view down, by up to %.1f degrees (%.2f)" % [rise_limit, lowest])
	_check(highest > 0.5 and highest <= fall_limit + 0.01, "falling tips it up (%.2f of up to %.1f)" % [highest, fall_limit])
	_check(lowest_at < highest_at, "down on the way up, then up on the way down")
	var apex := 0
	for index in heights.size():
		if heights[index] > heights[apex]:
			apex = index
	_check(absf(pitches[apex]) < absf(lowest) * 0.5, "level at the top of the jump, where the speed is nothing (%.2f)" % pitches[apex])
	await _ticks(60)
	_check(absf(rad_to_deg(rig.camera.rotation.x)) < 0.05, "and level again once back on the ground (%.3f)" % rad_to_deg(rig.camera.rotation.x))
	_end_world()

	# A long fall tips it as far as it will go, and no further.
	_begin_world()
	rig = _make_rig(Vector3(0.0, 40.0, 0.0))
	rig.motion.bob_enabled = false
	rig.motion.impact_enabled = false
	var far := -INF
	for tick in 150:
		await physics_frame
		far = maxf(far, rad_to_deg(rig.camera.rotation.x))
	_check(far > fall_limit - 0.05 and far <= fall_limit + 0.01, "a long fall reaches the limit and stops there (%.2f)" % far)
	_end_world()

	# No jump tilt in flight or zero gravity.
	_begin_world(false)
	rig = _make_rig(Vector3(1000.0, 10.0, 0.0))
	rig.motion.bob_enabled = false
	rig.body.velocity = Vector3(0.0, 6.0, 0.0)
	await _ticks(30)
	_check(absf(rad_to_deg(rig.camera.rotation.x)) < 0.01, "drifting upward in zero gravity does not tip the view (%.3f)" % rad_to_deg(rig.camera.rotation.x))
	_end_world()


## Landing knocks the view down once and eases it back up, without bouncing. How hard depends on how
## fast the ground was hit.
func _test_landing_impact() -> void:
	var peaks: Array[float] = []
	var strengths: Array[float] = []
	for drop in [0.6, 2.0, 6.0, 30.0]:
		_begin_world()
		var rig := _make_rig(Vector3(0.0, drop + 0.05, 0.0))
		rig.motion.bob_enabled = false
		rig.motion.tilt_enabled = false
		rig.motion.air_tilt_enabled = false
		var landings: Array[Vector2] = []
		rig.motion.landed.connect(func(speed: float, strength: float) -> void: landings.append(Vector2(speed, strength)))
		var down := 0.0
		var down_at := 0
		var up := 0.0
		var dip := 0.0
		var pitches: Array[float] = []
		for tick in int(ceil(sqrt(2.0 * drop / 16.0) * 60.0)) + 150:
			await physics_frame
			var pitch := rad_to_deg(rig.camera.rotation.x)
			pitches.append(pitch)
			dip = minf(dip, rig.camera.position.y)
			if -pitch > down:
				down = -pitch
				down_at = pitches.size() - 1
		for index in range(down_at, pitches.size()):
			up = maxf(up, pitches[index])
		var label := "%.1f m drop" % drop
		_check(landings.size() == 1, "%s: lands once" % label)
		if landings.is_empty():
			_end_world()
			continue
		var expected_speed := sqrt(2.0 * 16.0 * drop)
		_check(absf(landings[0].x - expected_speed) < 1.2, "%s: hits at about %.1f m/s (%.1f)" % [label, expected_speed, landings[0].x])
		var expected_peak := landings[0].y * rig.motion.impact_pitch_degrees
		_check(absf(down - expected_peak) < expected_peak * 0.15 + 0.1, "%s: the view tips down by about %.2f degrees (%.2f)" % [label, expected_peak, down])
		_check(dip < -landings[0].y * rig.motion.impact_drop * 0.7, "%s: and drops (%.3f m)" % [label, dip])
		_check(up < down * 0.03 + 0.02, "%s: then comes back up without bouncing past level (%.3f up from %.2f down)" % [label, up, down])
		var settled := true
		for pitch in pitches.slice(pitches.size() - 20):
			if absf(pitch) > 0.05:
				settled = false
		_check(settled, "%s: and settles level" % label)
		peaks.append(down)
		strengths.append(landings[0].y)
		_end_world()

	_check(peaks[0] < peaks[1] and peaks[1] < peaks[2], "harder landings knock harder (%.2f, %.2f, %.2f degrees)" % [peaks[0], peaks[1], peaks[2]])
	_check(is_equal_approx(strengths[3], 1.0), "and there is a limit (%.2f)" % strengths[3])

	# A small step down is not a landing.
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.25, 0.0))
	rig.motion.air_tilt_enabled = false
	rig.motion.tilt_enabled = false
	rig.motion.bob_enabled = false
	var landed_count := [0]
	rig.motion.landed.connect(func(_speed: float, _strength: float) -> void: landed_count[0] += 1)
	var tiny := 0.0
	for tick in 90:
		await physics_frame
		tiny = maxf(tiny, absf(rad_to_deg(rig.camera.rotation.x)))
	_check(landed_count[0] == 0 and tiny < 0.2, "a short hop down is not felt (%d landings, %.2f degrees)" % [landed_count[0], tiny])
	_end_world()

	# The strength setting scales it, and zero switches it off.
	_begin_world()
	rig = _make_rig(Vector3(0.0, 6.05, 0.0))
	rig.motion.bob_enabled = false
	rig.motion.tilt_enabled = false
	rig.motion.air_tilt_enabled = false
	rig.motion.impact_strength = 0.5
	var half := 0.0
	for tick in 120:
		await physics_frame
		half = maxf(half, -rad_to_deg(rig.camera.rotation.x))
	_check(absf(half - peaks[2] * 0.5) < peaks[2] * 0.1, "half the impact strength gives half the knock (%.2f of %.2f)" % [half, peaks[2]])
	_end_world()

	_begin_world()
	rig = _make_rig(Vector3(0.0, 6.05, 0.0))
	rig.motion.bob_enabled = false
	rig.motion.tilt_enabled = false
	rig.motion.air_tilt_enabled = false
	rig.motion.impact_strength = 0.0
	var none := 0.0
	for tick in 120:
		await physics_frame
		none = maxf(none, absf(rad_to_deg(rig.camera.rotation.x)))
	_check(none < 0.001, "an impact strength of zero removes it (%.4f)" % none)
	_end_world()


func _add_floor(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


## Starting to walk is heard at once.
func _test_first_step_is_immediate() -> void:
	_begin_world()
	var rig := _make_rig()
	await _ticks(60)
	var frames_before := rig.recorder.heights.size()
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(10)
	_check(not rig.steps.is_empty(), "a step has sounded within 10 frames of setting off")
	if not rig.steps.is_empty():
		var delay: int = rig.steps[0]["frame"] - frames_before
		_check(delay <= 6, "in fact within %d frames (%.0f ms)" % [delay, delay * 16.7])
		_check(rig.steps[0]["strength"] >= 0.55, "and not a faint one (%.2f)" % rig.steps[0]["strength"])
		var height: float = rig.recorder.heights[rig.steps[0]["frame"]]
		_check(height < -0.01, "with the head dipping on it (%.4f)" % height)
	await _ticks(60)
	_check(rig.steps.size() >= 2, "then the walk goes on (%d steps)" % rig.steps.size())
	_check(rig.steps[1]["frame"] - rig.steps[0]["frame"] >= 12, "a stride later, not straight after (%d frames)" % (rig.steps[1]["frame"] - rig.steps[0]["frame"]))

	# Stopping and standing a while, then setting off again, is another first step.
	rig.walker.move = Vector2.ZERO
	await _ticks(60)
	var count := rig.steps.size()
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(8)
	_check(rig.steps.size() > count, "setting off again is heard at once too")
	_end_world()


## Hitting the ground is a step, and the walk carries on from it.
func _test_landing_step() -> void:
	# Standing jump: one step at touchdown, and nothing more.
	_begin_world()
	var rig := _make_rig()
	await _ticks(60)
	rig.walker.jump_once = true
	await _ticks(20)
	_check(rig.steps.is_empty(), "no step while in the air")
	var guard := 0
	while not rig.walker.is_grounded() and guard < 120:
		await physics_frame
		guard += 1
	await _ticks(2)
	_check(rig.steps.size() == 1, "touching down makes a step (%d)" % rig.steps.size())
	var jump_strength: float = rig.steps[0]["strength"] if not rig.steps.is_empty() else 0.0
	await _ticks(90)
	_check(rig.steps.size() == 1, "and standing there makes no more (%d)" % rig.steps.size())
	_end_world()

	# A hard fall lands harder.
	_begin_world()
	rig = _make_rig(Vector3(0.0, 8.05, 0.0))
	await _ticks(150)
	_check(rig.steps.size() == 1, "a fall ends with a step too (%d)" % rig.steps.size())
	_check(not rig.steps.is_empty() and rig.steps[0]["strength"] > jump_strength + 0.3, "heavier than from a jump (%.2f against %.2f)" % [rig.steps[0]["strength"] if not rig.steps.is_empty() else 0.0, jump_strength])
	_end_world()

	# Landing while walking: the landing is the first step, the next one a stride later.
	_begin_world()
	rig = _make_rig()
	await _ticks(30)
	rig.walker.move = Vector2(0.0, -1.0)
	await _ticks(80)
	rig.walker.jump_once = true
	guard = 0
	await _ticks(10)
	while not rig.walker.is_grounded() and guard < 120:
		await physics_frame
		guard += 1
	var touchdown := rig.recorder.heights.size()
	await _ticks(60)
	var after := rig.steps.filter(func(step: Dictionary) -> bool: return step["frame"] >= touchdown - 2)
	_check(after.size() >= 2, "walking on after landing (%d steps)" % after.size())
	if after.size() >= 2:
		_check(after[0]["frame"] - touchdown <= 3, "the first of them is the landing itself")
		_check(after[1]["frame"] - after[0]["frame"] >= 15, "and the next is a full stride later (%d frames), not right behind it" % (after[1]["frame"] - after[0]["frame"]))
	_end_world()


## Strolling and sneaking are quiet, and both together are close to silent.
func _test_quiet_steps() -> void:
	var loudness := {}
	for style in ["walk", "sprint", "stroll", "sneak", "sneak_stroll"]:
		_begin_world()
		var rig := _make_rig()
		await _ticks(40)
		rig.walker.move = Vector2(0.0, -1.0)
		rig.walker.sprint = style == "sprint"
		rig.walker.stroll = style == "stroll" or style == "sneak_stroll"
		rig.walker.crouch = style == "sneak" or style == "sneak_stroll"
		await _ticks(120)
		var first_strength: float = rig.steps[0]["strength"] if not rig.steps.is_empty() else -1.0
		rig.steps.clear()
		await _ticks(240)
		var total := 0.0
		for step in rig.steps:
			total += step["strength"]
		var average := total / float(maxi(rig.steps.size(), 1))
		loudness[style] = average
		var first_label := "%.2f" % first_strength
		print("  info %s: %d steps in 4 s, average strength %.3f (%.1f dB), first step %s" % [style, rig.steps.size(), average, linear_to_db(maxf(average, 0.0001)), first_label])
		if style == "stroll" or style == "sneak" or style == "sneak_stroll":
			_check(first_strength >= 0.0 and first_strength < average * 2.0 + 0.05, "%s: even the first step is as quiet as the rest (%.3f against %.3f)" % [style, first_strength, average])
		_end_world()
	_check(loudness["sprint"] > loudness["walk"], "sprinting is louder than walking (%.2f against %.2f)" % [loudness["sprint"], loudness["walk"]])
	_check(loudness["stroll"] < loudness["walk"] * 0.4, "strolling is much quieter (%.2f against %.2f)" % [loudness["stroll"], loudness["walk"]])
	_check(loudness["sneak"] < loudness["walk"] * 0.3, "sneaking is quieter still (%.2f)" % loudness["sneak"])
	_check(loudness["sneak_stroll"] < 0.1, "and sneaking while strolling is close to silent (%.3f, %.0f dB)" % [loudness["sneak_stroll"], linear_to_db(loudness["sneak_stroll"])])
