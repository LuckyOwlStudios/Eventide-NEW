extends Node
## Headless checks for Suspension3D on real Jolt physics: a spring on a ray that holds a rigid body
## up, settles without bouncing, never pulls, and carries a wheel or a foot to the ground.
##
## godot --headless --fixed-fps 60 --path . res://Components/Physics/Testing/SuspensionTest.tscn
## ONLY=<name> runs one test, such as ONLY=grip.

## Gravity of the field below.
const GRAVITY := 16.0
## A test body's collision box.
const BODY_SIZE := Vector3(2.0, 0.5, 4.0)
## Each spring is mounted at the middle of the body and reaches this far down, which is 0.8 m below
## the bottom. It cannot be mounted lower: a ray that starts inside the floor sees no floor.
const REACH := 1.05
## The height the body settles at on four springs of strength 20 in this gravity: the reach, less the
## squeeze that makes four springs carry its weight (16 / (4 x 20) = 0.2 m).
const STANDING_HEIGHT := REACH - GRAVITY / (4.0 * 20.0)

var _world: Node3D
var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in [
		"finds_its_body", "holds_up", "any_mass", "stiffness", "damping", "disabled", "reach", "never_pulls",
		"extension", "moving_parts", "grip", "pushes_back", "signal", "tilted", "hard_landing", "cost",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			_begin_world()
			await call("_test_" + test_name)
			_end_world()
	if _failures == 0:
		print("Suspension tests passed.")
	else:
		print("Suspension tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_finds_its_body() -> void:
	var body := _body(Vector3(0.0, 5.0, 0.0), 0)
	var spring := _spring(body, Vector3.ZERO)
	_check(spring.rigid_body == body, "a spring under a body finds it")
	var holder := Node3D.new()
	body.add_child(holder)
	var nested := Suspension3D.new()
	nested.target_position = Vector3(0.0, -REACH, 0.0)
	holder.add_child(nested)
	_check(nested.rigid_body == body, "and so does one further down the tree")
	var other := _body(Vector3(20.0, 5.0, 0.0), 0)
	var chosen := Suspension3D.new()
	chosen.rigid_body = other
	body.add_child(chosen)
	_check(chosen.rigid_body == other, "one given a body uses that one")
	var lost := Suspension3D.new()
	_world.add_child(lost)
	await _frames(2)
	_check(lost.rigid_body == null and not lost.is_physics_processing(), "one with no body anywhere above it does nothing")


func _test_holds_up() -> void:
	var body := _body(Vector3(0.0, 4.0, 0.0), 4)
	await _frames(300)
	_check(absf(body.global_position.y - STANDING_HEIGHT) < 0.02, "a body on four springs settles %.2f m up, as strength says it should (%.3f)" % [STANDING_HEIGHT, body.global_position.y])
	_check(body.linear_velocity.length() < 0.01, "and comes to rest (%.4f m/s)" % body.linear_velocity.length())
	_check(absf(body.global_basis.y.dot(Vector3.UP) - 1.0) < 0.0005, "level")
	var weight := 0.0
	for spring in _springs_of(body):
		weight += spring.get_spring_force()
		_check(absf(spring.get_compression() - GRAVITY / (4.0 * 20.0)) < 0.02, "each spring is squeezed the same (%.3f m)" % spring.get_compression())
	_check(absf(weight - body.mass * GRAVITY) < body.mass * GRAVITY * 0.02, "and together they carry its weight (%.0f of %.0f N)" % [weight, body.mass * GRAVITY])
	var floor_gap := body.global_position.y - BODY_SIZE.y * 0.5
	_check(floor_gap > 0.5, "the body itself never touches the floor (%.2f m clear)" % floor_gap)
	var spring := _springs_of(body)[0]
	_check(absf(spring.get_length() - STANDING_HEIGHT) < 0.02 and absf(spring.get_full_length() - REACH) < 0.0001, "a spring knows how long it is (%.3f of %.2f m)" % [spring.get_length(), spring.get_full_length()])
	_check(spring.get_axis().is_equal_approx(Vector3.DOWN) and spring.get_contact_normal().is_equal_approx(Vector3.UP), "and which way it points, and which way the ground faces")
	_check(absf(spring.get_contact_point().y) < 0.001, "and where it touches")


func _test_any_mass() -> void:
	var light := _body(Vector3(-4.0, 4.0, 0.0), 4, 100.0)
	var heavy := _body(Vector3(4.0, 4.0, 0.0), 4, 50000.0)
	await _frames(300)
	_check(absf(light.global_position.y - heavy.global_position.y) < 0.01, "a light body and a heavy one settle at the same height (%.3f and %.3f)" % [light.global_position.y, heavy.global_position.y])


func _test_stiffness() -> void:
	var soft := _body(Vector3(-4.0, 4.0, 0.0), 4)
	var stiff := _body(Vector3(4.0, 4.0, 0.0), 4)
	for spring in _springs_of(stiff):
		spring.strength = 40.0
	await _frames(300)
	_check(absf(stiff.global_position.y - (REACH - GRAVITY / 160.0)) < 0.02, "twice the strength sinks half as far (%.3f m up)" % stiff.global_position.y)
	_check(stiff.global_position.y > soft.global_position.y + 0.05, "so the stiffer one stands higher")
	var weak := _body(Vector3(12.0, 4.0, 0.0), 4)
	for spring in _springs_of(weak):
		spring.strength = 0.0
	await _frames(240)
	_check(weak.global_position.y < 0.3, "with no strength it falls onto the floor (%.2f)" % weak.global_position.y)


func _test_damping() -> void:
	# Both are dropped from the same height; the one without a damper bounces on, the other settles.
	var damped := _body(Vector3(-5.0, 1.45, 0.0), 4)
	var loose := _body(Vector3(5.0, 1.45, 0.0), 4)
	for spring in _springs_of(damped):
		spring.dampening = 0.5
	for spring in _springs_of(loose):
		spring.dampening = 0.0
	await _frames(180)
	var damped_low := 99.0
	var damped_high := -99.0
	var loose_low := 99.0
	var loose_high := -99.0
	for frame in 90:
		await _frames(1)
		damped_low = minf(damped_low, damped.global_position.y)
		damped_high = maxf(damped_high, damped.global_position.y)
		loose_low = minf(loose_low, loose.global_position.y)
		loose_high = maxf(loose_high, loose.global_position.y)
	_check(loose_high - loose_low > 0.1, "with no damping the body is still bouncing three seconds later (%.3f m of travel)" % (loose_high - loose_low))
	_check(damped_high - damped_low < 0.005, "damped, it has settled by then (%.4f m of travel)" % (damped_high - damped_low))
	_check(absf(damped.global_position.y - STANDING_HEIGHT) < 0.02, "at the height it should stand (%.3f)" % damped.global_position.y)


func _test_disabled() -> void:
	var body := _body(Vector3(0.0, 4.0, 0.0), 4)
	await _frames(240)
	var standing := body.global_position.y
	for spring in _springs_of(body):
		spring.enabled = false
	await _frames(120)
	_check(body.global_position.y < standing - 0.4 and body.global_position.y < 0.3, "turn the springs off and the body drops to the floor (%.2f to %.2f)" % [standing, body.global_position.y])
	_check(not _springs_of(body)[0].is_touching() and _springs_of(body)[0].get_spring_force() == 0.0, "and they report nothing")
	for spring in _springs_of(body):
		spring.enabled = true
	await _frames(240)
	_check(absf(body.global_position.y - standing) < 0.05, "turn them back on and it is lifted back up (%.3f)" % body.global_position.y)


func _test_reach() -> void:
	# Nothing below within reach means no force at all.
	var body := _body(Vector3(0.0, 4.0, 0.0), 4)
	await _frames(30)
	var fall := body.linear_velocity.y
	_check(absf(fall - (-GRAVITY * 0.5)) < 0.8, "out of reach of the ground the body falls freely (%.1f m/s after half a second)" % fall)
	var spring := _springs_of(body)[0]
	_check(not spring.is_touching() and spring.get_spring_force() == 0.0 and spring.get_compression() == 0.0, "and nothing is touching")
	await _frames(40)
	_check(spring.is_touching(), "it touches when the ground comes within reach")


func _test_never_pulls() -> void:
	var body := _body(Vector3(0.0, 1.2, 0.0), 4)
	await _frames(240)
	# Thrown upward away from the ground while still touching: the damper alone would pull it back.
	body.linear_velocity = Vector3(0.0, 6.0, 0.0)
	var lowest_force := INF
	var peak := 0.0
	for frame in 120:
		await _frames(1)
		for spring in _springs_of(body):
			lowest_force = minf(lowest_force, spring.get_spring_force())
		peak = maxf(peak, body.global_position.y)
	_check(lowest_force >= 0.0, "the spring never pulls (lowest force %.0f N)" % lowest_force)
	_check(peak > REACH + 0.4, "a body thrown up leaves the ground and is not held back (%.2f m)" % peak)


func _test_extension() -> void:
	var body := _body(Vector3(0.0, 1.2, 0.0), 4)
	await _frames(240)
	var full := body.global_position.y
	for spring in _springs_of(body):
		spring.extension = 0.5
	await _frames(240)
	# Half the reach, and the springs still squeeze 0.2 m.
	_check(absf(body.global_position.y - (REACH * 0.5 - GRAVITY / 80.0)) < 0.03, "half pulled in, it stands lower (%.3f, was %.3f)" % [body.global_position.y, full])
	for spring in _springs_of(body):
		spring.extension = 0.0
	await _frames(120)
	_check(body.global_position.y < 0.3, "pulled all the way in, the springs do nothing and it drops (%.2f)" % body.global_position.y)
	_check(not _springs_of(body)[0].is_touching(), "and touch nothing")
	for spring in _springs_of(body):
		spring.extension = 1.0
	await _frames(240)
	_check(absf(body.global_position.y - full) < 0.03, "put back out, it is lifted again (%.3f)" % body.global_position.y)


func _test_moving_parts() -> void:
	var body := _body(Vector3(0.0, 1.2, 0.0), 4)
	var spring := _springs_of(body)[0]
	# Wherever a part is put along the ray, it ends up at the point of contact.
	var wheel := MeshInstance3D.new()
	spring.add_child(wheel)
	var hub := MeshInstance3D.new()
	hub.position = Vector3(0.3, -0.2, 0.1)
	spring.add_child(hub)
	var leg := Node3D.new()
	leg.position = Vector3(0.0, -0.4, 0.0)
	spring.add_child(leg)
	var foot := MeshInstance3D.new()
	foot.position = Vector3(0.0, 0.5, 0.0)
	leg.add_child(foot)
	var elsewhere := Node3D.new()
	elsewhere.position = Vector3(0.0, -REACH, 1.0)
	body.add_child(elsewhere)
	# The spring has to be told about parts added after it was ready.
	spring.call("_collect_parts")
	await _frames(2)
	_check(not spring.is_touching(), "in the air the spring touches nothing")
	_check(absf(wheel.global_position.y - (spring.global_position.y - REACH)) < 0.01, "so the wheel hangs at the end of the reach, wherever it was put (%.3f)" % wheel.global_position.y)
	await _frames(240)
	var ground := 0.0
	_check(spring.is_touching(), "on the ground the spring is squeezed")
	_check(absf(wheel.global_position.y - ground) < 0.01, "and the wheel sits on the ground, however much (%.4f)" % wheel.global_position.y)
	_check(absf(wheel.global_position.x - spring.global_position.x) < 0.001 and absf(wheel.global_position.z - spring.global_position.z) < 0.001, "straight along the ray, not sideways")
	_check(absf(hub.global_position.y - ground) < 0.01 and absf(hub.global_position.x - (spring.global_position.x + 0.3)) < 0.001 and absf(hub.global_position.z - (spring.global_position.z + 0.1)) < 0.001, "a part put to one side stays to that side (%s)" % str(hub.global_position - spring.global_position))
	_check(absf(leg.global_position.y - ground) < 0.01 and absf(foot.global_position.y - (ground + 0.5)) < 0.01, "what hangs from a moved part goes with it, keeping its place (%.3f)" % foot.global_position.y)

	spring.moved_offset = Vector3(0.0, 0.3, 0.0)
	await _frames(2)
	_check(absf(wheel.global_position.y - 0.3) < 0.01, "an offset lifts the parts off the ground (%.3f)" % wheel.global_position.y)
	spring.moved_offset = Vector3.ZERO

	spring.moved_node = elsewhere
	spring.call("_collect_parts")
	await _frames(2)
	_check(absf(elsewhere.global_position.y - ground) < 0.01, "a node chosen to be moved is moved instead, from wherever it is (%.3f)" % elsewhere.global_position.y)
	_check(absf(elsewhere.global_position.z - (body.global_position.z + 1.0)) < 0.001 and absf(elsewhere.global_position.x - body.global_position.x) < 0.001, "and stays where it was across the ray")
	spring.moved_node = null
	spring.call("_collect_parts")

	spring.extension = 0.0
	await _frames(2)
	_check(absf(wheel.global_position.y - spring.global_position.y) < 0.03, "pulled all the way in, the wheel is up at the spring's mount (%.3f)" % wheel.global_position.y)
	spring.extension = 0.5
	await _frames(2)
	_check(absf(wheel.global_position.y - (spring.global_position.y - REACH * 0.5)) < 0.03 and spring.get_length() > 0.0, "and halfway in, it is halfway up (%.3f)" % wheel.global_position.y)


func _test_grip() -> void:
	var ice := _body(Vector3(-6.0, 1.2, -10.0), 4)
	var stuck := _body(Vector3(6.0, 1.2, -10.0), 4)
	for spring in _springs_of(stuck):
		spring.grip = 1.0
	await _frames(240)
	ice.linear_velocity = Vector3(0.0, 0.0, 5.0)
	stuck.linear_velocity = Vector3(0.0, 0.0, 5.0)
	var start_z := stuck.global_position.z
	await _frames(240)
	_check(ice.linear_velocity.z > 4.9, "with no grip a body keeps sliding (%.2f m/s)" % ice.linear_velocity.z)
	_check(stuck.linear_velocity.length() < 0.05, "with grip it is stopped (%.3f m/s)" % stuck.linear_velocity.length())
	var skid := stuck.global_position.z - start_z
	_check(skid > 0.5 and skid < 2.6, "in about the distance friction says, v squared over 2 mu g, which is 0.8 m (%.2f m)" % skid)
	_check(absf(stuck.global_position.y - STANDING_HEIGHT) < 0.03, "without sinking or rising while it does (%.3f)" % stuck.global_position.y)


func _test_pushes_back() -> void:
	# Ground that can move is pushed down by the weight standing on it. It has no gravity of its own,
	# being on the World layer, which the field does not pull.
	var ground := RigidBody3D.new()
	ground.collision_layer = PhysicsLayers.WORLD
	ground.collision_mask = 0
	ground.mass = 400.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.5, 8.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(30.0, 0.0, 0.0)
	_world.add_child(ground)
	_body(Vector3(30.0, 1.2, 0.0), 4, 1000.0)
	await _frames(30)
	_check(ground.linear_velocity.y < -1.0, "a loose floor is pushed down by what stands on it (%.2f m/s)" % ground.linear_velocity.y)
	_check(absf(ground.linear_velocity.x) < 0.05 and absf(ground.linear_velocity.z) < 0.05, "straight down")


func _test_signal() -> void:
	var body := _body(Vector3(0.0, 3.0, 0.0), 4)
	var spring := _springs_of(body)[0]
	var changes: Array[bool] = []
	spring.contact_changed.connect(func(touching: bool) -> void: changes.append(touching))
	await _frames(180)
	_check(changes.size() >= 1 and changes[0], "it says when it lands")
	var count := changes.size()
	body.linear_velocity = Vector3(0.0, 12.0, 0.0)
	await _frames(40)
	_check(changes.size() > count and not changes.back() and not spring.is_touching(), "and when it leaves the ground again")


func _test_tilted() -> void:
	# Springs on one side only hold that side up: the body tips over onto the other.
	var body := _body(Vector3(0.0, 1.0, 0.0), 0)
	_spring(body, Vector3(-0.9, 0.0, 1.8))
	_spring(body, Vector3(-0.9, 0.0, -1.8))
	await _frames(240)
	_check(body.global_basis.y.x > 0.1, "a body held up on one side only leans over to the other (tilt %.2f)" % body.global_basis.y.x)
	_check(body.global_position.y < 0.9, "and sags on that side")


func _test_hard_landing() -> void:
	var body := _body(Vector3(0.0, 6.0, 0.0), 4)
	var lowest := 99.0
	for frame in 420:
		await _frames(1)
		lowest = minf(lowest, body.global_position.y)
	_check(lowest > BODY_SIZE.y * 0.5, "dropped from 5 m the springs take the landing before the body reaches the floor (lowest %.3f)" % lowest)
	_check(absf(body.global_position.y - STANDING_HEIGHT) < 0.03 and body.linear_velocity.length() < 0.02, "and it settles (%.3f m, %.4f m/s)" % [body.global_position.y, body.linear_velocity.length()])
	_check(absf(body.global_position.x) < 0.5 and absf(body.global_position.z) < 0.5, "without wandering off")


## How long the springs take, which is about what every ship and car with them pays each tick.
func _test_cost() -> void:
	for index in 25:
		_body(Vector3(float(index % 5) * 6.0 - 12.0, 1.0, float(index / 5) * 6.0 - 12.0), 4)
	await _frames(120)
	var started := Time.get_ticks_usec()
	await _frames(240)
	var per_tick := float(Time.get_ticks_usec() - started) / 240.0
	print("       100 springs on 25 bodies: %.0f us per tick all told, physics included" % per_tick)
	_check(per_tick < 20000.0, "that is cheap enough")


# --- Helpers -----------------------------------------------------------------

func _begin_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	InGameUIHandler.is_ui_open = false
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200.0, 2.0, 200.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	_world.add_child(floor_body)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300.0, 300.0, 300.0)
	field_shape.shape = field_box
	field.add_child(field_shape)
	_world.add_child(field)


func _end_world() -> void:
	_world.free()
	InGameUIHandler.is_ui_open = true


## A box that gravity pulls and the floor stops, with [param springs] springs at its corners (0, or 4
## for all four).
func _body(at: Vector3, springs: int, mass := 1000.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = PhysicsLayers.VEHICLES
	body.collision_mask = PhysicsLayers.WORLD
	body.mass = mass
	body.can_sleep = false
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_world.add_child(body)
	if springs == 4:
		for corner in [Vector3(-0.9, 0.0, -1.8), Vector3(0.9, 0.0, -1.8), Vector3(-0.9, 0.0, 1.8), Vector3(0.9, 0.0, 1.8)]:
			_spring(body, corner)
	return body


func _spring(body: RigidBody3D, at: Vector3) -> Suspension3D:
	var spring := Suspension3D.new()
	spring.target_position = Vector3(0.0, -REACH, 0.0)
	spring.position = at
	body.add_child(spring)
	return spring


func _springs_of(body: RigidBody3D) -> Array[Suspension3D]:
	var found: Array[Suspension3D] = []
	for child in body.get_children():
		if child is Suspension3D:
			found.append(child as Suspension3D)
	return found


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
