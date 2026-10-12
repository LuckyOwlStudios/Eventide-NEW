extends Node
## Checks gamepad control of the real Player scene by feeding it real joystick events:
## movement with the left stick, looking with the right stick, and the buttons.
##
## godot --headless --fixed-fps 60 --path . res://Components/Movement/Testing/ControllerInputTest.tscn

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

var physics_frame: Signal
var _failures := 0
var _world: Node3D


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	_test_input_map()
	_test_settings_list()
	_world = Node3D.new()
	add_child(_world)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300.0, 200.0, 300.0)
	field_shape.shape = field_box
	field_shape.position = Vector3(0.0, 80.0, 0.0)
	field.add_child(field_shape)
	_world.add_child(field)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400.0, 1.0, 400.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.05, 0.0)
	_world.add_child(player)
	var controller := player.get_node("PlayerCharacterController") as CharacterController
	var rotator := player.get_node("Rotator") as Rotator
	# The turn-speed limit the server puts on players runs on wall-clock time, and a test runs
	# frames faster than real time, so it would pull the view back. Lift it here.
	rotator.server_max_turn_speed_degrees = 1000000.0
	InGameUIHandler.is_ui_open = false
	await _ticks(40)

	await _test_movement(player, controller)
	await _test_buttons(player, controller)
	await _test_looking(rotator)

	_release_everything()
	_world.free()
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Controller input tests passed.")
	else:
		print("Controller input tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_input_map() -> void:
	var expected := {
		&"move_left": [JOY_AXIS_LEFT_X, -1.0],
		&"move_right": [JOY_AXIS_LEFT_X, 1.0],
		&"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
		&"move_back": [JOY_AXIS_LEFT_Y, 1.0],
		&"look_left": [JOY_AXIS_RIGHT_X, -1.0],
		&"look_right": [JOY_AXIS_RIGHT_X, 1.0],
		&"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
		&"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	}
	for action: StringName in expected:
		var found := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion and event.axis == expected[action][0] and signf(event.axis_value) == expected[action][1]:
				found = true
		_check(found, "%s is on the stick" % action)
		_check(InputMap.action_get_deadzone(action) <= 0.3, "%s has a deadzone a stick can work with (%.2f)" % [action, InputMap.action_get_deadzone(action)])
	for entry in [[&"jump", JOY_BUTTON_A], [&"crouch", JOY_BUTTON_B], [&"sprint", JOY_BUTTON_LEFT_STICK], [&"stroll", JOY_BUTTON_RIGHT_STICK], [&"roll", JOY_BUTTON_LEFT_SHOULDER]]:
		var on_button := false
		var keyboard := false
		for event in InputMap.action_get_events(entry[0]):
			if event is InputEventJoypadButton and event.button_index == entry[1]:
				on_button = true
			if event is InputEventKey or event is InputEventMouseButton:
				keyboard = true
		_check(on_button, "%s has its button" % entry[0])
		_check(keyboard, "and still its keyboard key or mouse button")


func _test_settings_list() -> void:
	_check(Settings.get_definition(&"keybind.look_left") == null, "the stick-only look actions are not offered as keyboard rebinds")
	_check(Settings.get_definition(&"keybind.move_forward") != null, "while the move keys still can be rebound")
	_check(Settings.get_definition(&"controls.controller_sensitivity") != null, "and there is a controller sensitivity setting")
	var before := InputMap.action_get_events(&"move_forward").size()
	Settings.set_setting(&"keybind.move_forward", PackedInt64Array([KEY_I]), false)
	var kept := false
	for event in InputMap.action_get_events(&"move_forward"):
		if event is InputEventJoypadMotion:
			kept = true
	_check(kept, "rebinding a key keeps the stick binding")
	Settings.reset_setting(&"keybind.move_forward")
	var after := InputMap.action_get_events(&"move_forward").size()
	_check(after >= before - 1, "and resetting it restores the keys (%d events, was %d)" % [after, before])


func _test_movement(player: CharacterBody3D, controller: CharacterController) -> void:
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _ticks(45)
	var speed := _planar_speed(player)
	_check(absf(speed - 5.0) < 0.2, "the stick all the way forward walks at full speed (%.2f m/s)" % speed)
	_check(player.velocity.z < -4.0, "and forward is forward")

	_axis(JOY_AXIS_LEFT_Y, -0.6)
	await _ticks(45)
	speed = _planar_speed(player)
	_check(speed > 2.0 and speed < 3.2, "a gentle push walks slowly, about half speed (%.2f m/s)" % speed)

	_axis(JOY_AXIS_LEFT_Y, -0.12)
	await _ticks(45)
	_check(_planar_speed(player) < 0.1, "a push inside the deadzone does nothing, so a resting stick does not drift (%.3f)" % _planar_speed(player))

	_axis(JOY_AXIS_LEFT_Y, -1.0)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _ticks(45)
	speed = _planar_speed(player)
	_check(absf(speed - 5.0) < 0.3, "pushing the corner of the stick is no faster than straight (%.2f m/s)" % speed)
	_check(player.velocity.x > 2.0 and player.velocity.z < -2.0, "and goes diagonally forward and right")
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _ticks(30)

	_axis(JOY_AXIS_LEFT_X, -1.0)
	await _ticks(45)
	_check(player.velocity.x < -4.0, "stick left strafes left (%.2f)" % player.velocity.x)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 1.0)
	await _ticks(45)
	_check(player.velocity.z > 4.0, "stick down walks backward (%.2f)" % player.velocity.z)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _ticks(30)
	_check(controller.is_grounded() and _planar_speed(player) < 0.1, "letting go stops")


func _test_buttons(player: CharacterBody3D, controller: CharacterController) -> void:
	_button(JOY_BUTTON_A, true)
	var peak := 0.0
	for tick in 50:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		if tick == 2:
			_button(JOY_BUTTON_A, false)
	_check(peak > 0.8 and peak < 1.2, "A jumps (%.2f m)" % peak)
	await _ticks(40)

	_button(JOY_BUTTON_B, true)
	await _ticks(40)
	_check(controller.is_crouching(), "holding B crouches")
	_button(JOY_BUTTON_B, false)
	await _ticks(40)
	_check(not controller.is_crouching(), "and letting go stands")

	_axis(JOY_AXIS_LEFT_Y, -1.0)
	_button(JOY_BUTTON_LEFT_STICK, true)
	await _ticks(45)
	_check(controller.is_sprinting() and _planar_speed(player) > 7.0, "clicking the left stick sprints (%.2f m/s)" % _planar_speed(player))
	_button(JOY_BUTTON_LEFT_STICK, false)
	_button(JOY_BUTTON_RIGHT_STICK, true)
	await _ticks(45)
	_check(_planar_speed(player) < 2.8, "clicking the right stick strolls (%.2f m/s)" % _planar_speed(player))
	_button(JOY_BUTTON_RIGHT_STICK, false)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _ticks(30)


func _test_looking(rotator: Rotator) -> void:
	var start := rotator.get_predicted_look()
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(30)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var turned := rad_to_deg(rotator.get_predicted_look().x - start.x)
	_check(absf(turned + 100.0) < 12.0, "the stick all the way right turns right at about 200 degrees a second (%.1f in half a second)" % turned)
	_check(absf(rad_to_deg(rotator.get_predicted_look().y - start.y)) < 0.01, "without tilting the view")

	start = rotator.get_predicted_look()
	_axis(JOY_AXIS_RIGHT_X, -1.0)
	await _frames(30)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check(rotator.get_predicted_look().x - start.x > 0.0, "stick left turns left")

	# A gentle push turns far slower than half the full speed: the curve gives fine control.
	start = rotator.get_predicted_look()
	_axis(JOY_AXIS_RIGHT_X, 0.6)
	await _frames(30)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var gentle := absf(rad_to_deg(rotator.get_predicted_look().x - start.x))
	_check(gentle > 10.0 and gentle < 40.0, "a gentle push turns slowly (%.1f degrees in half a second, against 100 at full)" % gentle)

	start = rotator.get_predicted_look()
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(20)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	var looked_up := rad_to_deg(rotator.get_predicted_look().y - start.y)
	_check(looked_up > 25.0 and looked_up < 60.0, "stick up looks up, a bit slower than turning (%.1f degrees)" % looked_up)

	start = rotator.get_predicted_look()
	Settings.set_setting(&"controls.invert_mouse_y", true, false)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(20)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_check(rotator.get_predicted_look().y - start.y < -0.1, "inverting the vertical axis flips it")
	Settings.set_setting(&"controls.invert_mouse_y", false, false)

	start = rotator.get_predicted_look()
	Settings.set_setting(&"controls.controller_sensitivity", 2.0, false)
	_axis(JOY_AXIS_RIGHT_X, 0.8)
	await _frames(15)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var doubled := absf(rad_to_deg(rotator.get_predicted_look().x - start.x))
	Settings.set_setting(&"controls.controller_sensitivity", 1.0, false)
	start = rotator.get_predicted_look()
	_axis(JOY_AXIS_RIGHT_X, 0.8)
	await _frames(15)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var normal := absf(rad_to_deg(rotator.get_predicted_look().x - start.x))
	_check(absf(doubled / maxf(normal, 0.001) - 2.0) < 0.15, "doubling the sensitivity doubles the turning (%.1f against %.1f)" % [doubled, normal])

	_axis(JOY_AXIS_RIGHT_X, 0.1)
	await _frames(30)
	start = rotator.get_predicted_look()
	await _frames(30)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var drift := absf(rad_to_deg(rotator.get_predicted_look().x - start.x))
	_check(drift < 0.05, "a resting stick does not turn the view (%.3f degrees in half a second)" % drift)

	# Not while a menu has the mouse, and not while something blocks looking.
	start = rotator.get_predicted_look()
	InGameUIHandler.is_ui_open = true
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(20)
	_check(is_equal_approx(rotator.get_predicted_look().x, start.x), "the stick does not turn the view while a menu is open")
	InGameUIHandler.is_ui_open = false
	rotator.can_look_around.add(77, "test")
	start = rotator.get_predicted_look()
	await _frames(20)
	_check(is_equal_approx(rotator.get_predicted_look().x, start.x), "or while looking is blocked")
	rotator.can_look_around.remove(77)
	await _frames(10)
	_check(not is_equal_approx(rotator.get_predicted_look().x, start.x), "and works again once it is not")
	_axis(JOY_AXIS_RIGHT_X, 0.0)


# --- Helpers -----------------------------------------------------------------

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_everything() -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		_axis(axis, 0.0)
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
		_button(button, false)


func _planar_speed(player: CharacterBody3D) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


## Waits whole rendered frames. Looking turns once per frame, and the engine may fit extra
## physics ticks into a slow frame, so counting ticks would not be counting turns.
func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
