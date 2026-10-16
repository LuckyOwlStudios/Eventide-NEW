extends Node
## Headless checks for CharacterController on real physics.
##
## Run from the project folder (fixed-fps makes every frame exactly one tick):
## godot --headless --fixed-fps 60 --path . res://Components/Movement/Testing/CharacterControllerTest.tscn

const TICK := 1.0 / 60.0

var physics_frame: Signal
var _world: Node3D
var _failures := 0


class ScriptedController extends CharacterController:
	var move := Vector2.ZERO
	var vertical := 0.0
	var roll := 0.0
	var yaw := 0.0
	var pitch := 0.0
	var sprint := false
	var stroll := false
	var crouch := false
	var jump_once := false
	var toggle_flight_once := false

	func poll_intent(_delta: float) -> MoveIntent:
		var intent := MoveIntent.new()
		intent.move = move
		intent.vertical = vertical
		intent.roll = roll
		intent.yaw = yaw
		intent.pitch = pitch
		intent.sprint = sprint
		intent.stroll = stroll
		intent.crouch = crouch
		intent.jump_pressed = jump_once
		intent.toggle_flight = toggle_flight_once
		jump_once = false
		toggle_flight_once = false
		return intent


class Rig:
	var body: WalkingCharacter3D
	var controller: ScriptedController
	var stamina: Stamina
	var jetpack: Jetpack

	func body_shape() -> Shape3D:
		return body.collision_shape.shape


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	# ONLY=name runs just the test whose function is _test_<name>.
	var only := OS.get_environment("ONLY")
	for test_name in [
		"wire_formats", "fall_and_land", "walk_speeds", "sprint_stamina", "jump_height",
		"jump_buffer", "coyote_time", "air_control", "stairs_up_and_down", "stair_variants",
		"tall_wall_blocks", "crouch_and_ceiling", "zero_gravity_drift_jetpack_roll",
		"creative_flight", "movement_lock", "replay_matches_live", "tilted_gravity",
			"crouch_and_stroll_stack", "roll_follows_view", "ai_controller",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("CharacterController tests passed.")
	else:
		print("CharacterController tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_wire_formats() -> void:
	var intent := MoveIntent.new()
	intent.move = Vector2(0.7071, -1.0)
	intent.vertical = -0.5
	intent.roll = 0.25
	intent.yaw = 2.5
	intent.pitch = -0.9
	intent.jump_pressed = true
	intent.crouch = true
	intent.quantize()
	var buffer := PackedByteArray()
	buffer.resize(MoveIntent.ENCODED_SIZE + 3)
	intent.encode_to(buffer, 3)
	var decoded := MoveIntent.decode_from(buffer, 3)
	_check(decoded.move.is_equal_approx(intent.move), "intent move survives encoding")
	_check(is_equal_approx(decoded.yaw, intent.yaw), "intent yaw survives encoding")
	_check(is_equal_approx(decoded.pitch, intent.pitch), "intent pitch survives encoding (%.4f)" % decoded.pitch)
	_check(absf(decoded.pitch - -0.9) < 0.001, "and is close to what was asked for")
	_check(decoded.jump_pressed and decoded.crouch and not decoded.sprint, "intent flags survive encoding")

	var state := MoveState.new()
	state.position = Vector3(1.5, -2.0, 30.25)
	state.rotation = Quaternion(Vector3.UP, 1.0)
	state.velocity = Vector3(0.0, -3.0, 1.0)
	state.crouching = true
	state.grounded = true
	state.coyote_time_left = 0.1
	state.step_assist_ticks = 4
	var round_trip := MoveState.decode(state.encode())
	_check(round_trip != null, "state decodes")
	if round_trip != null:
		_check(round_trip.position.is_equal_approx(state.position), "state position survives encoding")
		_check(round_trip.crouching and round_trip.grounded and not round_trip.flying, "state flags survive encoding")
		_check(round_trip.step_assist_ticks == 4, "state step assist survives encoding")
	_check(MoveState.decode(PackedByteArray([1, 2, 3])) == null, "malformed state is rejected")
	await physics_frame


func _test_fall_and_land() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 3.0, 0.0))
	var landed_speeds: Array[float] = []
	rig.controller.landed.connect(func(speed: float) -> void: landed_speeds.append(speed))
	await _ticks(120)
	_check(rig.controller.is_grounded(), "falling character ends up grounded")
	_check(absf(rig.body.global_position.y) < 0.02, "character rests on the floor (y=%.4f)" % rig.body.global_position.y)
	_check(landed_speeds.size() == 1, "landed fires exactly once (got %d)" % landed_speeds.size())
	if not landed_speeds.is_empty():
		_check(landed_speeds[0] > 5.0, "impact speed is reported (%.2f)" % landed_speeds[0])
	_end_world()


func _test_walk_speeds() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	var start := rig.body.global_position
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(60)
	var walked := start.distance_to(rig.body.global_position)
	_check(walked > 4.4 and walked < 5.1, "walking covers about 5 m in a second (%.2f)" % walked)
	_check(rig.body.global_position.z < start.z - 4.0, "forward is -Z")

	rig.controller.sprint = true
	await _ticks(30)
	var sprint_speed := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(absf(sprint_speed - 7.5) < 0.2, "sprint is 1.5x speed (%.2f)" % sprint_speed)

	rig.controller.sprint = false
	rig.controller.stroll = true
	await _ticks(30)
	var stroll_speed := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(absf(stroll_speed - 2.5) < 0.2, "stroll is half speed (%.2f)" % stroll_speed)

	rig.controller.stroll = false
	rig.controller.move = Vector2(1.0, 0.0)
	await _ticks(30)
	_check(rig.body.velocity.x > 4.5, "right input moves +X (%.2f)" % rig.body.velocity.x)
	rig.controller.yaw = PI / 2.0
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(30)
	_check(rig.body.velocity.x < -4.5, "yaw turns the heading (%.2f)" % rig.body.velocity.x)

	_end_world()


func _test_sprint_stamina() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0), true)
	await _ticks(20)
	var before := rig.stamina.stamina
	rig.controller.move = Vector2(0.0, -1.0)
	rig.controller.sprint = true
	await _ticks(60)
	var spent := before - rig.stamina.stamina
	_check(spent > 12.0 and spent < 18.0, "a second of sprint costs about 15 stamina (%.2f)" % spent)

	var emptied := false
	for tick in 60 * 10:
		await physics_frame
		if rig.stamina.is_depleted():
			emptied = true
			break
	_check(emptied, "sprinting drains stamina to empty")
	await _ticks(15)
	var speed := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(absf(speed - 5.0) < 0.3, "an exhausted character cannot sprint (%.2f)" % speed)
	rig.controller.sprint = false
	rig.controller.move = Vector2.ZERO
	_end_world()


func _test_jump_height() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	var jumps := [0]
	rig.controller.jumped.connect(func() -> void: jumps[0] += 1)
	rig.controller.jump_once = true
	var peak := 0.0
	for tick in 90:
		await physics_frame
		peak = maxf(peak, rig.body.global_position.y)
	_check(jumps[0] == 1, "jumped fires once (%d)" % jumps[0])
	_check(absf(peak - 1.0) < 0.12, "a jump reaches the jump height attribute (%.3f)" % peak)
	_check(rig.controller.is_grounded(), "and the character lands again")

	rig.body._jump_height = 2.0
	await _ticks(10)
	rig.controller.jump_once = true
	peak = 0.0
	for tick in 120:
		await physics_frame
		peak = maxf(peak, rig.body.global_position.y)
	_check(absf(peak - 2.0) < 0.2, "changing the attribute changes the jump (%.3f)" % peak)
	_end_world()


func _test_jump_buffer() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.09, 0.0))
	await physics_frame
	rig.controller.jump_once = true
	var peak := 0.0
	for tick in 60:
		await physics_frame
		peak = maxf(peak, rig.body.global_position.y)
	_check(peak > 0.7, "a jump pressed just before landing still happens (%.3f)" % peak)
	_end_world()

	_begin_world()
	rig = _make_rig(Vector3(0.0, 0.09, 0.0))
	rig.body.jump_buffer_time = 0.0
	await physics_frame
	rig.controller.jump_once = true
	peak = 0.0
	for tick in 60:
		await physics_frame
		peak = maxf(peak, rig.body.global_position.y)
	_check(peak < 0.2, "without the buffer that press is lost (%.3f)" % peak)
	_end_world()


func _test_coyote_time() -> void:
	for late in [false, true]:
		_begin_world(false)
		_add_box(Vector3(0.0, -0.5, 0.0), Vector3(4.0, 1.0, 4.0))
		var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
		await _ticks(20)
		rig.controller.move = Vector2(0.0, -1.0)
		var guard := 0
		while rig.controller.is_grounded() and guard < 200:
			await physics_frame
			guard += 1
		_check(not rig.controller.is_grounded(), "character walks off the ledge")
		rig.controller.move = Vector2.ZERO
		await _ticks(12 if late else 2)
		var before := rig.body.velocity.y
		rig.controller.jump_once = true
		await _ticks(2)
		var gained := rig.body.velocity.y - before
		if late:
			_check(gained < 0.0, "a jump after the coyote window does nothing (%.2f)" % gained)
		else:
			_check(rig.body.velocity.y > 1.0, "a jump inside the coyote window works (%.2f)" % rig.body.velocity.y)
		_end_world()


func _test_air_control() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	rig.controller.jump_once = true
	await _ticks(3)
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(12)
	var speed := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(not rig.controller.is_grounded(), "still airborne")
	_check(speed > 0.5 and speed < 2.5, "air control steers only a little (%.2f m/s)" % speed)
	_end_world()


func _test_stairs_up_and_down() -> void:
	_begin_world()
	var steps := 6
	for index in steps:
		# Each step is a solid block from the floor up to its own height.
		var top := 0.18 * float(index + 1)
		_add_box(Vector3(0.0, top * 0.5, -3.0 - 0.3 * float(index)), Vector3(3.0, top, 0.3))
	_add_box(Vector3(0.0, 0.18 * steps * 0.5, -3.0 - 0.3 * float(steps - 1) - 0.15 - 6.0), Vector3(3.0, 0.18 * steps, 12.0))
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	rig.controller.move = Vector2(0.0, -1.0)
	var airborne_ticks := 0
	for tick in 100:
		await physics_frame
		if tick > 30 and not rig.controller.is_grounded():
			airborne_ticks += 1
	var top_height := 0.18 * float(steps)
	_check(absf(rig.body.global_position.y - top_height) < 0.04, "walking up stairs reaches the top (y=%.3f of %.3f)" % [rig.body.global_position.y, top_height])
	_check(rig.body.global_position.z < -4.5, "and keeps moving along it (z=%.2f)" % rig.body.global_position.z)
	_check(airborne_ticks < 12, "stair climbing is not a series of hops (%d airborne ticks)" % airborne_ticks)

	# Back down: face the other way.
	rig.controller.yaw = PI
	var airborne_down := 0
	for tick in 150:
		await physics_frame
		if tick > 10 and not rig.controller.is_grounded():
			airborne_down += 1
	_check(absf(rig.body.global_position.y) < 0.04, "walking back down ends on the floor (y=%.3f)" % rig.body.global_position.y)
	_check(airborne_down < 6, "descending stays on the stairs instead of falling (%d airborne ticks)" % airborne_down)
	_end_world()


## Different stairs, speeds and approach angles: the climb must always get there and
## the descent must always stay on the steps.
func _test_stair_variants() -> void:
	var cases := [
		{"rise": 0.15, "run": 0.25, "speed": "walk"},
		{"rise": 0.20, "run": 0.30, "speed": "sprint"},
		{"rise": 0.25, "run": 0.35, "speed": "walk"},
		{"rise": 0.30, "run": 0.40, "speed": "walk"},
		{"rise": 0.18, "run": 0.28, "speed": "stroll"},
		{"rise": 0.18, "run": 0.28, "speed": "diagonal"},
	]
	for case in cases:
		await _run_stair_case(case["rise"], case["run"], case["speed"])


func _run_stair_case(rise: float, run: float, style: String) -> void:
	_begin_world()
	var steps := 6
	var label := "rise %.2f run %.2f %s" % [rise, run, style]
	for index in steps:
		var top := rise * float(index + 1)
		_add_box(Vector3(0.0, top * 0.5, -3.0 - run * float(index)), Vector3(14.0, top, run))
	var landing_z := -3.0 - run * float(steps - 1) - run * 0.5 - 6.0
	_add_box(Vector3(0.0, rise * steps * 0.5, landing_z), Vector3(14.0, rise * steps, 12.0))
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(20)
	rig.controller.move = Vector2(0.0, -1.0)
	match style:
		"sprint":
			rig.controller.sprint = true
		"stroll":
			rig.controller.stroll = true
		"diagonal":
			rig.controller.move = Vector2(0.5, -1.0).normalized()
	var speed := 5.0 * (1.5 if style == "sprint" else (0.5 if style == "stroll" else 1.0))
	var climb_ticks := int(ceil((3.0 + run * steps + 1.5) / speed * 60.0))
	var airborne := 0
	for tick in climb_ticks:
		await physics_frame
		if not rig.controller.is_grounded():
			airborne += 1
	var top_height := rise * float(steps)
	_check(absf(rig.body.global_position.y - top_height) < 0.05, "stairs (%s) climbed to the top (y=%.3f of %.3f)" % [label, rig.body.global_position.y, top_height])
	_check(airborne <= 2, "stairs (%s) climbed without hopping (%d airborne ticks)" % [label, airborne])

	# Turn around and walk back down.
	rig.controller.yaw = PI
	rig.controller.sprint = false
	airborne = 0
	for tick in int(ceil((run * steps + 6.0) / speed * 60.0)):
		await physics_frame
		if tick > 6 and not rig.controller.is_grounded():
			airborne += 1
	_check(absf(rig.body.global_position.y) < 0.05, "stairs (%s) descended to the floor (y=%.3f)" % [label, rig.body.global_position.y])
	_check(airborne <= 2, "stairs (%s) descended without falling (%d airborne ticks)" % [label, airborne])
	_end_world()


func _test_tall_wall_blocks() -> void:
	_begin_world()
	_add_box(Vector3(0.0, 0.3, -3.0), Vector3(4.0, 0.6, 0.5))
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(20)
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(120)
	_check(rig.body.global_position.y < 0.05, "a wall taller than the step height is not climbed (y=%.3f)" % rig.body.global_position.y)
	_check(rig.body.global_position.z > -3.0, "and it blocks (z=%.2f)" % rig.body.global_position.z)
	_end_world()


func _test_crouch_and_ceiling() -> void:
	_begin_world()
	# A low ceiling the standing capsule (1.8 m) cannot enter.
	_add_box(Vector3(0.0, 1.2 + 0.5, -6.0), Vector3(3.0, 1.0, 4.0))
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	_check(rig.body_shape() is CapsuleShape3D, "standing uses the capsule")
	rig.controller.crouch = true
	await _ticks(40)
	_check(rig.controller.is_crouching(), "crouch is on")
	_check(rig.body_shape() is SphereShape3D, "crouching swaps to a sphere")
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(30)
	var crouch_speed := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(absf(crouch_speed - 2.5) < 0.2, "crouched movement is slower (%.2f)" % crouch_speed)

	# Crawl under the ceiling, then let go of crouch while still under it.
	await _ticks(120)
	_check(rig.body.global_position.z < -5.0, "the crouched character fits under the ceiling (z=%.2f)" % rig.body.global_position.z)
	rig.controller.crouch = false
	rig.controller.move = Vector2.ZERO
	await _ticks(30)
	_check(rig.controller.is_crouching(), "releasing crouch under a low ceiling keeps you crouched")
	_check(not rig.controller.can_stand(), "can_stand reports the blockage")

	# Leave from underneath and it stands up by itself.
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(150)
	_check(not rig.controller.is_crouching(), "clear of the ceiling the character stands (z=%.2f)" % rig.body.global_position.z)
	_check(rig.body_shape() is CapsuleShape3D, "and the capsule is back")
	_end_world()


func _test_zero_gravity_drift_jetpack_roll() -> void:
	_begin_world(false)
	var rig := _make_rig(Vector3(1000.0, 10.0, 0.0), false, false)
	rig.body.velocity = Vector3(0.0, 0.0, -2.0)
	await _ticks(60)
	var drifted := absf(rig.body.global_position.z)
	_check(not rig.controller.has_gravity, "no gravity out here")
	_check(drifted > 1.9 and drifted < 2.1, "without thrust a floating character keeps drifting (%.2f m in 1 s)" % drifted)
	_check(is_equal_approx(rig.body.velocity.z, -2.0), "and keeps its speed")
	_check(rig.controller.get_move_mode() == CharacterController.MoveMode.FLOATING, "mode is floating")

	rig.controller.roll = 1.0
	var up_before := rig.body.global_basis.y
	await _ticks(30)
	rig.controller.roll = 0.0
	var rolled := rad_to_deg(up_before.angle_to(rig.body.global_basis.y))
	_check(absf(rolled - 60.0) < 4.0, "half a second of roll turns the body about 60 degrees (%.1f)" % rolled)

	rig.body.velocity = Vector3.ZERO
	await _ticks(2)
	_end_world()

	_begin_world(false)
	rig = _make_rig(Vector3(1000.0, 10.0, 0.0), false, true)
	await _ticks(5)
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(90)
	var thrust_speed := rig.body.velocity.length()
	_check(thrust_speed > 5.0 and thrust_speed <= 10.05, "the jetpack accelerates toward its top speed (%.2f)" % thrust_speed)
	rig.controller.move = Vector2.ZERO
	await _ticks(150)
	_check(rig.body.velocity.length() < 0.3, "dampeners bring it to a stop (%.2f)" % rig.body.velocity.length())
	rig.controller.vertical = 1.0
	await _ticks(30)
	_check(rig.body.velocity.y > 2.0, "vertical thrust goes up (%.2f)" % rig.body.velocity.y)
	_end_world()


func _test_creative_flight() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	rig.controller.toggle_flight_once = true
	await _ticks(2)
	_check(rig.controller.is_flying(), "toggle starts flight")
	rig.controller.vertical = 1.0
	await _ticks(45)
	var height := rig.body.global_position.y
	_check(height > 4.0, "flight climbs quickly (%.2f)" % height)
	rig.controller.vertical = 0.0
	await _ticks(40)
	height = rig.body.global_position.y
	await _ticks(60)
	_check(absf(rig.body.global_position.y - height) < 0.05, "and hovers when released (%.2f -> %.2f)" % [height, rig.body.global_position.y])
	_check(rig.controller.is_flying(), "still flying")

	rig.controller.vertical = -1.0
	await _ticks(180)
	_check(not rig.controller.is_flying(), "touching down ends flight")
	_check(rig.controller.is_grounded(), "and the character is back on the ground")
	_end_world()

	_begin_world()
	rig = _make_rig(Vector3(0.0, 0.05, 0.0))
	rig.controller.allow_creative_flight = false
	await _ticks(30)
	rig.controller.toggle_flight_once = true
	await _ticks(5)
	_check(not rig.controller.is_flying(), "a forbidden flight toggle is ignored")
	_end_world()


func _test_movement_lock() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	rig.controller.movement_blocker.add(1, "test")
	rig.controller.move = Vector2(0.0, -1.0)
	var start := rig.body.global_position
	await _ticks(30)
	_check(rig.body.global_position.distance_to(start) < 0.001, "a blocked controller does not move the body")
	rig.controller.movement_blocker.remove(1)
	await _ticks(30)
	_check(rig.body.global_position.distance_to(start) > 1.0, "and it picks up again when unblocked")
	_end_world()


## Prediction depends on this: rewinding to a captured state and replaying the same
## intents has to land exactly where the live run did.
func _test_replay_matches_live() -> void:
	_begin_world()
	_add_box(Vector3(0.0, 0.09, -4.0), Vector3(3.0, 0.18, 2.0))
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)

	var script: Array[MoveIntent] = []
	for tick in 150:
		var intent := MoveIntent.new()
		intent.move = Vector2(sin(tick * 0.07), -1.0).limit_length(1.0)
		intent.yaw = sin(tick * 0.03) * 0.8
		intent.sprint = tick % 50 > 30
		intent.crouch = tick > 100 and tick < 120
		intent.jump_pressed = tick % 45 == 20
		script.append(intent.quantize())

	var start_state := rig.controller.capture_state()
	# Drive it by hand so its own polling stays out of the way.
	rig.controller.movement_blocker.add(7, "manual stepping")
	await physics_frame
	var live: Array[MoveState] = []
	for intent in script:
		rig.controller.step(intent.duplicate())
		live.append(rig.controller.capture_state())
	rig.controller.apply_state(start_state)
	var replayed: Array[MoveState] = []
	for intent in script:
		rig.controller.replay(intent.duplicate())
		replayed.append(rig.controller.capture_state())
	var worst := 0.0
	for index in script.size():
		worst = maxf(worst, live[index].position.distance_to(replayed[index].position))
	_check(worst < 0.0005, "replaying inputs reproduces the live run (worst drift %.6f m)" % worst)
	_check(live[-1].position.distance_to(start_state.position) > 3.0, "the scripted run actually went somewhere")
	rig.controller.movement_blocker.remove(7)
	_end_world()


## Interiors use gravity fields at any angle. Turn gravity sideways and the character
## must stand on the "wall", turn to it, and walk along it.
func _test_tilted_gravity() -> void:
	_begin_world(false)
	# Gravity pointing +X, with a floor to match at x = 10 (facing -X).
	var field := _world.get_child(0) as DirectionalGravityField3D
	field.global_transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.0, 0.0, 0.0))
	field.get_child(0).position = Vector3(0.0, 0.0, 0.0)
	(field.get_child(0).shape as BoxShape3D).size = Vector3(60.0, 60.0, 60.0)
	_add_box(Vector3(10.5, 0.0, 0.0), Vector3(1.0, 100.0, 100.0))
	var rig := _make_rig(Vector3(9.0, 0.0, 0.0))
	await _ticks(150)
	var up := rig.body.global_basis.y
	_check(rig.controller.has_gravity, "the tilted field gives gravity")
	_check(up.dot(Vector3.LEFT) > 0.99, "the body turns so its up is away from the new floor (up=%s)" % up)
	_check(rig.controller.is_grounded(), "and it stands on the wall")
	_check(absf(rig.body.global_position.x - 10.0) < 0.05, "at the surface (x=%.3f)" % rig.body.global_position.x)
	var start := rig.body.global_position
	rig.controller.move = Vector2(0.0, -1.0)
	await _ticks(60)
	var moved := rig.body.global_position - start
	_check(moved.length() > 4.3, "walking moves along the surface (%.2f m)" % moved.length())
	_check(absf(moved.x) < 0.1, "without leaving it (dx=%.3f)" % moved.x)
	_end_world()


## Crouching and strolling each halve the speed, and doing both multiplies them.
func _test_crouch_and_stroll_stack() -> void:
	_begin_world()
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	rig.controller.move = Vector2(0.0, -1.0)
	rig.controller.crouch = true
	rig.controller.stroll = true
	await _ticks(90)
	var creep := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(rig.controller.is_crouching(), "crouching while strolling")
	_check(absf(creep - 1.25) < 0.1, "crouch and stroll together creep at a quarter speed (%.2f)" % creep)

	rig.controller.stroll = false
	await _ticks(60)
	var crouch_only := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(absf(crouch_only - 2.5) < 0.15, "crouching alone is half speed (%.2f)" % crouch_only)

	rig.controller.crouch = false
	rig.controller.stroll = true
	await _ticks(60)
	var stroll_only := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(not rig.controller.is_crouching(), "standing again")
	_check(absf(stroll_only - 2.5) < 0.15, "strolling alone is half speed (%.2f)" % stroll_only)

	# Sprint cannot cancel either slowdown.
	rig.controller.crouch = true
	rig.controller.sprint = true
	await _ticks(60)
	var sprint_attempt := Vector2(rig.body.velocity.x, rig.body.velocity.z).length()
	_check(absf(sprint_attempt - 1.25) < 0.1, "holding sprint does not undo them (%.2f)" % sprint_attempt)
	_end_world()


## Rolling must spin the view around the line of sight, wherever the player is
## looking, instead of around the body's own forward axis.
func _test_roll_follows_view() -> void:
	for look: Vector2 in [
		Vector2(0.0, 0.0),
		Vector2(PI / 2.0, 0.0),
		Vector2(1.0, 0.7),
		Vector2(-2.2, -0.9),
		Vector2(0.4, 1.4),
	]:
		_begin_world(false)
		var rig := _make_rig(Vector3(1000.0, 10.0, 0.0))
		await _ticks(5)
		rig.controller.yaw = look.x
		rig.controller.pitch = look.y
		await _ticks(1)
		var view_before := _view_direction(rig.body, rig.controller.yaw, rig.controller.pitch)
		var rotation_before := rig.body.global_basis.get_rotation_quaternion()
		rig.controller.roll = 1.0
		await _ticks(30)
		rig.controller.roll = 0.0
		await _ticks(1)
		var label := "yaw %.1f pitch %.1f" % [look.x, look.y]
		var view_after := _view_direction(rig.body, rig.controller.yaw, rig.controller.pitch)
		var drift := rad_to_deg(view_before.angle_to(view_after))
		var turned := rad_to_deg(rotation_before.angle_to(rig.body.global_basis.get_rotation_quaternion()))
		_check(drift < 1.0, "roll keeps looking the same way (%s: view moved %.2f degrees)" % [label, drift])
		_check(absf(turned - 60.0) < 4.0, "and spins the body about 60 degrees in half a second (%s: %.1f)" % [label, turned])
		_end_world()

	# Looking straight down -Z, rolling right lays the body's up toward +X: the
	# player's right-hand side. Rolling left goes the other way.
	_begin_world(false)
	var rig := _make_rig(Vector3(1000.0, 10.0, 0.0))
	await _ticks(5)
	rig.controller.roll = 1.0
	await _ticks(20)
	var leaned_right := rig.body.global_basis.y.x
	_check(leaned_right > 0.4, "roll right leans the body's up toward the player's right (%.2f)" % leaned_right)
	rig.controller.roll = -1.0
	await _ticks(40)
	var leaned_left := rig.body.global_basis.y.x
	_check(leaned_left < -0.4, "and roll left leans it the other way (%.2f)" % leaned_left)
	_end_world()


## An AI drives the very same movement a player does.
func _test_ai_controller() -> void:
	_begin_world()
	var npc := _make_ai(Vector3(0.0, 0.05, 0.0))
	await _ticks(20)
	var body := npc.get_body()
	var arrivals := [0]
	npc.destination_reached.connect(func() -> void: arrivals[0] += 1)

	npc.move_to(Vector3(6.0, 0.0, 6.0))
	_check(npc.is_moving_to_destination(), "move_to starts walking")
	await _ticks(60 * 3)
	var remaining := Vector2(body.global_position.x - 6.0, body.global_position.z - 6.0).length()
	_check(arrivals[0] == 1, "arrival is reported once (%d)" % arrivals[0])
	_check(remaining < 1.0, "the NPC got to its destination (%.2f m away)" % remaining)
	_check(not npc.is_moving_to_destination(), "and stopped heading for it")
	_check(Vector2(body.velocity.x, body.velocity.z).length() < 0.2, "and came to rest")

	npc.sprint_to_destination = true
	npc.move_to(Vector3(-6.0, 0.0, 6.0))
	await _ticks(45)
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	_check(absf(speed - 7.5) < 0.3, "sprint_to_destination sprints like a player (%.2f)" % speed)
	await _ticks(120)
	npc.sprint_to_destination = false
	_check(arrivals[0] == 2, "second arrival (%d)" % arrivals[0])

	var peak := 0.0
	npc.jump()
	for tick in 90:
		await physics_frame
		peak = maxf(peak, body.global_position.y)
	_check(absf(peak - 1.0) < 0.15, "the NPC jumps to the same height as a player (%.2f)" % peak)

	npc.face_position(body.global_position + Vector3(0.0, 4.0, -4.0))
	var facing := Basis(Vector3.UP, npc.look_yaw) * Vector3.FORWARD
	_check(facing.dot(Vector3.FORWARD) > 0.99, "face_position turns toward a point")
	_check(absf(npc.look_pitch - PI / 4.0) < 0.01, "and looks up at it (%.2f)" % npc.look_pitch)

	npc.stop()
	npc.wants_crouch = true
	await _ticks(30)
	_check(npc.is_crouching(), "wants_crouch crouches the NPC")
	_end_world()


# --- Helpers -----------------------------------------------------------------

## The direction the camera looks: the body turned by yaw, then tipped up by pitch.
func _view_direction(body: Node3D, yaw: float, pitch: float) -> Vector3:
	return (body.global_basis.orthonormalized() * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD).normalized()


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
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 200.0, 300.0)
	field_shape.shape = box
	field_shape.position = Vector3(0.0, 80.0, 0.0)
	field.add_child(field_shape)
	_world.add_child(field)
	if with_floor:
		_add_box(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))


func _end_world() -> void:
	_world.free()
	_world = null


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


func _make_ai(position: Vector3) -> AICharacterController:
	var body := TestCharacter.make("Npc", PhysicsLayers.CREATURES, PhysicsLayers.CREATURE_MASK)
	var ai := AICharacterController.new()
	body.add_child(ai)
	body.position = position
	_world.add_child(body)
	return ai


func _make_rig(position: Vector3, with_stamina := false, with_jetpack := false) -> Rig:
	var rig := Rig.new()
	var body := TestCharacter.make("Player")

	var controller := ScriptedController.new()
	controller.name = "Controller"
	if with_stamina:
		rig.stamina = Stamina.new()
		rig.stamina.name = "Stamina"
		body.add_child(rig.stamina)
		controller.stamina = rig.stamina
	if with_jetpack:
		rig.jetpack = Jetpack.new()
		rig.jetpack.name = "Jetpack"
		body.add_child(rig.jetpack)
	body.add_child(controller)

	body.position = position
	_world.add_child(body)
	rig.body = body
	rig.controller = controller
	return rig
