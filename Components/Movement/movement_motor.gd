class_name MovementMotor
extends Node
## Shared movement state and input for character and rigid-body movers.

signal movement_mode_changed(previous_mode: MovementMode, current_mode: MovementMode)

enum MovementMode {
	GROUND,
	FLIGHT,
}

const BOOST_MODIFIER_ID := "movement.input.boost"
const SLOW_MODIFIER_ID := "movement.input.slow"
const DOUBLE_TAP_WINDOW := 0.3
const JUMP_BUFFER_TIME := 0.12
const ROLL_SPEED := deg_to_rad(120.0)
const MINIMUM_GRAVITY := 0.001

@export var base_movement_speed := 10.0:
	set(value):
		base_movement_speed = maxf(value, 0.0)
		if movement_speed:
			movement_speed.base_value = base_movement_speed
@export var base_jump_height := 5.5:
	set(value):
		base_jump_height = maxf(value, 0.0)
		if jump_height:
			jump_height.base_value = base_jump_height
## Optional view-relative basis used to turn movement input into world direction.
## Keeping this separate from the physics body lets a local camera turn immediately
## without writing to the CharacterBody3D outside physics ticks.
@export var movement_reference: Node3D
## Allows a double jump press to toggle between ground movement and flight.
@export var toggle_flight := true

var movement_speed := Attribute.new()
var jump_height := Attribute.new()
var boost_modifier := AttributeModifier.new()
var slow_modifier := AttributeModifier.new()
var movement_mode := MovementMode.GROUND
var gravity_vector := Vector3.ZERO
var has_gravity := false
var is_flying: bool:
	get:
		return movement_mode == MovementMode.FLIGHT

var _jump_tap_timer := 0.0
var _jump_buffer_timer := 0.0
var _flight_has_left_ground := false


func _ready() -> void:
	movement_speed.base_value = base_movement_speed
	jump_height.base_value = base_jump_height
	boost_modifier.operation = AttributeModifier.Operation.MULTIPLY_TOTAL
	boost_modifier.amount = 50.0
	slow_modifier.operation = AttributeModifier.Operation.MULTIPLY_TOTAL
	slow_modifier.amount = -50.0


func _input(event: InputEvent) -> void:
	# E is also the interaction key. During zero-gravity flight Q/E belong to roll.
	if is_flying and not has_gravity:
		if event.is_action_pressed("roll"):
			get_viewport().set_input_as_handled()


func set_flying(enabled: bool) -> void:
	var next_mode := MovementMode.FLIGHT if enabled else MovementMode.GROUND
	if next_mode == movement_mode:
		return
	var previous_mode := movement_mode
	movement_mode = next_mode
	_jump_buffer_timer = 0.0
	_flight_has_left_ground = false
	movement_mode_changed.emit(previous_mode, movement_mode)


func set_boosting(enabled: bool) -> void:
	if enabled:
		movement_speed.add_attribute_modifier(BOOST_MODIFIER_ID, boost_modifier)
	else:
		movement_speed.remove_attribute_modifier(BOOST_MODIFIER_ID)


func set_slowing(enabled: bool) -> void:
	if enabled:
		movement_speed.add_attribute_modifier(SLOW_MODIFIER_ID, slow_modifier)
	else:
		movement_speed.remove_attribute_modifier(SLOW_MODIFIER_ID)


func _update_common_input(delta: float) -> void:
	_jump_tap_timer = maxf(_jump_tap_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	var slowing := Input.is_action_pressed("stroll")
	set_slowing(slowing)
	set_boosting(Input.is_action_pressed("sprint") and not slowing)
	if Input.is_action_just_pressed("jump"):
		_handle_jump_press()


func _handle_jump_press() -> void:
	if toggle_flight and _jump_tap_timer > 0.0:
		_jump_tap_timer = 0.0
		set_flying(not is_flying)
		return
	_jump_tap_timer = DOUBLE_TAP_WINDOW
	if not is_flying:
		_jump_buffer_timer = JUMP_BUFFER_TIME


func _update_flight_ground_contact(is_grounded: bool) -> void:
	if not is_flying:
		return
	if not _flight_has_left_ground:
		_flight_has_left_ground = not is_grounded
	elif is_grounded:
		set_flying(false)


func _set_gravity(new_gravity: Vector3) -> void:
	gravity_vector = new_gravity
	has_gravity = gravity_vector.length_squared() > MINIMUM_GRAVITY * MINIMUM_GRAVITY


func _sample_gravity(body: PhysicsBody3D) -> PhysicsDirectBodyState3D:
	var direct_state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	_set_gravity(direct_state.total_gravity if direct_state else _get_default_gravity())
	return direct_state


func _get_up_direction(body: Node3D) -> Vector3:
	if has_gravity:
		return -gravity_vector.normalized()
	var body_up := body.global_basis.y.normalized()
	return body_up if not body_up.is_zero_approx() else Vector3.UP


func _get_ground_direction(body: Node3D, up: Vector3) -> Vector3:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back",
	)
	if input_direction.is_zero_approx():
		return Vector3.ZERO
	var local_direction := Vector3(input_direction.x, 0.0, input_direction.y)
	var world_direction := _get_movement_basis(body) * local_direction
	world_direction = world_direction.slide(up)
	if world_direction.is_zero_approx():
		return Vector3.ZERO
	return world_direction.normalized() * minf(input_direction.length(), 1.0)


func _get_flight_direction(body: Node3D) -> Vector3:
	var horizontal_input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back",
	)
	var vertical_input := Input.get_axis("crouch", "jump")
	var local_direction := Vector3(horizontal_input.x, vertical_input, horizontal_input.y)
	if local_direction.length_squared() > 1.0:
		local_direction = local_direction.normalized()
	return _get_movement_basis(body) * local_direction


func _get_movement_basis(body: Node3D) -> Basis:
	var reference := movement_reference if is_instance_valid(movement_reference) else body
	return reference.global_basis.orthonormalized()


func _get_roll_input() -> float:
	return Input.get_action_strength("roll") if not has_gravity else 0.0


func _consume_jump_request(can_jump: bool) -> bool:
	if _jump_buffer_timer <= 0.0 or not can_jump:
		return false
	_jump_buffer_timer = 0.0
	return true

func _get_jump_speed() -> float:
	var gravity_strength := maxf(gravity_vector.length(), _get_default_gravity().length())
	return sqrt(2.0 * gravity_strength * jump_height.value)

func _get_default_gravity() -> Vector3:
	var direction: Vector3 = ProjectSettings.get_setting(
		"physics/3d/default_gravity_vector",
		Vector3.DOWN,
	)
	var strength := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	return direction.normalized() * strength

func _exponential_weight(speed: float, delta: float) -> float:
	return 1.0 if speed <= 0.0 else 1.0 - exp(-speed * delta)
