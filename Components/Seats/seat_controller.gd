class_name SeatController
extends Node
## Actor-side seating component. It locks its CharacterBody3D parent to a Seat3D.

signal seat_entered(seat: Node)
signal seat_exited(seat: Node)

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


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("SeatController must be a direct child of a CharacterBody3D.")
		set_process_input(false)
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(current_seat) or _body == null:
		return
	_body.global_transform = current_seat.get_seat_transform()
	_body.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(current_seat) or not is_local_controller():
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(exit_seat_action):
		exit_seat()
		get_viewport().set_input_as_handled()


func enter_seat(seat: Node) -> bool:
	if (
		not is_local_controller()
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
	_body.global_transform = seat.get_seat_transform()
	_body.reset_physics_interpolation()

	_saved_process_modes.clear()
	_lock_movement()
	_disable_component(player_rotator)
	_disable_component(orientation_component)
	if is_instance_valid(interaction_ray):
		_interaction_was_enabled = interaction_ray.interaction_enabled
		interaction_ray.interaction_enabled = false
		_disable_component(interaction_ray)

	_on_seat_entered(seat)
	seat_entered.emit(seat)
	return true


func exit_seat() -> bool:
	if not is_instance_valid(current_seat):
		return false
	var previous := current_seat
	var exit_transform: Transform3D = previous.get_dismount_transform()
	if not previous.release_occupancy(self):
		return false

	current_seat = null
	_body.global_transform = exit_transform
	_body.reset_physics_interpolation()
	_body.velocity = Vector3.ZERO
	_body.collision_layer = _saved_collision_layer
	_body.collision_mask = _saved_collision_mask
	_restore_components()
	_unlock_movement()
	if is_instance_valid(interaction_ray):
		interaction_ray.interaction_enabled = _interaction_was_enabled

	_on_seat_exited(previous)
	seat_exited.emit(previous)
	return true


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
