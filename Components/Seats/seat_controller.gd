class_name SeatController
extends Node
## Actor-side seating component. It locks its CharacterBody3D parent to a Seat3D.
##
## Sitting down turns the actor to face the way the seat faces and eases them to it, camera and all, in
## the seat's [member Seat3D.transition_time] (none at all for a vehicle seat). Standing up eases them
## to the seat's dismount point, keeping the view pointed where it was.

signal seat_entered(seat: Node)
signal seat_exited(seat: Node)

enum Move {
	NONE,
	ENTERING,
	EXITING,
}

@export_category("Actor Components")
@export var character_controller: Node
@export var player_rotator: Node
@export var orientation_component: Node
@export var interaction_ray: InteractionRayCast3D

@export_category("Input")
@export var exit_seat_action: StringName = &"dismount_vehicle"

var current_seat: Node

var _body: CharacterBody3D
var _saved_collision_layer := 0
var _saved_collision_mask := 0
var _saved_process_modes: Dictionary = {}
var _interaction_was_enabled := true
## The Rotator's own limits, while a seat's are in force.
var _saved_look: Dictionary = {}

var _move := Move.NONE
var _move_seat: Node
var _move_elapsed := 0.0
var _move_duration := 0.0
var _move_from := Transform3D.IDENTITY
var _move_camera_basis := Basis.IDENTITY
var _move_from_pitch := 0.0
var _saved_interpolation_mode := Node.PHYSICS_INTERPOLATION_MODE_INHERIT


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("SeatController must be a direct child of a CharacterBody3D.")
		set_process_input(false)
		set_physics_process(false)
	set_process(false)


func _process(delta: float) -> void:
	_tick_move(delta)


func _physics_process(_delta: float) -> void:
	if _move != Move.NONE or not is_instance_valid(current_seat) or _body == null:
		return
	_body.global_transform = current_seat.get_seat_transform()
	_body.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(current_seat) or _move != Move.NONE or not is_local_controller():
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(exit_seat_action):
		exit_seat()
		get_viewport().set_input_as_handled()


func enter_seat(seat: Node) -> bool:
	if (
		not is_local_controller()
		or _move != Move.NONE
		or is_instance_valid(current_seat)
		or not is_instance_valid(seat)
		or not seat.claim_occupancy(self)
	):
		return false

	current_seat = seat
	_saved_collision_layer = _body.collision_layer
	_saved_collision_mask = _body.collision_mask
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.velocity = Vector3.ZERO

	_saved_process_modes.clear()
	_lock_movement()
	_disable_component(orientation_component)
	if is_instance_valid(interaction_ray):
		_interaction_was_enabled = interaction_ray.interaction_enabled
		interaction_ray.interaction_enabled = false
		_disable_component(interaction_ray)

	_on_seat_entered(seat)
	seat_entered.emit(seat)
	_begin_move(Move.ENTERING, seat)
	return true


func exit_seat() -> bool:
	if not is_instance_valid(current_seat) or _move != Move.NONE:
		return false
	var previous := current_seat
	if not previous.release_occupancy(self):
		return false

	current_seat = null
	_restore_look()
	_begin_move(Move.EXITING, previous)
	return true


## True while easing into or out of a seat.
func is_moving_to_seat() -> bool:
	return _move != Move.NONE


func is_local_controller() -> bool:
	if _body == null:
		_body = get_parent() as CharacterBody3D
	if _body == null:
		return false
	return NetworkSession.is_local_authority(_body)


static func find_on_actor(actor: Node) -> SeatController:
	if actor == null:
		return null
	if actor is SeatController:
		return actor as SeatController
	var named_controller := actor.get_node_or_null("SeatController") as SeatController
	if is_instance_valid(named_controller):
		return named_controller
	named_controller = actor.get_node_or_null("VehicleController") as SeatController
	if is_instance_valid(named_controller):
		return named_controller
	for child in actor.get_children():
		if child is SeatController:
			return child as SeatController
	return null


## Hooks for controllers that add behavior such as vehicle camera switching.
func _on_seat_entered(_seat: Node) -> void:
	pass


func _on_seat_exited(_seat: Node) -> void:
	pass


# --- Easing into and out of the seat -----------------------------------------

func _begin_move(kind: Move, seat: Node) -> void:
	_move = kind
	_move_seat = seat
	_move_elapsed = 0.0
	_move_duration = (seat as Seat3D).transition_time if seat is Seat3D else 0.0
	if _move_duration <= 0.0:
		_finish_move()
		return
	_move_from = _body.global_transform.orthonormalized()
	var look := _get_look()
	_move_camera_basis = _move_from.basis * Basis(Vector3.UP, look.x)
	_move_from_pitch = look.y
	# The body is driven from _process, in step with the camera.
	_saved_interpolation_mode = _body.physics_interpolation_mode
	_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(true)


func _tick_move(delta: float) -> void:
	if not is_instance_valid(_move_seat) or _body == null:
		_finish_move()
		return
	_move_elapsed += delta
	var t := clampf(_move_elapsed / _move_duration, 0.0, 1.0) if _move_duration > 0.0 else 1.0
	var eased := smoothstep(0.0, 1.0, t)
	# The target is read every frame, so a seat on a moving ship is followed.
	var target := _move_target()
	var target_rotation := target.basis.orthonormalized().get_rotation_quaternion()
	var body_basis := Basis(_move_from.basis.get_rotation_quaternion().slerp(target_rotation, eased))
	_body.global_transform = Transform3D(body_basis, _move_from.origin.lerp(target.origin, eased))
	_body.velocity = Vector3.ZERO
	if _move == Move.ENTERING:
		# Turning the body turns the camera with it, so the view is set to make up the difference: it
		# swings to the way the seat faces, and levels out, on the same curve as the body.
		var camera_basis := Basis(_move_camera_basis.get_rotation_quaternion().slerp(target_rotation, eased))
		_set_view(camera_basis, body_basis, lerpf(_move_from_pitch, 0.0, eased))
	else:
		_set_view(_move_camera_basis, body_basis, _move_from_pitch)
	if t >= 1.0:
		_finish_move()


func _move_target() -> Transform3D:
	if _move == Move.ENTERING:
		return _move_seat.get_seat_transform()
	return _move_seat.get_dismount_transform()


func _finish_move() -> void:
	set_process(false)
	if _body == null:
		_move = Move.NONE
		return
	if is_instance_valid(_move_seat):
		_body.global_transform = _move_target()
	_body.velocity = Vector3.ZERO
	if _move_duration > 0.0:
		_body.physics_interpolation_mode = _saved_interpolation_mode
	_body.reset_physics_interpolation()
	if _move == Move.ENTERING:
		_finish_enter()
	else:
		_finish_exit()


func _finish_enter() -> void:
	var seat := _move_seat
	_move = Move.NONE
	_move_seat = null
	if not is_instance_valid(seat):
		return
	# Facing the way the seat faces, level.
	var basis := _body.global_basis
	_set_view(basis, basis, 0.0)
	if _seat_lets_occupant_look(seat):
		_limit_look(seat)
	else:
		_disable_component(player_rotator)


func _finish_exit() -> void:
	var previous := _move_seat
	_move = Move.NONE
	_move_seat = null
	_body.collision_layer = _saved_collision_layer
	_body.collision_mask = _saved_collision_mask
	_body.velocity = Vector3.ZERO
	_restore_components()
	_unlock_movement()
	if is_instance_valid(interaction_ray):
		interaction_ray.interaction_enabled = _interaction_was_enabled
	_on_seat_exited(previous)
	seat_exited.emit(previous)


func _get_look() -> Vector2:
	return (player_rotator as Rotator).get_predicted_look() if player_rotator is Rotator else Vector2.ZERO


## Points the view along [param camera_basis]'s heading with the body at [param body_basis], by setting the
## Rotator's yaw relative to the body, and tips it to [param pitch].
func _set_view(camera_basis: Basis, body_basis: Basis, pitch: float) -> void:
	if not player_rotator is Rotator:
		return
	var rotator := player_rotator as Rotator
	var relative := body_basis.orthonormalized().inverse() * camera_basis
	var yaw := atan2(relative.z.x, relative.z.z)
	var look := rotator.get_predicted_look()
	rotator.add_look_input(angle_difference(look.x, yaw), pitch - look.y)


# --- Looking from the seat ---------------------------------------------------

func _seat_lets_occupant_look(seat: Node) -> bool:
	return player_rotator is Rotator and seat is Seat3D and (seat as Seat3D).can_occupant_look()


## Lets the occupant look around within the seat's limits (they are already facing the way it does).
func _limit_look(seat: Seat3D) -> void:
	var rotator := player_rotator as Rotator
	_saved_look = {
		"maximum_yaw": rotator.maximum_yaw,
		"minimum_pitch": rotator.minimum_pitch,
		"maximum_pitch": rotator.maximum_pitch,
	}
	rotator.maximum_yaw = seat.look_yaw_arc
	rotator.minimum_pitch = seat.look_minimum_pitch
	rotator.maximum_pitch = seat.look_maximum_pitch


func _restore_look() -> void:
	if _saved_look.is_empty() or not player_rotator is Rotator:
		_saved_look.clear()
		return
	var rotator := player_rotator as Rotator
	rotator.maximum_yaw = _saved_look["maximum_yaw"]
	rotator.minimum_pitch = _saved_look["minimum_pitch"]
	rotator.maximum_pitch = _saved_look["maximum_pitch"]
	_saved_look.clear()


# --- Actor state -------------------------------------------------------------

## Stops the actor from moving itself. A CharacterController has a proper lock; anything
## else is simply switched off.
func _lock_movement() -> void:
	if character_controller is CharacterController:
		(character_controller as CharacterController).movement_blocker.add(get_instance_id(), "seat")
	else:
		_disable_component(character_controller)


func _unlock_movement() -> void:
	if character_controller is CharacterController:
		(character_controller as CharacterController).movement_blocker.remove(get_instance_id())


func _disable_component(component: Node) -> void:
	if not is_instance_valid(component) or _saved_process_modes.has(component):
		return
	_saved_process_modes[component] = component.process_mode
	component.process_mode = Node.PROCESS_MODE_DISABLED


func _restore_components() -> void:
	for component: Node in _saved_process_modes:
		if is_instance_valid(component):
			@warning_ignore("int_as_enum_without_cast")
			component.process_mode = int(_saved_process_modes[component])
	_saved_process_modes.clear()
