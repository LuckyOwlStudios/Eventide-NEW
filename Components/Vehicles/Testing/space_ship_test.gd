extends Node
## Checks that a SpaceShip3D is a real physical body that turns to face its camera rig: it has
## weight and keeps its velocity, spins when it crashes and then swings back, and only follows
## the rig while someone is flying it.
##
## godot --headless --fixed-fps 60 --path . res://Components/Vehicles/Testing/SpaceShipTest.tscn

const RIG_SCENE := preload("res://Components/Camera/CameraRig.tscn")
const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const TURRET_SCENE := preload("res://Testing/Turret/Turret3D.tscn")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

var _failures := 0
var _world: Node3D


func _ready() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	InGameUIHandler.is_ui_open = false

	_test_defaults()
	await _test_only_follows_when_flown()
	await _test_turns_to_the_rig()
	await _test_flying_relative_to_the_camera()
	await _test_engine_and_power()
	await _test_roll_follows_too()
	await _test_velocity_and_weight()
	await _test_crash()
	await _test_gravity_field()
	await _test_mule()
	await _test_walking_inside_the_mule()
	await _test_driving_the_mule()
	await _test_piloting_the_mule()
	await _test_leaving_mid_turn()
	await _test_turret_is_separate()

	_world.free()
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Space ship tests passed.")
	else:
		print("Space ship tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_defaults() -> void:
	print("A vehicle is a rigid body with sensible defaults")
	var ship := _ship(false)
	_check(ship is RigidBody3D, "Vehicle3D is a RigidBody3D")
	_check(ship.collision_layer == PhysicsLayers.VEHICLES, "it is on the Vehicles layer")
	_check(ship.collision_mask == PhysicsLayers.VEHICLE_MASK, "and collides with what vehicles should")
	_check(ship.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE and is_zero_approx(ship.linear_damp), "nothing slows it down by itself")
	_check(not ship.can_sleep, "and it never falls asleep")
	_check(ship.camera_rig != null and ship.vehicle_camera == ship.camera_rig.camera, "it found its camera rig and uses its camera")
	ship.free()


func _test_only_follows_when_flown() -> void:
	print("Only follows the rig while flown")
	var ship := _ship(false)
	ship.angular_velocity = Vector3(0.0, 0.3, 0.0)
	ship.camera_rig.add_look_input(deg_to_rad(120.0), 0.0)
	await _frames(120)
	_check(ship.angular_velocity.is_equal_approx(Vector3(0.0, 0.3, 0.0)), "an empty ship just keeps spinning")
	_check(ship.get_aim_error_degrees() > 10.0, "and does not chase the rig")
	ship.free()


func _test_turns_to_the_rig() -> void:
	print("Turns to face the rig, heavily")
	var ship := _ship(true)
	await _frames(2)
	_check(ship.get_aim_error_degrees() < 0.5, "starts out facing the rig")
	ship.camera_rig.add_look_input(deg_to_rad(90.0), 0.0)
	_check(ship.get_aim_error_degrees() > 80.0, "turning the rig puts the ship 90 degrees off")

	var fastest := 0.0
	var sharpest := 0.0
	var spin_after_a_tenth_of_a_second := 0.0
	var previous_spin := Vector3.ZERO
	for frame in 360:
		await _frames(1)
		fastest = maxf(fastest, ship.angular_velocity.length())
		sharpest = maxf(sharpest, (ship.angular_velocity - previous_spin).length() * 60.0)
		previous_spin = ship.angular_velocity
		if frame == 5:
			spin_after_a_tenth_of_a_second = ship.angular_velocity.length()
	_check(ship.get_aim_error_degrees() < 1.0, "ends up facing it (%.2f degrees off)" % ship.get_aim_error_degrees())
	_check(rad_to_deg(fastest) <= ship.max_turn_rate_degrees * 1.02, "never turns faster than its limit (%.1f of %.0f degrees a second)" % [rad_to_deg(fastest), ship.max_turn_rate_degrees])
	_check(rad_to_deg(fastest) > ship.max_turn_rate_degrees * 0.9, "but does reach it on a big turn")
	_check(rad_to_deg(sharpest) <= ship.turn_acceleration_degrees * 1.05, "and speeds up no faster than its thrusters (%.1f of %.0f degrees a second squared)" % [rad_to_deg(sharpest), ship.turn_acceleration_degrees])
	_check(rad_to_deg(spin_after_a_tenth_of_a_second) < ship.turn_acceleration_degrees * 0.1 * 1.3, "so it starts turning slowly")
	_check(ship.angular_velocity.length() < 0.01, "and comes to rest on the target without wobbling")
	ship.free()


func _test_flying_relative_to_the_camera() -> void:
	print("Flying: WASD, Space, Ctrl, Shift and Alt, all relative to the camera")
	var ship := _ship(true)
	await _frames(2)

	# The camera looks left, and the ship has only just started to turn that way.
	ship.camera_rig.add_look_input(deg_to_rad(90.0), 0.0)
	var aim_forward := ship.camera_rig.get_aim_forward()
	Input.action_press(&"move_forward")
	await _frames(30)
	_check(ship.get_aim_error_degrees() > 20.0, "the ship is still turning toward the camera")
	_check(ship.linear_velocity.normalized().dot(aim_forward) > 0.99, "but forward already goes where the camera looks")
	_check(absf(ship.linear_velocity.length() - ship.thrust_acceleration * 0.5) < 0.6, "gaining speed at the thrusters' pace (%.1f m/s after half a second)" % ship.linear_velocity.length())
	await _frames(240)
	_check(absf(ship.linear_velocity.length() - ship.max_speed) < 0.5, "up to its top speed (%.1f m/s)" % ship.linear_velocity.length())

	Input.action_press(&"move_right")
	await _frames(120)
	_check(absf(ship.linear_velocity.length() - ship.max_speed) < 0.5, "going diagonally is no faster (%.1f m/s)" % ship.linear_velocity.length())
	var right := ship.camera_rig.get_aim_basis().x
	_check(ship.linear_velocity.normalized().dot((aim_forward + right).normalized()) > 0.99, "and goes between the camera's forward and right")
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	await _frames(300)
	_check(ship.linear_velocity.length() < 0.1, "letting go brings the ship to a stop (%.2f m/s)" % ship.linear_velocity.length())

	Input.action_press(&"move_back")
	Input.action_press(&"sprint")
	await _frames(300)
	_check(absf(ship.linear_velocity.length() - ship.max_speed * ship.boost_multiplier) < 1.0, "Shift boosts the top speed (%.1f m/s)" % ship.linear_velocity.length())
	_check(ship.linear_velocity.normalized().dot(-aim_forward) > 0.99, "and back goes away from where the camera looks")
	Input.action_release(&"move_back")
	Input.action_release(&"sprint")
	await _frames(600)

	Input.action_press(&"move_forward")
	Input.action_press(&"stroll")
	await _frames(240)
	_check(absf(ship.linear_velocity.length() - ship.max_speed * ship.precision_multiplier) < 0.4, "Alt moves precisely, slowly (%.1f m/s)" % ship.linear_velocity.length())
	Input.action_release(&"move_forward")
	Input.action_release(&"stroll")
	await _frames(300)

	# Up and down follow the camera's up, so a camera rolled over to the right has up pointing right.
	ship.camera_rig.add_look_input(0.0, 0.0, deg_to_rad(90.0))
	var camera_up := ship.camera_rig.get_aim_basis().y
	Input.action_press(&"jump")
	await _frames(120)
	_check(ship.linear_velocity.normalized().dot(camera_up) > 0.99, "Space goes along the camera's up, even rolled over")
	Input.action_release(&"jump")
	await _frames(300)
	Input.action_press(&"crouch")
	await _frames(120)
	_check(ship.linear_velocity.normalized().dot(-camera_up) > 0.99, "and Ctrl along its down")
	Input.action_release(&"crouch")
	ship.free()

	var heavy := _ship(true)
	var light := _ship(true, Vector3(200.0, 0.0, 0.0))
	light.mass = heavy.mass * 0.25
	Input.action_press(&"move_forward")
	await _frames(60)
	_check(absf(heavy.linear_velocity.length() - light.linear_velocity.length()) < 0.3, "a light ship and a heavy one speed up equally (%.1f and %.1f m/s)" % [heavy.linear_velocity.length(), light.linear_velocity.length()])
	InGameUIHandler.is_ui_open = true
	await _frames(300)
	_check(heavy.linear_velocity.length() < 0.1, "with a menu open the keys do nothing, and the ship stops")
	InGameUIHandler.is_ui_open = false
	Input.action_release(&"move_forward")
	light.free()
	heavy.free()

	var empty := _ship(false)
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	_check(empty.linear_velocity.length() < 0.001, "an empty ship cannot be flown")
	empty.free()


func _test_engine_and_power() -> void:
	print("Starting and stopping the engines, and the power")
	var ship := _ship(true)
	ship.engine_state = false
	ship.power_state = true
	var engine_changes: Array[bool] = []
	var power_changes: Array[bool] = []
	ship.engine_state_changed.connect(func(on: bool) -> void: engine_changes.append(on))
	ship.power_state_changed.connect(func(on: bool) -> void: power_changes.append(on))
	await _frames(2)

	Input.action_press(&"jump")
	await _frames(170)
	_check(not ship.engine_state, "holding Space for almost 3 seconds does not start the engines")
	_check(ship.engine_hold_progress > 0.9 and ship.engine_hold_progress < 1.0, "but the hold is nearly there (%.2f)" % ship.engine_hold_progress)
	Input.action_release(&"jump")
	await _frames(2)
	_check(ship.engine_hold_progress == 0.0, "letting go starts the hold over")
	Input.action_press(&"jump")
	await _frames(120)
	Input.action_release(&"jump")
	await _frames(2)
	Input.action_press(&"jump")
	await _frames(120)
	_check(not ship.engine_state, "two short holds do not add up")
	Input.action_release(&"jump")

	Input.action_press(&"jump")
	await _frames(190)
	_check(ship.engine_state and engine_changes == [true], "holding Space for 3 seconds starts them")
	await _frames(90)
	_check(ship.linear_velocity.length() < 0.01, "and keeping Space held does not launch the ship")
	Input.action_release(&"jump")
	await _frames(2)
	Input.action_press(&"jump")
	await _frames(60)
	_check(ship.linear_velocity.dot(ship.camera_rig.get_aim_basis().y) > 5.0, "pressing it again afterwards flies up")
	Input.action_release(&"jump")
	await _frames(300)

	Input.action_press(&"engine_off")
	await _frames(40)
	_check(ship.engine_state, "a short press of the stop key does nothing")
	Input.action_release(&"engine_off")
	await _frames(2)
	Input.action_press(&"engine_off")
	await _frames(70)
	Input.action_release(&"engine_off")
	_check(not ship.engine_state and engine_changes == [true, false], "holding it for a second shuts them down")
	_check(ship.power_state, "which leaves the power on")

	ship.power_state = false
	Input.action_press(&"jump")
	await _frames(240)
	Input.action_release(&"jump")
	_check(not ship.engine_state, "without power the engines will not start")
	ship.power_state = true
	Input.action_press(&"jump")
	await _frames(190)
	Input.action_release(&"jump")
	_check(ship.engine_state, "with power again they do")
	ship.power_state = false
	_check(not ship.engine_state and power_changes == [false, true, false], "and cutting the power stops them too")
	ship.free()

	var empty := _ship(false)
	empty.engine_state = false
	empty.power_state = true
	Input.action_press(&"jump")
	await _frames(240)
	Input.action_release(&"jump")
	_check(not empty.engine_state, "with nobody in the seat the keys do nothing")
	empty.free()

	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	await _frames(2)
	_check(mule.power_state and not mule.engine_state, "the Mule starts with its power on and its engines off")
	var power_switch := mule.find_child("PowerSwitch", true, false) as PowerSwitch3D
	_check(power_switch != null and power_switch.vehicle == mule, "and has a power switch that controls the Mule")
	_check(not power_switch._can_interact_option(null, 0) and power_switch._can_interact_option(null, 1), "which offers to turn the power off while it is on")
	mule.engine_state = true
	_check(power_switch._interact_option(null, 1) and not mule.power_state and not mule.engine_state, "switching it off cuts the power")
	_check(power_switch._can_interact_option(null, 0) and not power_switch._can_interact_option(null, 1), "and then offers to turn it on")
	power_switch._interact_option(null, 0)
	_check(mule.power_state and not mule.engine_state, "turning it back on leaves the engines off")
	mule.free()


func _test_roll_follows_too() -> void:
	print("Follows the rig's roll as well as its direction")
	var ship := _ship(true)
	await _frames(2)
	ship.camera_rig.add_look_input(0.0, 0.0, deg_to_rad(60.0))
	await _frames(360)
	_check(ship.get_aim_error_degrees() < 1.0, "ends up facing it (%.2f degrees off)" % ship.get_aim_error_degrees())
	_check(ship.global_basis.y.x > 0.85, "banked over to the right")
	_check(ship.global_basis.z.is_equal_approx(ship.camera_rig.get_aim_basis().z) or ship.get_aim_error_degrees() < 1.0, "and still pointing the same way")
	ship.free()


func _test_velocity_and_weight() -> void:
	print("Velocity and weight")
	var ship := _ship(false)
	ship.linear_velocity = Vector3(0.0, 0.0, -12.0)
	await _frames(120)
	_check(absf(ship.global_position.z - (-24.0)) < 0.6, "it keeps flying at the speed it had (%.1f m in 2 s)" % -ship.global_position.z)
	var before := ship.linear_velocity
	for frame in 60:
		ship.apply_central_force(Vector3(0.0, 0.0, -2.0 * ship.mass))
		await _frames(1)
	_check(absf((ship.linear_velocity - before).z - (-2.0)) < 0.1, "a push of 2 m/s2 worth of force speeds it up by 2 m/s in a second")
	var light := _ship(false, Vector3(100.0, 0.0, 0.0))
	light.mass = ship.mass * 0.25
	for frame in 60:
		light.apply_central_force(Vector3(0.0, 0.0, -2.0 * ship.mass))
		await _frames(1)
	_check(light.linear_velocity.z < -7.5, "the same push moves a lighter ship four times as much (%.1f m/s)" % -light.linear_velocity.z)
	light.free()
	ship.free()


func _test_crash() -> void:
	print("Crashing")
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(19.5, 10.0, 1.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(10.25, 0.0, -12.0)
	_world.add_child(wall)

	# Nobody flying it: the hit alone decides what happens.
	var drifting := _ship(false)
	drifting.linear_velocity = Vector3(0.0, 0.0, -20.0)
	var drifting_spin := 0.0
	for frame in 120:
		await _frames(1)
		drifting_spin = maxf(drifting_spin, drifting.angular_velocity.length())
	_check(drifting.linear_velocity.z > -2.0, "it stopped at the wall instead of passing through (%.1f m/s)" % drifting.linear_velocity.z)
	_check(drifting_spin > 0.1, "hitting the wall off-center spun it (%.2f rad/s)" % drifting_spin)
	drifting.free()

	# Flown: the thrusters fight the hit and then bring it back.
	var ship := _ship(true)
	ship.linear_velocity = Vector3(0.0, 0.0, -20.0)
	await _frames(2)
	var most_off := 0.0
	for frame in 120:
		await _frames(1)
		most_off = maxf(most_off, ship.get_aim_error_degrees())
	_check(most_off > 3.0, "and it is knocked off its heading even while flown (%.1f degrees)" % most_off)
	await _frames(480)
	_check(ship.get_aim_error_degrees() < 1.5, "then swings back to face the rig (%.2f degrees off)" % ship.get_aim_error_degrees())
	ship.free()
	wall.free()


func _test_gravity_field() -> void:
	print("Gravity: the engine decides whether the ship falls")
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(200.0, 200.0, 200.0)
	field_shape.shape = field_box
	field.add_child(field_shape)
	_world.add_child(field)

	var dead := _ship(false)
	dead.engine_state = false
	await _frames(60)
	_check(absf(dead.linear_velocity.y - (-16.0)) < 2.0, "with the engine off it falls at the field's strength (%.1f m/s after a second)" % dead.linear_velocity.y)
	await _frames(2)
	_check(not dead.camera_rig.is_weightless(), "and its camera rig feels the gravity")
	dead.free()

	var driven_dead := _ship(true)
	driven_dead.engine_state = false
	driven_dead.camera_rig.add_look_input(deg_to_rad(60.0), 0.0)
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	_check(driven_dead.linear_velocity.y < -10.0, "even with a driver, an engine that is off means it falls")
	_check(Vector2(driven_dead.linear_velocity.x, driven_dead.linear_velocity.z).length() < 0.1, "it cannot thrust")
	_check(driven_dead.get_aim_error_degrees() > 30.0, "or turn to follow the camera")
	driven_dead.free()

	var hovering := _ship(false)
	hovering.rotation = Vector3(0.0, 0.0, deg_to_rad(50.0))
	await _frames(240)
	_check(absf(hovering.linear_velocity.y) < 0.05 and absf(hovering.global_position.y) < 0.05, "with the engine on it does not fall (%.2f m moved)" % hovering.global_position.y)
	_check(hovering.global_basis.y.dot(Vector3.UP) > 0.999, "and an empty ship rights itself against the gravity")
	_check(not hovering.camera_rig.is_weightless(), "while its camera rig still knows there is gravity")
	hovering.engine_state = false
	await _frames(60)
	_check(hovering.linear_velocity.y < -10.0, "switch the engine off and it drops")
	hovering.free()

	var flown := _ship(true)
	flown.camera_rig.add_look_input(deg_to_rad(90.0), deg_to_rad(20.0))
	await _frames(360)
	_check(flown.get_aim_error_degrees() < 1.5 and absf(flown.global_position.y) < 0.05, "a flown ship follows the camera instead, and still does not fall (%.2f degrees off)" % flown.get_aim_error_degrees())
	field.free()
	flown.free()


func _test_mule() -> void:
	print("The Mule")
	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	await _frames(2)
	_check(mule is RigidBody3D and mule is SpaceShip3D, "is a space ship that is a rigid body")
	_check(mule.camera_rig != null, "has its camera rig")
	var hull := mule.get_node("Hull") as CollisionShape3D
	var hull_box := hull.shape as BoxShape3D
	# The scene is saved with however many segments it was last left with.
	mule.segments = 1
	await _frames(2)
	_check(is_equal_approx(hull_box.size.z, 12.0), "has a hull as long as the ship (%.1f)" % hull_box.size.z)
	mule.segments = 2
	await _frames(2)
	_check(is_equal_approx(hull_box.size.z, 16.0), "and the hull grows with each cargo segment (%.1f)" % hull_box.size.z)
	var hull_parts := 0
	for body in mule.find_children("*", "CSGCombiner3D", true, false):
		if (body as CSGCombiner3D).use_collision:
			hull_parts += 1
			_check((body as CSGCombiner3D).collision_layer == PhysicsLayers.VEHICLE_INTERIORS, "%s does not collide with its own ship" % body.name)
	# An editor re-save once left a wall on World; the ship must not fight it.

	var healed := MULE_SCENE.instantiate() as Mule
	(healed.find_child("MuleBowModel", true, false) as CSGCombiner3D).collision_layer = PhysicsLayers.WORLD
	_world.add_child(healed)
	healed.position = Vector3(100.0, 0.0, 0.0)
	await _frames(120)
	_check((healed.find_child("MuleBowModel", true, false) as CSGCombiner3D).collision_layer == PhysicsLayers.VEHICLE_INTERIORS, "a wall left on the World layer is moved off it")
	_check(healed.global_position.distance_to(Vector3(100.0, 0.0, 0.0)) < 0.01, "so the ship does not throw itself around")
	healed.free()
	_check(hull_parts > 0, "found its collision parts (%d)" % hull_parts)
	var misplaced := 0
	for node in mule.find_children("*", "InteractableObject3D", true, false):
		if (node as Area3D).collision_layer != PhysicsLayers.INTERACTABLES:
			misplaced += 1
			print("       ", node.get_path(), " is on layer ", (node as Area3D).collision_layer)
	_check(misplaced == 0, "every button, seat and hatch is on the Interactables layer")
	mule.segments = 1
	await _frames(2)
	var resting_at := mule.global_position
	await _frames(240)
	_check(mule.global_position.distance_to(resting_at) < 0.01 and mule.linear_velocity.length() < 0.01, "left alone it stays exactly where it is")
	mule.free()


func _test_walking_inside_the_mule() -> void:
	print("Walking inside the Mule")
	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.1, 1.5)
	_world.add_child(player)
	await _frames(90)
	_check(player.global_position.distance_to(Vector3(0.0, 0.0, 1.5)) < 0.5, "someone put in the cargo bay stays there and stands on the floor (%s)" % player.global_position.snapped(Vector3.ONE * 0.01))
	Input.action_press(&"move_forward")
	await _frames(90)
	Input.action_release(&"move_forward")
	_check(player.global_position.z < -3.0, "and can walk along the bay and into the bow (z = %.2f, from 1.5)" % player.global_position.z)
	_check(absf(player.global_position.y) < 0.5 and absf(player.global_position.x) < 2.0, "inside the walls")
	player.free()
	mule.free()


func _test_driving_the_mule() -> void:
	print("Driving the Mule")
	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	await _frames(2)
	# An editor re-save once left a stray 0 on one direction, and the ship would not go that way.
	for multiplier in [mule.forward_direction_multiplier, mule.backward_direction_multiplier, mule.left_direction_multiplier, mule.right_direction_multiplier, mule.up_direction_multiplier, mule.down_direction_multiplier]:
		_check(multiplier > 0.0, "every direction is open to the Mule (%.1f)" % multiplier)
	mule.power_state = true
	mule.engine_state = true
	mule.fly_without_pilot = true
	var forward := -mule.camera_rig.get_aim_basis().z
	Input.action_press(&"move_forward")
	await _frames(180)
	Input.action_release(&"move_forward")
	var speed_forward := mule.linear_velocity.dot(forward)
	_check(speed_forward > mule.max_speed * 0.8, "holding forward drives it ahead (%.1f of %.1f m/s)" % [speed_forward, mule.max_speed])
	mule.free()


func _test_piloting_the_mule() -> void:
	print("Piloting the Mule from its seat")
	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	mule.engine_state = true
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.1, -3.0)
	_world.add_child(player)
	await _frames(30)
	var seat := mule.find_child("PilotSeat", true, false) as VehicleSeat3D
	_check(seat != null and seat.vehicle == mule, "the Mule has a pilot seat that controls the Mule")
	var pilot := player.get_node("VehicleController") as VehicleController
	var rig := mule.camera_rig
	_check(not rig.input_enabled and mule.get_aim_error_degrees() < 0.5, "before anyone sits down the rig ignores input")
	rig.add_look_input(deg_to_rad(40.0), 0.0)
	await _frames(60)
	_check(mule.get_aim_error_degrees() > 30.0, "and the empty Mule does not chase it")
	rig.align_to_mount()

	_check(pilot.enter_seat(seat), "the player can take the seat")
	_check(mule.controller == pilot and mule.has_local_control(), "and so controls the Mule")
	_check(rig.input_enabled and mule.vehicle_camera == rig.camera and rig.camera.current, "the rig takes input and its camera is the one used")
	rig.add_look_input(deg_to_rad(50.0), deg_to_rad(10.0))
	await _frames(480)
	_check(mule.get_aim_error_degrees() < 1.5, "the Mule turns to where the pilot looks (%.2f degrees off)" % mule.get_aim_error_degrees())
	_check(absf(mule.global_basis.get_euler().y - deg_to_rad(50.0)) < deg_to_rad(5.0), "toward the left, as asked")
	_check(player.global_position.distance_to(seat.get_seat_transform().origin) < 0.2, "and the pilot is carried round with it")

	_check(pilot.exit_seat(), "the pilot can get up again")
	_check(not rig.input_enabled and not is_instance_valid(mule.controller), "which hands the Mule back")
	player.free()
	mule.free()


func _test_leaving_mid_turn() -> void:
	print("Getting out while the ship is turning")
	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	mule.engine_state = true
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.1, -3.0)
	_world.add_child(player)
	await _frames(30)
	var seat := mule.find_child("PilotSeat", true, false) as VehicleSeat3D
	var pilot := player.get_node("VehicleController") as VehicleController
	mule.linear_velocity = Vector3(0.0, 0.0, -3.0)
	pilot.enter_seat(seat)
	mule.camera_rig.add_look_input(deg_to_rad(120.0), 0.0)
	await _frames(70)
	_check(mule.angular_velocity.length() > 0.3, "the ship is mid-turn when the pilot gets up (%.2f rad/s)" % mule.angular_velocity.length())
	var speed_on_leaving := mule.linear_velocity
	pilot.exit_seat()
	await _frames(1)
	_check(mule.angular_velocity.length() > 0.2, "the thrusters do not stop it dead (a heavy ship slows at its own pace)")
	await _frames(120)
	_check(mule.angular_velocity.length() < 0.001, "but its spin is stopped soon after (%.4f rad/s)" % mule.angular_velocity.length())
	var facing := mule.global_basis
	await _frames(180)
	_check(mule.global_basis.is_equal_approx(facing), "and it stays facing the same way")
	_check(mule.linear_velocity.is_equal_approx(speed_on_leaving), "and the empty ship drifts on at the speed it had when the pilot left")

	# Out in space, a knock is not damped away: the empty ship tumbles on.
	mule.angular_velocity = Vector3(0.0, 0.25, 0.1)
	await _frames(600)
	_check(mule.angular_velocity.is_equal_approx(Vector3(0.0, 0.25, 0.1)), "a hit on an empty ship keeps it tumbling")
	player.free()
	mule.free()


func _test_turret_is_separate() -> void:
	print("A turret is not a vehicle")
	var turret := TURRET_SCENE.instantiate() as Turret3D
	_world.add_child(turret)
	await _frames(2)
	_check(not (turret as Node is Vehicle3D) and not (turret as Node is RigidBody3D), "Turret3D is its own Node3D, not a vehicle")
	var seat := turret.get_node("VehicleSeat") as VehicleSeat3D
	_check(seat.vehicle == turret, "its seat still controls it")
	var pilot := VehicleController.new()
	_check(turret.can_be_controlled_by(pilot), "and it can be taken control of")
	pilot.free()
	turret.free()


# --- Helpers -----------------------------------------------------------------

func _ship(flown: bool, at := Vector3.ZERO) -> SpaceShip3D:
	var ship := SpaceShip3D.new()
	ship.mass = 10000.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 10.0)
	shape.shape = box
	ship.add_child(shape)
	ship.add_child(RIG_SCENE.instantiate())
	ship.engine_state = true
	ship.power_state = true
	ship.fly_without_pilot = flown
	ship.position = at
	_world.add_child(ship)
	return ship


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
