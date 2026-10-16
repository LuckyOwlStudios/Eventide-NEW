extends Node
## Checks a vehicle's power switch lever, the nodes that follow its power, the headlights on the lights
## key, and the exterior doors on the doors key, on the real Mule.
##
## godot --headless --fixed-fps 60 --path . res://Components/Vehicles/Testing/VehicleSystemsTest.tscn
## ONLY=<name> runs one test, such as ONLY=doors.

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")

var _world: Node3D
var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in ["lever", "lever_standalone", "power_nodes", "lights", "doors", "keys"]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			_begin_world()
			await call("_test_" + test_name)
			_release_keys()
			_end_world()
	if _failures == 0:
		print("Vehicle systems tests passed.")
	else:
		print("Vehicle systems tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_lever() -> void:
	var mule := _mule(Vector3(0.0, 20.0, 0.0))
	await _frames(3)
	var power_switch := mule.find_child("PowerSwitch", true, false) as PowerSwitch3D
	var lever := power_switch.lever if power_switch != null else null
	_check(lever != null, "the Mule's power switch has a lever")
	if lever == null:
		return
	_check(mule.power_state and lever.down, "the Mule starts with its power on and the lever down")
	_check(is_equal_approx(lever.get_angle(), lever.down_angle) and not lever.is_swinging(), "with the arm in its down position (%.1f degrees)" % lever.get_angle())
	var arm := lever.get_node("Arm") as Node3D
	var up_direction := mule.global_basis.y
	# The lever sits on the panel facing into the room; down means the arm points below the hinge.
	_check(_arm_height(lever, arm) < -0.03, "which puts the arm below the hinge (%.3f m)" % _arm_height(lever, arm))

	# Pulling it: the prompts, then the swing.
	_check(power_switch._interact_option(null, 1) and not mule.power_state, "turning the power off from the switch")
	_check(not lever.down and lever.is_swinging(), "sends the lever up, and it takes time to get there")
	await _frames(5)
	_check(lever.progress > 0.0 and lever.progress < 1.0, "it is part of the way after a moment (%.2f)" % lever.progress)
	await _frames(40)
	_check(not lever.is_swinging() and is_equal_approx(lever.get_angle(), lever.up_angle), "and then it is up (%.1f degrees)" % lever.get_angle())
	_check(_arm_height(lever, arm) > 0.03, "with the arm above the hinge (%.3f m)" % _arm_height(lever, arm))
	_check(is_equal_approx(up_direction.dot(Vector3.UP), 1.0), "(the Mule is level)")

	_check(power_switch._interact_option(null, 0) and mule.power_state, "turning it back on")
	await _frames(40)
	_check(lever.down and is_equal_approx(lever.get_angle(), lever.down_angle), "puts the lever back down")

	# Whoever changes the power, the lever tells the truth.
	mule.power_state = false
	await _frames(40)
	_check(not lever.down and is_equal_approx(lever.get_angle(), lever.up_angle), "cutting the power from anywhere else raises the lever too")
	mule.power_state = true
	await _frames(40)
	_check(lever.down, "and restoring it lowers the lever")


func _test_lever_standalone() -> void:
	# The lever on its own: a node with an arm, turned by the down flag.
	var lever := Lever3D.new()
	lever.rotation = Vector3(0.0, 0.5, 0.0)
	var arm := Node3D.new()
	arm.position = Vector3(0.0, 0.1, 0.0)
	lever.add_child(arm)
	_world.add_child(lever)
	await _frames(2)
	var signals := []
	lever.moved.connect(func(is_down: bool) -> void: signals.append(is_down))
	_check(not lever.down and is_equal_approx(lever.get_angle(), 45.0), "a new lever is up")
	_check(is_equal_approx(lever.rotation.y, 0.5) or lever.basis.is_equal_approx(Basis.from_euler(Vector3(0.0, 0.5, 0.0)) * Basis(Vector3.RIGHT, deg_to_rad(45.0))), "and keeps the way it was placed")
	lever.down = true
	await _frames(30)
	_check(signals == [true] and is_equal_approx(lever.get_angle(), 135.0), "pulling it down swings the arm and says so once (%s)" % str(signals))
	lever.down = false
	lever.down = true
	_check(not lever.is_swinging(), "pulling a lever that is already down does nothing")
	lever.snap(false)
	_check(not lever.down and is_equal_approx(lever.get_angle(), 45.0) and not lever.is_swinging(), "snap puts it up at once")
	var quarter := Lever3D.new()
	quarter.travel_time = 1.0
	_world.add_child(quarter)
	await _frames(2)
	quarter.down = true
	await _frames(30)
	_check(quarter.progress > 0.4 and quarter.progress < 0.6, "the swing takes its travel time (%.2f of it after half a second)" % quarter.progress)


func _test_power_nodes() -> void:
	var mule := _mule(Vector3(0.0, 20.0, 0.0))
	await _frames(3)
	var panel := Node3D.new()
	var lamp := Node3D.new()
	mule.add_child(panel)
	mule.add_child(lamp)
	mule.power_on_nodes = [panel, lamp]
	mule.power_state = false
	_check(not panel.visible and not lamp.visible, "nodes that need power are hidden when the power is off")
	mule.power_state = true
	_check(panel.visible and lamp.visible, "and shown when it comes on")
	# A node set up while the vehicle is already ready is still right.
	var late := Node3D.new()
	mule.add_child(late)
	late.visible = false
	mule.power_on_nodes = [late]
	mule.power_state = false
	mule.power_state = true
	_check(late.visible, "a node added later joins in")
	# Nodes named in both lists follow the stricter rule.
	mule.power_on_nodes = [lamp]
	mule.lights = [lamp]
	mule.light_state = false
	_check(not lamp.visible, "a node that is also a headlight stays dark with the switch off, even with power")
	mule.light_state = true
	_check(lamp.visible, "and shines with it on")
	mule.power_state = false
	_check(not lamp.visible, "and goes dark with the power")

	# A vehicle that starts without power starts dark.
	var dark := MULE_SCENE.instantiate() as Mule
	dark.power_state = false
	dark.position = Vector3(100.0, 20.0, 0.0)
	_world.add_child(dark)
	await _frames(2)
	for light in dark.lights:
		_check(not light.visible, "%s is dark on a Mule that starts without power" % light.name)


func _test_lights() -> void:
	var mule := _mule(Vector3(0.0, 20.0, 0.0))
	await _frames(3)
	_check(mule.lights.size() == 2, "the Mule's two headlights are on its lights list (%d)" % mule.lights.size())
	var changes := []
	mule.light_state_changed.connect(func(on: bool) -> void: changes.append(on))
	_check(mule.light_state and mule.are_lights_shining(), "with power and the switch on they shine")
	for light in mule.lights:
		_check(light.visible, "%s is visible" % light.name)

	_press(&"light")
	await _frames(10)
	_release(&"light")
	_check(mule.light_state, "with nobody flying it the lights key does nothing")

	mule.fly_without_pilot = true
	await _frames(5)
	_press(&"light")
	await _frames(10)
	_release(&"light")
	await _frames(3)
	_check(not mule.light_state and changes == [false], "from the pilot's seat the key switches them off (%s)" % str(changes))
	for light in mule.lights:
		_check(not light.visible, "%s is dark" % light.name)
	_check(not mule.are_lights_shining(), "and they are not shining")

	_press(&"light")
	await _frames(10)
	_release(&"light")
	await _frames(3)
	_check(mule.light_state and changes == [false, true], "a second press puts them back on")
	for light in mule.lights:
		_check(light.visible, "%s shines again" % light.name)

	mule.power_state = false
	for light in mule.lights:
		_check(not light.visible, "%s is dark without power" % light.name)
	_check(mule.light_state and not mule.are_lights_shining(), "though the switch is still on")
	_press(&"light")
	await _frames(10)
	_release(&"light")
	await _frames(3)
	_check(mule.light_state, "the key does nothing without power")
	mule.power_state = true
	for light in mule.lights:
		_check(light.visible, "%s is back when the power is" % light.name)

	InGameUIHandler.is_ui_open = true
	_press(&"light")
	await _frames(10)
	_release(&"light")
	InGameUIHandler.is_ui_open = false
	_check(mule.light_state, "with a menu open the key does nothing")

	mule.toggle_lights()
	_check(not mule.light_state, "code can switch them too")


func _test_doors() -> void:
	var mule := _mule(Vector3(0.0, 20.0, 0.0))
	mule.engine_state = true
	await _frames(3)
	_check(mule.exterior_doors.size() == 1, "the Mule's cargo bay door is on its exterior doors list (%d)" % mule.exterior_doors.size())
	var door := mule.exterior_doors[0]
	_check(door == mule.find_child("Door", true, false), "and it is the ramp in the bow")
	_check(not door.open_requested and not mule.are_exterior_doors_open(), "it starts closed")

	_press(&"exterior_doors")
	await _frames(10)
	_release(&"exterior_doors")
	_check(not door.open_requested, "with nobody flying the Mule the doors key does nothing")

	mule.fly_without_pilot = true
	await _frames(5)
	_press(&"exterior_doors")
	await _frames(10)
	_release(&"exterior_doors")
	await _frames(3)
	_check(door.open_requested and mule.are_exterior_doors_open(), "from the pilot's seat the key opens the door")
	await _frames(60)
	_check(door.get_angle() > 20.0, "and it swings open (%.0f degrees a second on)" % door.get_angle())
	await _frames(180)
	_check(door.is_fully_open(), "all the way (%.0f degrees)" % door.get_angle())

	_press(&"exterior_doors")
	await _frames(10)
	_release(&"exterior_doors")
	await _frames(3)
	_check(not door.open_requested, "a second press closes it")
	await _frames(240)
	_check(door.is_fully_closed(), "all the way")

	mule.power_state = false
	_press(&"exterior_doors")
	await _frames(10)
	_release(&"exterior_doors")
	_check(not door.open_requested and not mule.toggle_exterior_doors(), "with the power out the doors key does nothing")
	mule.power_state = true

	# If one is open, the key closes the lot.
	var second := HingedDoor3D.new()
	var second_pivot := Node3D.new()
	second.add_child(second_pivot)
	second.pivot = second_pivot
	mule.add_child(second)
	mule.exterior_doors = [door, second]
	await _frames(2)
	second.set_open(true)
	_check(mule.are_exterior_doors_open(), "one open door counts as open")
	_check(mule.toggle_exterior_doors() and not door.open_requested and not second.open_requested, "so the key closes them all")
	_check(mule.toggle_exterior_doors() and door.open_requested and second.open_requested, "and the next press opens them all")
	mule.exterior_doors = []
	_check(not mule.toggle_exterior_doors(), "a vehicle with no exterior doors does nothing")


func _test_keys() -> void:
	var lights := InputMap.action_get_events(&"light")
	var has_f := false
	for event in lights:
		has_f = has_f or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F)
	_check(has_f, "the lights action is on F")
	var doors := InputMap.action_get_events(&"exterior_doors")
	var has_key := false
	var has_button := false
	for event in doors:
		has_key = has_key or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_H)
		has_button = has_button or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_UP)
	_check(has_key and has_button, "the doors action is on H, and on the D-pad up")


# --- Helpers -----------------------------------------------------------------

func _begin_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	InGameUIHandler.is_ui_open = false


func _end_world() -> void:
	_world.free()
	InGameUIHandler.is_ui_open = true


func _release_keys() -> void:
	for action in [&"light", &"exterior_doors"]:
		Input.action_release(action)


func _press(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _mule(at: Vector3) -> Mule:
	var mule := MULE_SCENE.instantiate() as Mule
	mule.position = at
	_world.add_child(mule)
	return mule


## How far above the hinge the tip of the arm is, in the world.
func _arm_height(lever: Lever3D, arm: Node3D) -> float:
	return (arm.global_position - lever.global_position).dot(Vector3.UP)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
