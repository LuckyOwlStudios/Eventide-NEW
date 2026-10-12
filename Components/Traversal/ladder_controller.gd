@icon("uid://q7r8rnoxg654")
class_name LadderController
extends Node
## Actor-side ladder component. It carries its CharacterBody3D parent onto a
## Ladder3D, moves it along the ladder, and eases the body and camera on and off.

signal ladder_mounted(ladder: Ladder3D, climb_height: float)
signal ladder_dismounted(
	ladder: Ladder3D,
	dismount_type: Ladder3D.DismountType,
	destination: Transform3D,
)

enum State {
	IDLE,
	MOUNTING,
	CLIMBING,
	DISMOUNTING,
}

@export_category("Actor Components")
@export var character_controller: Node
@export var orientation_component: Node
@export var interaction_ray: InteractionRayCast3D
## Keeps the interaction ray working on the ladder so other objects, like a hatch
## at the top, can still be used. When off, interaction is disabled while on a ladder.
@export var allow_interaction_while_on_ladder := true
## Used to turn the camera smoothly. Found next to this node when left empty.
@export var player_rotator: Rotator
## Ladders cannot be mounted while this controller is seated.
@export var seat_controller: SeatController

@export_category("Input")
@export var climb_up_action: StringName = &"move_forward"
@export var climb_down_action: StringName = &"move_back"
@export var sprint_action: StringName = &"sprint"
## Lets go of the ladder where you are and hops backward.
@export var jump_off_action: StringName = &"jump"

@export_category("Climbing")
## Speed multiplier while sprint is held and moving down the ladder.
@export_range(1.0, 5.0, 0.05) var sprint_descent_multiplier := 3.5
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var jump_off_speed := 3.0
## Total horizontal look arc while on the ladder (180 = 90 degrees either side).
@export_range(30.0, 360.0, 1.0, "suffix:deg") var look_yaw_limit := 180.0

@export_category("Transitions")
@export_range(0.0, 3.0, 0.01, "suffix:s") var mount_duration := 0.25
@export_range(0.0, 3.0, 0.01, "suffix:s") var dismount_duration := 0.25

var state := State.IDLE
var current_ladder: Ladder3D

var _body: CharacterBody3D
var _climb_height := 0.0
var _exiting_ladder: Ladder3D
var _exit_type := Ladder3D.DismountType.TOP

var _saved_collision_layer := 0
var _saved_collision_mask := 0
var _saved_interpolation_mode := Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _saved_maximum_yaw := 360.0
var _saved_process_modes: Dictionary = {}
var _interaction_was_enabled := true

var _transition_elapsed := 0.0
var _transition_duration := 0.0
var _transition_from := Transform3D.IDENTITY
var _transition_camera_basis := Basis.IDENTITY


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("LadderController must be a direct child of a CharacterBody3D.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	if not is_instance_valid(player_rotator):
		player_rotator = _body.get_node_or_null("Rotator") as Rotator
	set_process(false)


func _exit_tree() -> void:
	if state != State.IDLE:
		abort_climb()


func _process(delta: float) -> void:
	match state:
		State.MOUNTING, State.DISMOUNTING:
			_tick_transition(delta)
		State.CLIMBING:
			_tick_climb(delta)


func _unhandled_input(event: InputEvent) -> void:
	if state != State.CLIMBING or not is_local_controller():
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(jump_off_action):
		jump_off()
		get_viewport().set_input_as_handled()


# --- Public API --------------------------------------------------------------

## True while mounting, climbing or dismounting.
func is_on_ladder() -> bool:
	return state != State.IDLE


## True only while the actor is fully on the ladder and under climb control.
func is_climbing() -> bool:
	return state == State.CLIMBING


func get_body() -> CharacterBody3D:
	return _body


## Distance from the bottom of the ladder in meters.
func get_climb_height() -> float:
	return _climb_height if state != State.IDLE else 0.0


## Position on the ladder from 0 (bottom) to 1 (top). Returns 0 when not on a ladder.
func get_climb_progress() -> float:
	var ladder := current_ladder if is_instance_valid(current_ladder) else _exiting_ladder
	if state == State.IDLE or not is_instance_valid(ladder):
		return 0.0
	return ladder.height_to_progress(_climb_height)


func can_mount(ladder: Ladder3D) -> bool:
	return (
		_body != null
		and state == State.IDLE
		and is_instance_valid(ladder)
		and is_local_controller()
		and not (is_instance_valid(seat_controller) and is_instance_valid(seat_controller.current_seat))
		and ladder.can_be_climbed_by(self)
	)


## Starts mounting [param ladder] at [param climb_height] meters from its bottom.
func mount(ladder: Ladder3D, climb_height: float) -> bool:
	if not can_mount(ladder):
		return false
	climb_height = clampf(climb_height, 0.0, ladder.height)
	if not ladder.claim_climber(self, climb_height):
		return false
	current_ladder = ladder
	_climb_height = climb_height
	_capture_actor()
	_begin_transition(State.MOUNTING, mount_duration)
	ladder_mounted.emit(ladder, climb_height)
	return true


## Leaves through the top or bottom, easing to the ladder's dismount position.
## The actor keeps facing the ladder.
func dismount(dismount_type: Ladder3D.DismountType) -> bool:
	if state != State.CLIMBING or not is_instance_valid(current_ladder):
		return false
	if dismount_type == Ladder3D.DismountType.JUMP_OFF:
		return jump_off()
	var ladder := current_ladder
	var destination := Transform3D(
		_body.global_basis.orthonormalized(),
		ladder.get_dismount_transform(dismount_type).origin,
	)
	_climb_height = ladder.height if dismount_type == Ladder3D.DismountType.TOP else 0.0
	_exiting_ladder = ladder
	_exit_type = dismount_type
	current_ladder = null
	ladder.release_climber(self, dismount_type, destination)
	_begin_transition(State.DISMOUNTING, dismount_duration)
	ladder_dismounted.emit(ladder, dismount_type, destination)
	return true


## Lets go immediately and pushes away from the ladder.
func jump_off() -> bool:
	if state != State.CLIMBING or not is_instance_valid(current_ladder):
		return false
	var ladder := current_ladder
	var destination := _body.global_transform
	var away := ladder.global_basis.z.normalized()
	current_ladder = null
	ladder.release_climber(self, Ladder3D.DismountType.JUMP_OFF, destination)
	_finish_exit()
	_body.velocity = away * jump_off_speed
	ladder_dismounted.emit(ladder, Ladder3D.DismountType.JUMP_OFF, destination)
	return true


## Drops off in place without any transition. Used when the ladder disappears.
func abort_climb() -> void:
	if state == State.IDLE:
		return
	var ladder := current_ladder
	var destination := _body.global_transform if is_instance_valid(_body) else Transform3D.IDENTITY
	current_ladder = null
	if is_instance_valid(ladder):
		ladder.release_climber(self, Ladder3D.DismountType.JUMP_OFF, destination)
		ladder_dismounted.emit(ladder, Ladder3D.DismountType.JUMP_OFF, destination)
	_finish_exit()


func is_local_controller() -> bool:
	if _body == null:
		_body = get_parent() as CharacterBody3D
	if _body == null:
		return false
	return NetworkSession.is_local_authority(_body)


static func find_on_actor(actor: Node) -> LadderController:
	if actor == null:
		return null
	if actor is LadderController:
		return actor as LadderController
	var named := actor.get_node_or_null("LadderController") as LadderController
	if is_instance_valid(named):
		return named
	for child in actor.get_children():
		if child is LadderController:
			return child as LadderController
	return null


# --- Per frame ---------------------------------------------------------------

func _tick_climb(delta: float) -> void:
	if not is_instance_valid(current_ladder):
		abort_climb()
		return
	var axis := Input.get_axis(climb_down_action, climb_up_action)
	var speed := current_ladder.climb_speed
	if axis < 0.0 and Input.is_action_pressed(sprint_action):
		speed *= sprint_descent_multiplier
	var next_height := _climb_height + axis * speed * delta
	if axis > 0.0 and next_height >= current_ladder.height:
		dismount(Ladder3D.DismountType.TOP)
		return
	if axis < 0.0 and next_height <= 0.0:
		dismount(Ladder3D.DismountType.BOTTOM)
		return
	_climb_height = clampf(next_height, 0.0, current_ladder.height)
	_body.global_transform = current_ladder.get_climb_transform(_climb_height)
	_body.velocity = Vector3.ZERO


func _tick_transition(delta: float) -> void:
	var ladder := current_ladder if state == State.MOUNTING else _exiting_ladder
	if not is_instance_valid(ladder):
		abort_climb()
		return
	_transition_elapsed += delta
	var t := 1.0
	if _transition_duration > 0.0:
		t = clampf(_transition_elapsed / _transition_duration, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)

	# The target is read every frame so a moving ladder (on a ship, say) is tracked.
	var target := _get_transition_target(ladder)
	var target_rotation := target.basis.orthonormalized().get_rotation_quaternion()
	var body_rotation := _transition_from.basis.get_rotation_quaternion().slerp(
		target_rotation, eased
	)
	var body_basis := Basis(body_rotation)
	_body.global_transform = Transform3D(
		body_basis,
		_transition_from.origin.lerp(target.origin, eased),
	)
	_body.velocity = Vector3.ZERO

	# Mounting turns the camera toward the ladder on its own curve. Turning the
	# body moves the camera, so the Rotator's yaw is set to make up the difference.
	# Dismounting never turns anything, so there is nothing to correct.
	if state == State.MOUNTING:
		var camera_basis := Basis(
			_transition_camera_basis.get_rotation_quaternion().slerp(target_rotation, eased)
		)
		_apply_camera_basis(camera_basis, body_basis)

	if t >= 1.0:
		if state == State.MOUNTING:
			_finish_mount()
		else:
			_finish_exit()
			_exiting_ladder = null


func _get_transition_target(ladder: Ladder3D) -> Transform3D:
	if state == State.MOUNTING:
		return ladder.get_climb_transform(_climb_height)
	# Only the position changes when leaving; the actor keeps its orientation.
	return Transform3D(
		_transition_from.basis,
		ladder.get_dismount_transform(_exit_type).origin,
	)


func _begin_transition(next_state: State, duration: float) -> void:
	state = next_state
	_transition_elapsed = 0.0
	_transition_duration = duration
	_transition_from = _body.global_transform.orthonormalized()
	_transition_camera_basis = _transition_from.basis * Basis(Vector3.UP, _get_relative_yaw())
	set_process(true)


func _finish_mount() -> void:
	state = State.CLIMBING
	_body.global_transform = current_ladder.get_climb_transform(_climb_height)
	_apply_camera_basis(_body.global_basis, _body.global_basis)
	if is_instance_valid(player_rotator):
		player_rotator.maximum_yaw = look_yaw_limit


# --- Camera ------------------------------------------------------------------

func _get_relative_yaw() -> float:
	return player_rotator.get_predicted_look().x if is_instance_valid(player_rotator) else 0.0


## Makes the view look along [param camera_basis]'s heading while the body sits at
## [param body_basis], by setting the Rotator's yaw relative to the body.
func _apply_camera_basis(camera_basis: Basis, body_basis: Basis) -> void:
	if not is_instance_valid(player_rotator):
		return
	var relative := body_basis.orthonormalized().inverse() * camera_basis
	var yaw := atan2(relative.z.x, relative.z.z)
	player_rotator.add_look_input(angle_difference(_get_relative_yaw(), yaw), 0.0)


# --- Actor state -------------------------------------------------------------

func _capture_actor() -> void:
	_saved_collision_layer = _body.collision_layer
	_saved_collision_mask = _body.collision_mask
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.velocity = Vector3.ZERO
	# The body is driven from _process, in step with the camera, not on physics ticks.
	_saved_interpolation_mode = _body.physics_interpolation_mode
	_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	_saved_process_modes.clear()
	_lock_movement()
	_disable_component(orientation_component)
	if not allow_interaction_while_on_ladder and is_instance_valid(interaction_ray):
		_interaction_was_enabled = interaction_ray.interaction_enabled
		interaction_ray.interaction_enabled = false
		_disable_component(interaction_ray)
	if is_instance_valid(player_rotator):
		_saved_maximum_yaw = player_rotator.maximum_yaw
		player_rotator.maximum_yaw = 360.0


## Returns control to the player. Shared by every way of leaving the ladder.
func _finish_exit() -> void:
	state = State.IDLE
	set_process(false)
	if not is_instance_valid(_body):
		return
	_body.collision_layer = _saved_collision_layer
	_body.collision_mask = _saved_collision_mask
	_body.velocity = Vector3.ZERO
	_body.physics_interpolation_mode = _saved_interpolation_mode
	_body.reset_physics_interpolation()
	_restore_components()
	_unlock_movement()
	if not allow_interaction_while_on_ladder and is_instance_valid(interaction_ray):
		interaction_ray.interaction_enabled = _interaction_was_enabled
	if is_instance_valid(player_rotator):
		player_rotator.maximum_yaw = _saved_maximum_yaw
	_exiting_ladder = null


## Stops the actor from moving itself. A CharacterController has a proper lock; anything
## else is simply switched off.
func _lock_movement() -> void:
	if character_controller is CharacterController:
		(character_controller as CharacterController).movement_blocker.add(get_instance_id(), "ladder")
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
