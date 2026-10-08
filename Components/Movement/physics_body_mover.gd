class_name PhysicsBodyMover
extends MovementMotor
## Ground and flight movement for a parent RigidBody3D.

const COYOTE_TIME := 0.12
const FLOOR_MAX_ANGLE := deg_to_rad(46.0)
const GROUND_ACCELERATION := 18.0
const FLIGHT_ACCELERATION := 8.0
const ROLL_ACCELERATION := 10.0

var _body: RigidBody3D
var _coyote_timer := 0.0

func _ready() -> void:
	super._ready()
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("PhysicsBodyMover must be a direct child of a RigidBody3D.")
		set_physics_process(false)
		return
	_body.contact_monitor = true
	_body.max_contacts_reported = maxi(_body.max_contacts_reported, 8)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body):
		set_physics_process(false)
		return

	var direct_state := _sample_gravity(_body)
	if direct_state == null:
		return
	_update_common_input(delta)
	var up := _get_up_direction(_body)
	var is_grounded := _is_grounded(direct_state, up)
	if is_flying:
		_move_flying(delta, is_grounded)
	else:
		_move_on_ground(delta, up, is_grounded)

func _move_on_ground(delta: float, up: Vector3, is_grounded: bool) -> void:
	if is_grounded:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	var planar_velocity := _body.linear_velocity.slide(up)
	var target_velocity := _get_ground_direction(_body, up) * movement_speed.value
	var desired_acceleration := (target_velocity - planar_velocity) * GROUND_ACCELERATION
	_body.apply_central_force(desired_acceleration * _body.mass)

	if _consume_jump_request(_coyote_timer > 0.0):
		_body.apply_central_impulse(up * _get_jump_speed() * _body.mass)
		_coyote_timer = 0.0

func _move_flying(delta: float, is_grounded: bool) -> void:
	# Cancel effective gravity so directional flight can hold position.
	if has_gravity:
		_body.apply_central_force(-gravity_vector * _body.mass)
	var target_velocity := _get_flight_direction(_body) * movement_speed.value
	var desired_acceleration := (target_velocity - _body.linear_velocity) * FLIGHT_ACCELERATION
	_body.apply_central_force(desired_acceleration * _body.mass)

	var roll_input := _get_roll_input()
	if not is_zero_approx(roll_input):
		var roll_axis := _body.global_basis.orthonormalized() * Vector3.FORWARD
		var current_roll_speed := _body.angular_velocity.dot(roll_axis)
		var target_roll_speed := roll_input * ROLL_SPEED
		var roll_change := (target_roll_speed - current_roll_speed) * ROLL_ACCELERATION * delta
		_body.angular_velocity += roll_axis * roll_change

	_update_flight_ground_contact(is_grounded)

func _is_grounded(direct_state: PhysicsDirectBodyState3D, up: Vector3) -> bool:
	var minimum_floor_dot := cos(FLOOR_MAX_ANGLE)
	for contact_index in direct_state.get_contact_count():
		var contact_normal := direct_state.get_contact_local_normal(contact_index).normalized()
		if contact_normal.dot(up) >= minimum_floor_dot:
			return true
	return false
