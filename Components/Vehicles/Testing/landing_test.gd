extends Node
## Checks the Mule's landing gear on real Jolt physics: six legs in the six bays under its sides that
## hold it up, a ship that counts as landed while enough of them are on the ground and Space is not
## held, full gravity while landed, an easy lift-off with Space, and legs that can be pulled up into
## their bays and put back down, which takes power.
##
## godot --headless --fixed-fps 60 --path . res://Components/Vehicles/Testing/LandingTest.tscn
## ONLY=<name> runs one test, such as ONLY=takeoff.

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const GRAVITY := 16.0
## How far below the Mule's origin each leg is mounted, and how far one reaches when fully out.
const MOUNT_HEIGHT := 0.15
const GEAR_REACH := 1.15
## Where the Mule's origin stands on its gear: six springs of strength 20 that carry its weight.
const STANDING_HEIGHT := GEAR_REACH - MOUNT_HEIGHT - GRAVITY / (6.0 * 20.0)

var _world: Node3D
var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in [
		"layout", "parks", "weight", "takeoff", "landing", "retract", "power", "key", "needed", "skid", "space",
		"no_gear",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			_begin_world()
			await call("_test_" + test_name)
			_release_keys()
			_end_world()
	if _failures == 0:
		print("Landing tests passed.")
	else:
		print("Landing tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_layout() -> void:
	var mule := _mule(Vector3(0.0, 8.0, 0.0))
	await _frames(3)
	var gear := _gear(mule)
	_check(gear.size() == 6 and mule.get_landing_gear_count() == 6, "the Mule has six landing gear (%d)" % gear.size())
	var zs: Array[float] = []
	var bow := 0
	var stern := 0
	var every_one_down := true
	var every_one_ours := true
	for leg in gear:
		var spot := mule.to_local(leg.global_position)
		zs.append(snappedf(spot.z, 0.001))
		_check(absf(absf(spot.x) - 2.5) < 0.001 and absf(spot.y - MOUNT_HEIGHT) < 0.001, "%s is in its bay, under the Mule's side (%.2f, %.2f)" % [leg.name, spot.x, spot.y])
		if leg.get_node("..").name == "MuleBow":
			bow += 1
		else:
			stern += 1
		every_one_down = every_one_down and leg.get_axis().is_equal_approx(mule.global_basis * Vector3.DOWN)
		every_one_ours = every_one_ours and leg.rigid_body == mule
	zs.sort()
	_check(bow == 2 and stern == 4, "two on the bow, four on the stern (%d, %d)" % [bow, stern])
	_check(zs == [-6.875, -6.875, 5.0, 5.0, 8.0, 8.0], "in the six bays: %s" % str(zs))
	_check(every_one_down, "every one points straight down")
	_check(every_one_ours, "and holds up the Mule")
	_check(mule.landing_gear_deployed and is_equal_approx(mule.get_landing_gear_extension(), 1.0) and not mule.is_landed(), "the gear starts down, and the Mule starts in the air")
	# Out, the feet stand clear below the belly; in, they are up in the bays.
	var belly := mule.global_position.y - 0.375
	for leg in gear:
		var pad := leg.get_node("Leg/Pad") as Node3D
		_check(pad.global_position.y < belly - 0.4, "%s's foot stands well below the hull (%.2f below)" % [leg.name, belly - pad.global_position.y])
		break


func _test_parks() -> void:
	var mule := _mule(Vector3(0.0, 1.5, 0.0))
	await _frames(360)
	_check(mule.get_landing_gear_touching() == 6, "dropped onto the floor all six legs are on it (%d)" % mule.get_landing_gear_touching())
	_check(mule.is_landed(), "so the Mule is landed")
	_check(absf(mule.global_position.y - STANDING_HEIGHT) < 0.08, "standing %.2f m up, on its gear, as the springs say (%.3f)" % [STANDING_HEIGHT, mule.global_position.y])
	_check(mule.global_position.y - 0.375 > 0.3, "its belly well clear of the floor (%.2f m)" % (mule.global_position.y - 0.375))
	_check(mule.linear_velocity.length() < 0.01 and mule.angular_velocity.length() < 0.001, "perfectly still (%.4f m/s, %.5f rad/s)" % [mule.linear_velocity.length(), mule.angular_velocity.length()])
	_check(rad_to_deg(mule.global_basis.y.angle_to(Vector3.UP)) < 1.0, "and level (%.2f degrees off)" % rad_to_deg(mule.global_basis.y.angle_to(Vector3.UP)))
	var carried := 0.0
	for leg in _gear(mule):
		carried += leg.get_spring_force()
	_check(absf(carried - mule.mass * GRAVITY) < mule.mass * GRAVITY * 0.02, "the six legs together carry its weight (%.0f of %.0f N)" % [carried, mule.mass * GRAVITY])
	_check(abs(mule.global_position.x) < 0.2 and abs(mule.global_position.z) < 0.2, "without having wandered off")


func _test_weight() -> void:
	# With the engine on a ship in the air hovers, but one on its gear is landed, and feels its weight.
	var mule := _mule(Vector3(0.0, 1.5, 0.0))
	await _frames(360)
	var landed_at := mule.global_position.y
	mule.engine_state = true
	await _frames(240)
	_check(mule.is_landed(), "starting the engine does not take it off the ground")
	_check(absf(mule.global_position.y - landed_at) < 0.02, "it stays on its springs (%.3f, was %.3f)" % [mule.global_position.y, landed_at])
	_check(mule.linear_velocity.length() < 0.01, "and does not drift (%.4f m/s)" % mule.linear_velocity.length())

	# In the air with the engine on it hovers, and when it comes down on its gear it stops hovering.
	var floating := _mule(Vector3(40.0, 12.0, 0.0))
	floating.engine_state = true
	await _frames(180)
	_check(not floating.is_landed() and absf(floating.global_position.y - 12.0) < 0.05, "a Mule hovering above the ground is not landed and does not fall (%.2f)" % floating.global_position.y)


func _test_takeoff() -> void:
	var mule := _mule(Vector3(0.0, 1.5, 0.0))
	await _frames(300)
	mule.engine_state = true
	mule.fly_without_pilot = true
	await _frames(60)
	_check(mule.is_landed() and absf(mule.global_position.y - STANDING_HEIGHT) < 0.08, "parked on its gear with the engine on")
	var changes: Array[bool] = []
	mule.landed_changed.connect(func(landed: bool) -> void: changes.append(landed))
	Input.action_press(&"jump")
	await _frames(2)
	_check(not mule.is_landed() and changes == [false], "holding Space ends the landing at once")
	await _frames(120)
	_check(mule.global_position.y > 6.0, "and it takes off easily (%.1f m up after two seconds)" % mule.global_position.y)
	_check(mule.get_landing_gear_touching() == 0, "with no leg on the ground")
	Input.action_release(&"jump")
	await _frames(240)
	var hover_height := mule.global_position.y
	_check(not mule.is_landed() and mule.linear_velocity.length() < 0.5, "let go in the air, it hovers (%.2f m/s)" % mule.linear_velocity.length())
	await _frames(120)
	_check(absf(mule.global_position.y - hover_height) < 0.2, "without falling (%.2f m in two seconds)" % absf(mule.global_position.y - hover_height))


func _test_landing() -> void:
	var mule := _mule(Vector3(0.0, 8.0, 0.0))
	mule.engine_state = true
	mule.fly_without_pilot = true
	await _frames(60)
	_check(not mule.is_landed() and absf(mule.global_position.y - 8.0) < 0.05, "hovering in the air above the ground")
	# Down slowly: Ctrl with Alt held.
	Input.action_press(&"crouch")
	Input.action_press(&"stroll")
	var lowest := 99.0
	var landed_at := -1
	for frame in 900:
		await _frames(1)
		lowest = minf(lowest, mule.global_position.y)
		if landed_at < 0 and mule.is_landed():
			landed_at = frame
			Input.action_release(&"crouch")
			Input.action_release(&"stroll")
	_check(landed_at >= 0, "coming down onto the ground it lands (after %d frames)" % landed_at)
	_check(lowest - 0.375 > 0.05, "the legs took the landing, not the hull (the belly came within %.2f m of the floor)" % (lowest - 0.375))
	await _frames(240)
	_check(mule.is_landed() and absf(mule.global_position.y - STANDING_HEIGHT) < 0.08, "and it rests on its gear (%.3f)" % mule.global_position.y)
	_check(mule.linear_velocity.length() < 0.01, "stationary (%.4f m/s)" % mule.linear_velocity.length())
	# It keeps its weight: nothing lifts it as time goes by.
	await _frames(300)
	_check(absf(mule.global_position.y - STANDING_HEIGHT) < 0.08 and mule.is_landed(), "and stays there (%.3f)" % mule.global_position.y)


func _test_retract() -> void:
	var mule := _mule(Vector3(0.0, 10.0, 0.0))
	mule.engine_state = true
	await _frames(30)
	var pads: Array[Node3D] = []
	for leg in _gear(mule):
		pads.append(leg.get_node("Leg/Pad") as Node3D)
	var down_y := mule.to_local(pads[0].global_position).y
	_check(mule.landing_gear_deployed and not mule.is_landing_gear_moving(), "the gear is down to begin with")
	var commands: Array[bool] = []
	mule.landing_gear_changed.connect(func(deployed: bool) -> void: commands.append(deployed))
	_check(mule.retract_landing_gear() and not mule.landing_gear_deployed and commands == [false], "told to retract")
	_check(mule.is_landing_gear_moving(), "it is on its way")
	await _frames(int(mule.landing_gear_travel_time * 60.0 * 0.5))
	var halfway_y := mule.to_local(pads[0].global_position).y
	_check(halfway_y > down_y + 0.3 and halfway_y < down_y + GEAR_REACH - 0.3, "halfway through, the foot is halfway up (%.2f, between %.2f and %.2f)" % [halfway_y, down_y, down_y + GEAR_REACH])
	_check(absf(mule.get_landing_gear_extension() - 0.5) < 0.05, "and the gear says so (%.2f)" % mule.get_landing_gear_extension())
	await _frames(int(mule.landing_gear_travel_time * 60.0 * 0.5) + 10)
	_check(not mule.is_landing_gear_moving() and mule.get_landing_gear_extension() == 0.0, "it finishes all the way up")
	var up_y := mule.to_local(pads[0].global_position).y
	_check(absf(up_y - (down_y + GEAR_REACH)) < 0.01, "the foot has gone up into its bay (%.2f, was %.2f)" % [up_y, down_y])
	for index in pads.size():
		var spot := mule.to_local(pads[index].global_position)
		_check(spot.y > 0.0 and spot.y < 1.0 and absf(absf(spot.x) - 2.5) < 0.001, "and is inside the box on the side, not poking out of it (%.2f, %.2f, %.2f)" % [spot.x, spot.y, spot.z])
		var piston := pads[index].get_node("../Piston") as MeshInstance3D
		var top := mule.to_local(piston.global_position).y + (piston.mesh as CylinderMesh).height * 0.5
		_check(top < 1.8, "the leg's top is inside the box as well, below its roof at 1.875 (%.2f)" % top)
		break

	# With the gear up there is nothing to land on.
	mule.engine_state = false
	mule.global_position = Vector3(30.0, 1.0, 0.0)
	mule.linear_velocity = Vector3.ZERO
	await _frames(300)
	_check(mule.get_landing_gear_touching() == 0 and not mule.is_landed(), "with the gear up, none of it touches the ground, so it is not landed")
	_check(absf(mule.global_position.y - 0.375) < 0.1, "the hull rests on the floor (%.3f)" % mule.global_position.y)
	_check(mule.deploy_landing_gear() and mule.landing_gear_deployed and commands == [false, true], "told to deploy")
	await _frames(int(mule.landing_gear_travel_time * 60.0) + 120)
	_check(mule.get_landing_gear_extension() == 1.0, "it ends up all the way down")
	_check(mule.is_landed() and absf(mule.global_position.y - STANDING_HEIGHT) < 0.08, "and the gear has pushed the Mule up onto its legs (%.3f)" % mule.global_position.y)


func _test_power() -> void:
	var mule := _mule(Vector3(0.0, 10.0, 0.0))
	mule.engine_state = true
	mule.power_state = false
	await _frames(10)
	_check(not mule.toggle_landing_gear() and not mule.retract_landing_gear() and mule.landing_gear_deployed, "without power the gear cannot be told to move")
	mule.power_state = true
	mule.retract_landing_gear()
	await _frames(60)
	var extension := mule.get_landing_gear_extension()
	_check(extension < 1.0 and extension > 0.0, "with power it moves (%.2f)" % extension)
	mule.power_state = false
	await _frames(60)
	_check(is_equal_approx(mule.get_landing_gear_extension(), extension), "if the power goes while it moves, it stops where it is (%.2f)" % mule.get_landing_gear_extension())
	mule.power_state = true
	await _frames(240)
	_check(mule.get_landing_gear_extension() == 0.0, "and carries on when the power returns")


func _test_key() -> void:
	var mule := _mule(Vector3(0.0, 10.0, 0.0))
	mule.engine_state = true
	await _frames(10)
	Input.action_press(&"landing_gear")
	await _frames(10)
	Input.action_release(&"landing_gear")
	_check(mule.landing_gear_deployed, "with nobody flying it the key does nothing")
	mule.fly_without_pilot = true
	await _frames(5)
	Input.action_press(&"landing_gear")
	await _frames(10)
	Input.action_release(&"landing_gear")
	await _frames(5)
	_check(not mule.landing_gear_deployed, "from the pilot's seat the key retracts the gear")
	Input.action_press(&"landing_gear")
	await _frames(10)
	Input.action_release(&"landing_gear")
	await _frames(5)
	_check(mule.landing_gear_deployed, "and a second press puts it back down")
	InGameUIHandler.is_ui_open = true
	Input.action_press(&"landing_gear")
	await _frames(10)
	Input.action_release(&"landing_gear")
	InGameUIHandler.is_ui_open = false
	_check(mule.landing_gear_deployed, "with a menu open it does nothing")
	var keys := InputMap.action_get_events(&"landing_gear")
	var has_key := false
	var has_button := false
	for event in keys:
		has_key = has_key or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_G)
		has_button = has_button or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_DOWN)
	_check(has_key and has_button, "the action is on G, and on the D-pad down")


func _test_needed() -> void:
	var mule := _mule(Vector3(0.0, 1.5, 0.0))
	await _frames(360)
	_check(mule.is_landed() and mule.landing_gear_needed == 3, "landed on all six, with three needed")
	var gear := _gear(mule)
	# Three legs left on the ground are enough, two are not.
	for index in [0, 1, 2]:
		gear[index].enabled = false
	await _frames(10)
	_check(mule.get_landing_gear_touching() == 3 and mule.is_landed(), "three of the six on the ground is still landed")
	gear[3].enabled = false
	await _frames(20)
	_check(mule.get_landing_gear_touching() == 2 and not mule.is_landed(), "two is not")
	for leg in gear:
		leg.enabled = true
	mule.landing_gear_needed = 6
	await _frames(180)
	_check(mule.get_landing_gear_touching() == 6 and mule.is_landed(), "it can be made to need all six")


func _test_skid() -> void:
	var mule := _mule(Vector3(0.0, 1.5, 0.0))
	await _frames(360)
	mule.linear_velocity = Vector3(0.0, 0.0, -6.0)
	await _frames(180)
	_check(mule.linear_velocity.length() < 0.05, "sliding along the ground on its feet, it is brought to a stop (%.3f m/s)" % mule.linear_velocity.length())
	_check(mule.is_landed() and absf(mule.global_position.y - STANDING_HEIGHT) < 0.08, "still on its gear (%.3f)" % mule.global_position.y)
	_check(absf(mule.global_position.z) < 4.0, "having slid a few meters (%.1f)" % mule.global_position.z)


func _test_space() -> void:
	# Far outside the gravity field there is a floor to be near, but nothing to land on.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100.0, 2.0, 100.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(1000.0, -1.0, 0.0)
	_world.add_child(floor_body)
	var mule := _mule(Vector3(1000.0, 0.85, 0.0))
	mule.engine_state = true
	mule.fly_without_pilot = true
	await _frames(3)
	_check(mule.get_landing_gear_touching() >= 3, "the gear is on the floor (%d legs)" % mule.get_landing_gear_touching())
	_check(not mule.is_landed(), "but with no gravity the Mule is not landed")
	var forward := -mule.camera_rig.get_aim_basis().z
	Input.action_press(&"move_forward")
	await _frames(90)
	_check(mule.linear_velocity.dot(forward) > 5.0, "so the pilot can still fly it (%.1f m/s forward)" % mule.linear_velocity.dot(forward))


func _test_no_gear() -> void:
	# A ship with no landing gear behaves as it always did.
	var ship := SpaceShip3D.new()
	ship.mass = 10000.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 10.0)
	shape.shape = box
	ship.add_child(shape)
	ship.add_child(load("res://Components/Camera/CameraRig.tscn").instantiate())
	ship.engine_state = true
	ship.power_state = true
	ship.position = Vector3(0.0, 6.0, 0.0)
	_world.add_child(ship)
	await _frames(120)
	_check(ship.get_landing_gear_count() == 0 and not ship.is_landed(), "it has no gear and is never landed")
	_check(absf(ship.global_position.y - 6.0) < 0.05, "it hovers as before (%.2f)" % ship.global_position.y)
	ship.toggle_landing_gear()
	await _frames(10)
	_check(not ship.is_landing_gear_moving() and not ship.is_landed(), "and asking for gear harms nothing")


# --- Helpers -----------------------------------------------------------------

func _begin_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	InGameUIHandler.is_ui_open = false
	# Floors for tests that put the Mule in several places: 100 m wide, top at y = 0.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(300.0, 2.0, 300.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	_world.add_child(floor_body)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(600.0, 600.0, 600.0)
	field_shape.shape = field_box
	field.add_child(field_shape)
	_world.add_child(field)


func _end_world() -> void:
	_world.free()
	InGameUIHandler.is_ui_open = true


func _release_keys() -> void:
	for action in [&"jump", &"crouch", &"stroll", &"landing_gear", &"move_forward"]:
		Input.action_release(action)


func _mule(at: Vector3) -> Mule:
	var mule := MULE_SCENE.instantiate() as Mule
	mule.position = at
	_world.add_child(mule)
	return mule


func _gear(mule: Mule) -> Array[Suspension3D]:
	var found: Array[Suspension3D] = []
	for node in mule.find_children("*", "Suspension3D", true, false):
		found.append(node as Suspension3D)
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
