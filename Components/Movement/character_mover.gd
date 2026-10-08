@icon("uid://bsf5y3xex4km7")
class_name CharacterMover
extends MovementMotor
## Ground and flight movement for a parent CharacterBody3D.

const COYOTE_TIME := 0.12
const GROUND_ACCELERATION := 30.0
const FLIGHT_ACCELERATION := 12.0

var _body: CharacterBody3D
var _coyote_timer := 0.0

func _ready() -> void:
	super._ready()
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("CharacterMover must be a direct child of a CharacterBody3D.")
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body):
		set_physics_process(false)
		return

	_sample_gravity(_body)
	_update_common_input(delta)
	if is_flying:
		_move_flying(delta)
	else:
		_move_on_ground(delta)


func _move_on_ground(delta: float) -> void:
	var up := _get_up_direction(_body)
	_body.up_direction = up
	if _body.is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	var vertical_velocity := up * _body.velocity.dot(up)
	var planar_velocity := _body.velocity - vertical_velocity
	var target_planar_velocity := _get_ground_direction(_body, up) * movement_speed.value
	planar_velocity = planar_velocity.lerp(
		target_planar_velocity,
		_exponential_weight(GROUND_ACCELERATION, delta),
	)

	if _body.is_on_floor() and vertical_velocity.dot(up) < 0.0:
		vertical_velocity = Vector3.ZERO
	elif has_gravity:
		vertical_velocity += gravity_vector * delta

	if _consume_jump_request(_coyote_timer > 0.0):
		vertical_velocity = up * _get_jump_speed()
		_coyote_timer = 0.0

	_body.velocity = planar_velocity + vertical_velocity
	_body.move_and_slide()


func _move_flying(delta: float) -> void:
	var target_velocity := _get_flight_direction(_body) * movement_speed.value
	_body.velocity = _body.velocity.lerp(
		target_velocity,
		_exponential_weight(FLIGHT_ACCELERATION, delta),
	)

	var roll_input := _get_roll_input()
	if not is_zero_approx(roll_input):
		_body.rotate_object_local(Vector3.FORWARD, roll_input * ROLL_SPEED * delta)
		_body.up_direction = _body.global_basis.y.normalized()

	_body.move_and_slide()
	_update_flight_ground_contact(_body.is_on_floor())
