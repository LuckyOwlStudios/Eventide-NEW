class_name AICharacterController
extends CharacterController
## Lets code control a character: NPCs, enemies, cutscenes.
##
## Nothing in here decides what to do. A brain (a behavior tree, a state machine,
## anything) steers by setting the values below or calling the helpers, and this class
## turns them into the same [MoveIntent] a player produces. That means an AI walks,
## sprints, crouches and jumps by exactly the same rules, speeds and stamina costs as
## a player, and works with [CharacterNetSync] the same way: the server runs it and
## everyone else sees the result.
## [codeblock]
## npc.move_to(Vector3(4, 0, -12))
## await npc.destination_reached
## npc.wants_crouch = true
## [/codeblock]

## Emitted when [method move_to] gets the character within [member arrive_distance].
signal destination_reached

## How close counts as arrived when walking to a destination.
@export_range(0.05, 5.0, 0.05, "suffix:m") var arrive_distance := 0.5
## Sprints while walking to a destination.
@export var sprint_to_destination := false

## The movement stick, like a player's: X is right, Y is back, so forward is -Y.
## Ignored while walking to a destination.
var move_input := Vector2.ZERO
## Up and down thrust for flight and jetpacks, from -1 to 1.
var vertical_input := 0.0
## Roll in zero gravity, from -1 (left) to 1 (right).
var roll_input := 0.0
## Which way the character is facing, in radians relative to its body. Movement is
## steered along this. [method face_position] sets it, and so does [method move_to].
var look_yaw := 0.0
## Looking up (positive) or down, in radians.
var look_pitch := 0.0
var wants_sprint := false
## The slow walk.
var wants_stroll := false
var wants_crouch := false

var _destination := Vector3.ZERO
var _has_destination := false
var _jump_requested := false
var _flight_toggle_requested := false


func poll_intent(_delta: float) -> MoveIntent:
	if _has_destination:
		_steer_toward_destination()
	var intent := MoveIntent.new()
	intent.move = move_input
	intent.vertical = vertical_input
	intent.roll = roll_input
	intent.yaw = look_yaw
	intent.pitch = look_pitch
	intent.sprint = wants_sprint or (_has_destination and sprint_to_destination)
	intent.stroll = wants_stroll
	intent.crouch = wants_crouch
	intent.jump_pressed = _jump_requested
	intent.toggle_flight = _flight_toggle_requested
	_jump_requested = false
	_flight_toggle_requested = false
	return intent


## Walks toward [param world_position] in a straight line until it is within
## [member arrive_distance], then stops and emits [signal destination_reached].
## Steering around obstacles is up to the brain, which can call this with each
## point of a path in turn.
func move_to(world_position: Vector3) -> void:
	_destination = world_position
	_has_destination = true


## Stops walking to a destination and lets go of the movement stick.
func stop() -> void:
	_has_destination = false
	move_input = Vector2.ZERO


func is_moving_to_destination() -> bool:
	return _has_destination


## Turns to face [param world_position], including looking up or down at it.
func face_position(world_position: Vector3) -> void:
	var body := get_body()
	if body == null:
		return
	var offset := _to_body_space(world_position)
	var planar := Vector2(offset.x, offset.z).length()
	if planar > 0.0001:
		look_yaw = atan2(-offset.x, -offset.z)
	look_pitch = clampf(atan2(offset.y, planar), -PI / 2.0, PI / 2.0)


## Presses jump for one tick.
func jump() -> void:
	_jump_requested = true


## Switches creative flight on or off, where the character is allowed it.
func toggle_flight() -> void:
	_flight_toggle_requested = true


func _steer_toward_destination() -> void:
	var offset := _to_body_space(_destination)
	offset.y = 0.0
	if offset.length() <= arrive_distance:
		stop()
		destination_reached.emit()
		return
	look_yaw = atan2(-offset.x, -offset.z)
	move_input = Vector2(0.0, -1.0)


## [param world_position] as seen from the body: X right, Y up, -Z ahead.
func _to_body_space(world_position: Vector3) -> Vector3:
	var body := get_body()
	return body.global_basis.orthonormalized().inverse() * (world_position - body.global_position)
