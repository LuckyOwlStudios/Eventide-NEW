class_name PlayerCharacterController
extends CharacterController
## Lets a player control a character.
##
## Reads the Input Map and the player's look direction and turns them into a
## [MoveIntent]; the [CharacterController] it extends does the moving. Button
## presses are latched from input events so a tap is never lost between physics ticks.

@export_group("Look")
## Supplies the heading that movement is steered along. Without one the
## character moves along its body's forward direction.
@export var rotator: Rotator

@export_group("Input Map Actions")
@export var move_left_action: StringName = &"move_left"
@export var move_right_action: StringName = &"move_right"
@export var move_forward_action: StringName = &"move_forward"
@export var move_back_action: StringName = &"move_back"
@export var jump_action: StringName = &"jump"
@export var crouch_action: StringName = &"crouch"
@export var sprint_action: StringName = &"sprint"
@export var stroll_action: StringName = &"stroll"
## Hold this in zero gravity and sideways mouse movement (or the right stick) rolls the character
## instead of turning it. How far the mouse moves is how far the character rolls.
@export var roll_action: StringName = &"roll"

@export_group("Behavior")
## Stops the character from reading any input, for example while a menu is open.
@export var input_enabled := true
## Crouch on one press and stand on the next, instead of holding the key.
@export var crouch_is_toggle := false
## Two jump presses inside this window switch creative flight on or off.
@export_range(0.1, 1.0, 0.05, "suffix:s") var double_tap_window := 0.3

## Mouse movement, as an angle in radians, that has not been turned into roll yet. The character
## rolls no faster than its roll speed, so a quick flick is worked off over the next ticks.
var _roll_mouse_angle := 0.0
var _jump_latched := false
var _flight_toggle_latched := false
var _crouch_toggled := false
var _last_jump_press_msec := -100000


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if (
		motion != null
		and input_enabled
		and is_instance_valid(rotator)
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and NetworkSession.is_local_authority(character)
		and _is_rolling()
	):
		_roll_mouse_angle += motion.relative.x * deg_to_rad(rotator.sensitivity)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or event.is_echo():
		return
	if event.is_action_pressed(jump_action):
		var now := Time.get_ticks_msec()
		if now - _last_jump_press_msec <= roundi(double_tap_window * 1000.0):
			# The second tap is only about flight, so it does not also jump.
			_flight_toggle_latched = true
			_last_jump_press_msec = -100000
		else:
			_jump_latched = true
			_last_jump_press_msec = now
	if crouch_is_toggle and event.is_action_pressed(crouch_action):
		_crouch_toggled = not _crouch_toggled


## Roll only exists in zero gravity. The look is told, so it does not also turn the view sideways.
func _is_rolling() -> bool:
	return not has_gravity and Input.is_action_pressed(roll_action)


## The roll for this tick, from -1 (left) to 1 (right), made of the mouse movement since the last
## tick and the right stick.
func _take_roll(delta: float) -> float:
	if is_instance_valid(rotator):
		rotator.roll_enabled = not has_gravity
	if not _is_rolling():
		_roll_mouse_angle = 0.0
		return 0.0
	var _step := deg_to_rad(roll_speed_degrees) * maxf(delta, 0.0001)
	var from_mouse := clampf(_roll_mouse_angle / _step, -1.0, 1.0)
	_roll_mouse_angle -= from_mouse * _step
	return clampf(from_mouse + Input.get_axis(&"look_left", &"look_right"), -1.0, 1.0)


func poll_intent(_delta: float) -> MoveIntent:
	var intent := MoveIntent.new()
	if not input_enabled:
		_jump_latched = false
		_flight_toggle_latched = false
		return intent
	intent.move = Input.get_vector(
		move_left_action,
		move_right_action,
		move_forward_action,
		move_back_action,
	)
	intent.vertical = Input.get_axis(crouch_action, jump_action)
	intent.roll = _take_roll(_delta)
	if is_instance_valid(rotator):
		var look := rotator.get_predicted_look()
		intent.yaw = look.x
		intent.pitch = look.y
	intent.sprint = Input.is_action_pressed(sprint_action)
	intent.stroll = Input.is_action_pressed(stroll_action)
	intent.crouch = _crouch_toggled if crouch_is_toggle else Input.is_action_pressed(crouch_action)
	intent.jump_pressed = _jump_latched
	intent.toggle_flight = _flight_toggle_latched
	_jump_latched = false
	_flight_toggle_latched = false
	return intent
