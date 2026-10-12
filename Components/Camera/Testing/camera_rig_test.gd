extends Node
## Checks the camera rig: it follows a vehicle's position without its rotation, looks freely
## while weightless, stays upright and pitch-limited in gravity, swings back from freecam, and
## is dragged along when a turret's arc runs out.
##
## godot --headless --fixed-fps 60 --path . res://Components/Camera/Testing/CameraRigTest.tscn

const RIG_SCENE := preload("res://Components/Camera/CameraRig.tscn")

var _failures := 0
var _world: Node3D


func _ready() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	InGameUIHandler.is_ui_open = false

	await _test_follows_position_not_rotation()
	await _test_weightless_looks_freely()
	await _test_gravity_keeps_upright()
	await _test_gravity_coming_and_going()
	await _test_gravity_direction_changes()
	await _test_freecam()
	await _test_freecam_in_gravity()
	await _test_mount_limits()
	await _test_heading_helpers()
	await _test_controls()
	await _test_vehicle_link()

	_world.free()
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Camera rig tests passed.")
	else:
		print("Camera rig tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_follows_position_not_rotation() -> void:
	print("Follows the vehicle's position, not its rotation")
	var vehicle := _vehicle(Vector3(10.0, 0.0, 0.0))
	vehicle.rotation.y = deg_to_rad(90.0)
	var rig := _rig(vehicle, Vector3(0.0, 2.0, 0.0))
	await _frames(2)
	_check(_near(rig.view.global_position, Vector3(10.0, 2.0, 0.0)), "starts at the mount")
	_check(_near(rig.get_aim_forward(), vehicle.global_basis * Vector3.FORWARD), "starts facing the way the mount points")

	var aim_before := rig.get_aim_basis()
	vehicle.global_position = Vector3(0.0, 0.0, 20.0)
	vehicle.rotation.y = deg_to_rad(200.0)
	vehicle.rotation.x = deg_to_rad(30.0)
	await _frames(2)
	_check(_near(rig.view.global_position, vehicle.global_transform * Vector3(0.0, 2.0, 0.0)), "the camera goes where the mount went")
	_check(rig.get_aim_basis().is_equal_approx(aim_before), "but the aim did not turn with the vehicle")
	_free(vehicle)


func _test_weightless_looks_freely() -> void:
	print("Weightless: every direction, upside down, roll")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	await _frames(2)
	_check(rig.is_weightless(), "no gravity means weightless")

	rig.add_look_input(0.0, deg_to_rad(120.0))
	var aim := rig.get_aim_basis()
	_check(_near(aim.z * -1.0, Vector3(0.0, sin(deg_to_rad(120.0)), -cos(deg_to_rad(120.0)))), "pitch goes past straight up")
	_check(aim.y.y < -0.4, "and the view ends up upside down")

	rig.align_to_mount()
	rig.add_look_input(0.0, deg_to_rad(45.0))
	rig.add_look_input(deg_to_rad(45.0), 0.0)
	_check(_near(rig.get_aim_forward(), Vector3(-0.7071068, 0.5, -0.5)), "yaw turns around the camera's own up, not the world's")

	rig.align_to_mount()
	rig.add_look_input(0.0, 0.0, deg_to_rad(90.0))
	_check(_near(rig.get_aim_basis().y, Vector3.RIGHT), "rolling right banks the view to the right")
	_check(_near(rig.get_aim_forward(), Vector3.FORWARD), "without changing where it looks")

	for turn in 500:
		rig.add_look_input(0.05, 0.03, 0.02)
	_check(rig.get_aim_basis().is_equal_approx(rig.get_aim_basis().orthonormalized()), "the orientation stays clean after a lot of turning")
	_free(vehicle)


func _test_gravity_keeps_upright() -> void:
	print("Gravity: upright, pitch limits")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	rig.orientator.orientation_speed = 0.0
	await _frames(2)

	# Looking somewhere odd while floating, then gravity switches on.
	rig.add_look_input(deg_to_rad(70.0), deg_to_rad(30.0), deg_to_rad(40.0))
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(2)
	var aim := rig.get_aim_basis()
	_check(not rig.is_weightless(), "gravity ends the weightlessness")
	_check(absf(aim.x.y) < 0.001 and aim.y.y > 0.0, "the view is upright, no roll left")
	_check(is_equal_approx(rig.get_aim_forward().y, sin(deg_to_rad(30.0))), "and it still looks 30 degrees up")
	_check(_near(rig.get_up_direction(), Vector3.UP), "up is opposite gravity")

	rig.add_look_input(0.0, deg_to_rad(200.0))
	_check(is_equal_approx(rig.get_aim_forward().y, sin(deg_to_rad(85.0))), "pitch stops at the highest allowed")
	rig.add_look_input(0.0, deg_to_rad(-400.0))
	_check(is_equal_approx(rig.get_aim_forward().y, sin(deg_to_rad(-85.0))), "and at the lowest")

	rig.add_look_input(0.0, deg_to_rad(85.0))
	var level_forward := rig.get_aim_forward()
	rig.add_look_input(deg_to_rad(90.0), 0.0)
	_check(_near(rig.get_aim_forward(), Basis(Vector3.UP, deg_to_rad(90.0)) * level_forward), "yaw turns around the world's up")
	_check(absf(rig.get_aim_basis().x.y) < 0.001, "and keeps the horizon level")

	rig.add_look_input(0.0, 0.0, deg_to_rad(90.0))
	_check(absf(rig.get_aim_basis().x.y) < 0.001, "there is no rolling while gravity holds the view")
	_free(vehicle)


func _test_gravity_coming_and_going() -> void:
	print("Gravity appearing and fading does not jolt the camera")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	rig.orientator.orientation_speed = 0.0
	await _frames(2)

	rig.add_look_input(deg_to_rad(70.0), deg_to_rad(30.0))
	var before := rig.get_aim_forward()
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(2)
	_check(_near(rig.get_aim_forward(), before), "the view is the same the moment gravity starts, when already level")

	rig.add_look_input(deg_to_rad(33.0), deg_to_rad(12.0))
	var in_gravity := rig.get_aim_basis()
	rig.set_gravity(Vector3.ZERO)
	await _frames(2)
	_check(rig.is_weightless(), "gravity going away frees the view")
	_check(rig.get_aim_basis().is_equal_approx(in_gravity), "with no jump")
	rig.add_look_input(0.0, deg_to_rad(100.0))
	_check(rig.get_aim_basis().y.y < 0.0, "and it can go over the top again")

	# Floating while looking straight up, then gravity: the pitch eases back into range.
	rig.align_to_mount()
	rig.add_look_input(0.0, deg_to_rad(89.9))
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(1)
	var pitch_after_one_frame := asin(rig.get_aim_forward().y)
	await _frames(30)
	var settled_pitch := asin(rig.get_aim_forward().y)
	_check(pitch_after_one_frame > deg_to_rad(85.0), "an out-of-range pitch is not snapped in")
	_check(absf(rad_to_deg(settled_pitch) - 85.0) < 0.01, "it eases back to the limit")
	_free(vehicle)


func _test_gravity_direction_changes() -> void:
	print("A change in gravity direction is followed smoothly")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	rig.orientator.orientation_speed = 10.0
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(2)
	rig.add_look_input(0.0, deg_to_rad(20.0))

	# Down is now toward -X, as if walking onto a wall.
	rig.set_gravity(Vector3.LEFT * 9.8)
	await _frames(2)
	var first_step := rig.get_aim_basis().y
	_check(first_step.dot(Vector3.UP) > 0.5, "it does not flip at once")
	await _frames(120)
	_check(_near(rig.view.global_basis.y, Vector3.RIGHT, 0.01), "and ends upright against the new gravity")
	_check(absf(rig.get_aim_basis().x.dot(Vector3.RIGHT)) < 0.01, "with no roll")
	_check(is_equal_approx(asin(rig.get_aim_forward().dot(Vector3.RIGHT)), deg_to_rad(20.0)), "still looking 20 degrees above the new horizon")
	_free(vehicle)


func _test_freecam() -> void:
	print("Freecam")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	var changes: Array[bool] = []
	rig.freecam_changed.connect(func(active: bool) -> void: changes.append(active))
	await _frames(2)

	rig.add_look_input(deg_to_rad(20.0), deg_to_rad(10.0))
	var aim := rig.get_aim_basis()
	Input.action_press(rig.freecam_action)
	await _frames(2)
	_check(rig.is_freecam_active(), "holding the key starts freecam")

	rig.add_look_input(deg_to_rad(90.0), deg_to_rad(15.0))
	await _frames(1)
	_check(rig.get_aim_basis().is_equal_approx(aim), "looking around does not move the aim")
	_check(_angle_between(rig.get_view_basis(), aim) > deg_to_rad(80.0), "but the camera does turn")
	rig.add_look_input(0.0, deg_to_rad(150.0))
	await _frames(1)
	_check(rig.get_aim_basis().is_equal_approx(aim) and rig.get_view_basis().y.dot(aim.y) > -0.001, "and it cannot be tipped over the top and flipped upside down")
	_check(-rig.get_view_basis().z.dot(aim.y) > 0.9999, "looking up stops straight up, like the limit under gravity")

	Input.action_release(rig.freecam_action)
	await _frames(2)
	_check(not rig.is_freecam_active(), "letting go ends freecam")
	_check(_angle_between(rig.get_view_basis(), aim) > deg_to_rad(5.0), "and the camera swings back instead of jumping")
	await _frames(90)
	_check(_angle_between(rig.get_view_basis(), aim) < deg_to_rad(0.5), "to where the aim was left")
	_check(changes == [true, false], "signals said so")

	# Looking while not in freecam moves the aim as normal.
	rig.add_look_input(deg_to_rad(10.0), 0.0)
	_check(not rig.get_aim_basis().is_equal_approx(aim), "and ordinary looking moves the aim again")

	rig.freecam_return_speed = 0.0
	Input.action_press(rig.freecam_action)
	await _frames(1)
	rig.add_look_input(deg_to_rad(90.0), 0.0)
	Input.action_release(rig.freecam_action)
	await _frames(2)
	_check(_angle_between(rig.get_view_basis(), rig.get_aim_basis()) < 0.001, "a return speed of zero snaps straight back")

	rig.freecam_enabled = false
	Input.action_press(rig.freecam_action)
	await _frames(2)
	_check(not rig.is_freecam_active(), "freecam can be switched off for a rig")
	Input.action_release(rig.freecam_action)
	_free(vehicle)


func _test_freecam_in_gravity() -> void:
	print("Freecam with gravity keeps the horizon level")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	rig.orientator.orientation_speed = 0.0
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(2)
	rig.add_look_input(deg_to_rad(30.0), deg_to_rad(30.0))
	var aim := rig.get_aim_basis()
	Input.action_press(rig.freecam_action)
	await _frames(2)

	# Tipping up and then turning sideways is what leaves a camera that turns around its own
	# axes with a tilted horizon.
	rig.add_look_input(0.0, deg_to_rad(20.0))
	rig.add_look_input(deg_to_rad(90.0), 0.0)
	rig.add_look_input(deg_to_rad(40.0), deg_to_rad(-10.0))
	await _frames(1)
	var view := rig.get_view_basis()
	_check(absf(view.x.y) < 0.001, "the horizon stays level however it is turned")
	_check(rig.get_aim_basis().is_equal_approx(aim), "and the aim has not moved")
	_check(absf(rad_to_deg(asin(-view.z.y)) - 40.0) < 0.01, "pitch is the aim's plus what was added")
	var heading := Vector3(-view.z.x, 0.0, -view.z.z).normalized()
	_check(_near(heading, Basis(Vector3.UP, deg_to_rad(160.0)) * Vector3.FORWARD), "and the heading is the aim's plus what was added")

	rig.add_look_input(0.0, deg_to_rad(100.0))
	_check(-rig.get_view_basis().z.y > 0.9999, "looking up stops straight up")
	rig.add_look_input(0.0, deg_to_rad(-300.0))
	_check(-rig.get_view_basis().z.y < -0.9999, "and looking down stops straight down")
	rig.add_look_input(0.0, deg_to_rad(125.0))

	Input.action_press(rig.roll_action)
	rig.apply_mouse_motion(Vector2(300.0, 0.0))
	await _frames(2)
	Input.action_release(rig.roll_action)
	_check(absf(rig.get_view_basis().x.y) < 0.001, "the roll key does nothing to it")

	Input.action_release(rig.freecam_action)
	await _frames(1)
	var worst_tilt := 0.0
	for frame in 90:
		await _frames(1)
		worst_tilt = maxf(worst_tilt, absf(rig.get_view_basis().x.y))
	_check(worst_tilt < 0.001, "it never tilts on the way back to the aim")
	_check(_angle_between(rig.get_view_basis(), aim) < deg_to_rad(0.5), "and ends on the aim")

	# Gravity switching off and on while freecam is held.
	Input.action_press(rig.freecam_action)
	await _frames(2)
	rig.add_look_input(deg_to_rad(120.0), deg_to_rad(20.0))
	var before := rig.get_view_basis()
	rig.set_gravity(Vector3.ZERO)
	await _frames(2)
	_check(rig.is_weightless() and _near(-rig.get_view_basis().z, -before.z, 0.01), "the camera keeps looking the same way when gravity goes away")
	rig.add_look_input(deg_to_rad(10.0), deg_to_rad(5.0), deg_to_rad(25.0))
	var floating_forward := -rig.get_view_basis().z
	_check(absf(rig.get_view_basis().x.dot(rig.get_aim_basis().y)) < 0.001, "freecam does not roll even while floating (level against the aim)")
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(2)
	_check(absf(rig.get_view_basis().x.y) < 0.001, "and the horizon is level again once gravity returns")
	_check(_near(-rig.get_view_basis().z, floating_forward, 0.01), "still looking the same way")
	Input.action_release(rig.freecam_action)
	_free(vehicle)


func _test_mount_limits() -> void:
	print("Mount limits (turret)")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	rig.limit_reference = vehicle
	rig.limit_yaw_arc = 180.0
	rig.limit_minimum_pitch = -45.0
	rig.limit_maximum_pitch = 45.0
	await _frames(2)

	rig.add_look_input(deg_to_rad(40.0), 0.0)
	await _frames(1)
	_check(_near(rig.get_aim_forward(), Basis(Vector3.UP, deg_to_rad(40.0)) * Vector3.FORWARD), "inside the arc it looks wherever it likes")

	rig.add_look_input(deg_to_rad(120.0), 0.0)
	await _frames(1)
	_check(_near(rig.get_aim_forward(), Basis(Vector3.UP, deg_to_rad(90.0)) * Vector3.FORWARD), "it cannot look past the edge of the arc")
	rig.add_look_input(0.0, deg_to_rad(80.0))
	await _frames(1)
	_check(is_equal_approx(rig.get_aim_forward().y, sin(deg_to_rad(45.0))), "or higher than the pitch limit")

	rig.align_to_mount()
	rig.add_look_input(deg_to_rad(90.0), 0.0)
	await _frames(1)
	var aim_at_edge := rig.get_aim_basis()
	vehicle.rotation.y = deg_to_rad(60.0)
	await _frames(1)
	_check(rig.get_aim_basis().is_equal_approx(aim_at_edge), "the vehicle turning toward the aim leaves the aim alone")
	vehicle.rotation.y = deg_to_rad(-45.0)
	await _frames(1)
	_check(_near(rig.get_aim_forward(), Basis(Vector3.UP, deg_to_rad(45.0)) * Vector3.FORWARD), "the vehicle turning away drags the aim along at the edge of the arc")

	vehicle.rotation.y = deg_to_rad(-45.0)
	vehicle.rotation.x = deg_to_rad(-60.0)
	await _frames(1)
	var local_forward := vehicle.global_basis.orthonormalized().inverse() * rig.get_aim_forward()
	_check(local_forward.y <= sin(deg_to_rad(45.0)) + 0.0001 and local_forward.y >= sin(deg_to_rad(-45.0)) - 0.0001, "a pitching vehicle cannot push the aim past the pitch limit either")

	rig.limit_reference = null
	vehicle.rotation = Vector3(0.0, deg_to_rad(170.0), 0.0)
	var free_aim := rig.get_aim_basis()
	await _frames(2)
	_check(rig.get_aim_basis().is_equal_approx(free_aim), "with no limit reference the aim ignores the vehicle completely")
	_free(vehicle)


func _test_heading_helpers() -> void:
	print("Heading helpers for cars and ships")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	rig.orientator.orientation_speed = 0.0
	rig.set_gravity(Vector3.DOWN * 9.8)
	await _frames(2)

	rig.add_look_input(deg_to_rad(90.0), deg_to_rad(40.0))
	_check(_near(rig.get_heading(), Vector3.LEFT), "the heading is the look direction along the ground")
	_check(is_equal_approx(rig.get_yaw_error(Vector3.FORWARD), deg_to_rad(90.0)), "a car pointing forward must turn 90 degrees left")
	_check(is_equal_approx(rig.get_yaw_error(Vector3.LEFT), 0.0), "a car already on the heading has no error")
	var nose_up_and_left := Basis(Vector3.UP, deg_to_rad(90.0)) * Basis(Vector3.RIGHT, deg_to_rad(30.0)) * Vector3.FORWARD
	_check(absf(rig.get_yaw_error(nose_up_and_left)) < 0.0001, "however its nose is pitched")

	# Gravity flips: a car lying upside down still steers toward the camera.
	rig.set_gravity(Vector3.UP * 9.8)
	await _frames(2)
	var up := rig.get_up_direction()
	_check(_near(up, Vector3.DOWN), "up follows gravity even upside down")
	_check(absf(rig.get_heading().dot(up)) < 0.001, "the heading lies along the ground")
	_check(absf(rig.get_yaw_error(Vector3.FORWARD)) > 0.1, "and steering errors are measured around the new up")
	_free(vehicle)


func _test_controls() -> void:
	print("Stick, roll buttons, and menus")
	var vehicle := _vehicle(Vector3.ZERO)
	var rig := _rig(vehicle, Vector3.ZERO)
	await _frames(2)

	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(30)
	_check(rig.get_aim_forward().x > 0.5, "the right stick turns it right")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(30)
	_check(rig.get_aim_forward().y > 0.2, "pushing the stick up looks up")
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _frames(2)

	rig.align_to_mount()
	# Without the roll key sideways mouse movement turns the camera.
	rig.apply_mouse_motion(Vector2(100.0, 0.0))
	_check(rig.get_aim_forward().x > 0.05 and absf(rig.get_aim_basis().y.x) < 0.001, "the mouse turns the camera when the roll key is not held")

	# With it, sideways rolls, and by as much as the mouse moved.
	rig.align_to_mount()
	Input.action_press(rig.roll_action)
	rig.apply_mouse_motion(Vector2(50.0, 0.0))
	var small_roll := rig.get_aim_basis().y.x
	rig.align_to_mount()
	rig.apply_mouse_motion(Vector2(200.0, 0.0))
	var big_roll := rig.get_aim_basis().y.x
	_check(small_roll > 0.01 and big_roll > small_roll * 3.0, "holding the roll key makes the mouse roll it right, smoothly (%.3f, then %.3f)" % [small_roll, big_roll])
	_check(_near(rig.get_aim_forward(), Vector3.FORWARD), "without turning it")
	rig.apply_mouse_motion(Vector2(-400.0, 0.0))
	_check(rig.get_aim_basis().y.x < 0.0, "and the other way rolls it left")
	rig.apply_mouse_motion(Vector2(0.0, -80.0))
	_check(rig.get_aim_forward().y < -0.01 or rig.get_aim_forward().y > 0.01, "while up and down still pitches")

	rig.align_to_mount()
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(20)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check(rig.get_aim_basis().y.x > 0.3 and _near(rig.get_aim_forward(), Vector3.FORWARD), "the right stick rolls it too while the key is held")

	rig.align_to_mount()
	InGameUIHandler.is_ui_open = true
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(20)
	_check(_near(rig.get_aim_forward(), Vector3.FORWARD) and _near(rig.get_aim_basis().y, Vector3.UP), "nothing moves while a menu is open")
	InGameUIHandler.is_ui_open = false
	_axis(JOY_AXIS_RIGHT_X, 0.0)

	# Under gravity the horizon stays level, so the roll key is ignored and the mouse turns as usual.
	rig.set_gravity(Vector3.DOWN * 9.8)
	rig.orientator.orientation_speed = 0.0
	await _frames(2)
	var heading_before := rig.get_aim_forward()
	rig.apply_mouse_motion(Vector2(100.0, 0.0))
	_check(not _near(rig.get_aim_forward(), heading_before, 0.01) and absf(rig.get_aim_basis().x.y) < 0.001, "with gravity the roll key does not roll anything")
	Input.action_release(rig.roll_action)
	rig.set_gravity(Vector3.ZERO)
	await _frames(2)
	rig.align_to_mount()

	rig.input_enabled = false
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(20)
	_check(_near(rig.get_aim_forward(), Vector3.FORWARD), "or when the rig is not being driven")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	rig.input_enabled = true
	await _frames(2)

	var turned: Array[float] = []
	for sensitivity in [1.0, 2.0]:
		Settings.set_setting(&"controls.controller_sensitivity", sensitivity, false)
		rig.align_to_mount()
		_axis(JOY_AXIS_RIGHT_X, 0.5)
		await _frames(20)
		_axis(JOY_AXIS_RIGHT_X, 0.0)
		turned.append(rig.get_aim_forward().x)
		await _frames(2)
	Settings.set_setting(&"controls.controller_sensitivity", 1.0, false)
	_check(turned[1] > turned[0] * 1.5, "the controller sensitivity setting applies")
	_free(vehicle)


func _test_vehicle_link() -> void:
	print("Works with a Vehicle3D")
	# Built the way a vehicle scene is: the rig is already inside when the vehicle starts.
	var vehicle := Vehicle3D.new()
	var rig := RIG_SCENE.instantiate() as CameraRig3D
	vehicle.add_child(rig)
	_world.add_child(vehicle)
	await _frames(2)
	_check(vehicle.vehicle_camera == rig.camera, "the vehicle uses the rig's camera")
	_check(not rig.input_enabled, "the rig ignores input until someone is in control")
	_check(not rig.camera.current, "and is not the active camera before then")
	_free(vehicle)


# --- Helpers -----------------------------------------------------------------

func _vehicle(at: Vector3) -> Node3D:
	var vehicle := Node3D.new()
	_world.add_child(vehicle)
	vehicle.global_position = at
	return vehicle


func _rig(vehicle: Node3D, mount_at: Vector3) -> CameraRig3D:
	var rig := RIG_SCENE.instantiate() as CameraRig3D
	rig.position = mount_at
	vehicle.add_child(rig)
	return rig


func _free(node: Node) -> void:
	node.free()
	_release_inputs()


func _release_inputs() -> void:
	for axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		_axis(axis, 0.0)


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _angle_between(a: Basis, b: Basis) -> float:
	return a.orthonormalized().get_rotation_quaternion().angle_to(b.orthonormalized().get_rotation_quaternion())


func _near(a: Vector3, b: Vector3, tolerance := 0.001) -> bool:
	return a.distance_to(b) <= tolerance


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
