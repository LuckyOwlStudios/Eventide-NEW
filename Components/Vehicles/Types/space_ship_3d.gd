@tool
@icon("uid://b3hdct1vl1edl")
class_name SpaceShip3D
extends Vehicle3D
## A space ship. It turns to face wherever its [CameraRig3D] is aimed, in direction and in
## roll, as fast as its thrusters allow. Nothing else holds it: whatever knocks it off course
## (a crash, a gravity field) turns it, and it then swings itself back.
##
## It moves relative to the camera rig, not to itself: forward is where the camera looks, up is
## the camera's up, however the ship happens to be turned at that moment. The thrusters speed it up
## to the speed asked for and brake it when nothing is held, so a ship someone is flying does not
## drift. Once the pilot leaves, nothing pushes it any more.
##
## None of this works with [member Vehicle3D.engine_state] off: the ship cannot turn or thrust, and
## it falls under full gravity. With the engine on it hovers instead: gravity does not pull it
## down, and when nobody is flying it, it turns itself upright against the gravity.

## The controls, shared with moving on foot. Every ship uses all of them.
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_UP := &"jump"
const MOVE_DOWN := &"crouch"
const BOOST := &"sprint"
const PRECISION := &"stroll"

## Gravity weaker than this is ignored.
const MINIMUM_GRAVITY := 0.001

@export_group("Steering")
## The camera rig the ship follows. The first one found under the ship when left empty.
@export var camera_rig: CameraRig3D
## The fastest the ship will turn.
@export_range(10.0, 360.0, 1.0, "suffix:°/s") var max_turn_rate_degrees := 60.0
## How quickly the thrusters can speed up or slow down a turn. Low is a heavy ship.
@export_range(10.0, 720.0, 1.0, "suffix:°/s²") var turn_acceleration_degrees := 90.0
## How hard the ship turns for the angle left to go. Higher is snappier near the target.
@export_range(0.5, 10.0, 0.1) var turn_response := 2.5

@export_group("Movement")
## The ship's top speed with nothing special held.
@export_range(1.0, 500.0, 1.0, "or_greater", "suffix:m/s") var max_speed := 25.0
## How hard the thrusters push, in speed gained per second. Low is a heavy ship.
@export_range(0.5, 200.0, 0.5, "or_greater", "suffix:m/s²") var thrust_acceleration := 10.0
## Top speed and thrust are multiplied by this while boosting (Shift).
@export_range(1.0, 10.0, 0.1) var boost_multiplier := 3.0
## ...and by this while moving precisely (Alt).
@export_range(0.01, 1.0, 0.01) var precision_multiplier := 0.2
## How fast the Ship moves forward, as a share of its speed
@export var forward_direction_multiplier: float = 1
## How fast the Ship moves backward, as a share of its speed
@export var backward_direction_multiplier: float = 1
## How fast the Ship moves left, as a share of its speed
@export var left_direction_multiplier: float = 1
## How fast the Ship moves right, as a share of its speed
@export var right_direction_multiplier: float = 1
## How fast the Ship moves up, as a share of its speed
@export var up_direction_multiplier: float = 1
## How fast the Ship moves down, as a share of its speed
@export var down_direction_multiplier: float = 1

@export_group("Debugging")
## Flies the ship without anyone sitting in a seat: the rig takes input and the ship follows
## it. For trying the ship out before there is a pilot seat.
@export var fly_without_pilot := false

## True while the thrusters are still stopping the turn they were making when the pilot left.
var _cutting_spin := false
## The gravity acting on the ship, as of the last physics step.
var _gravity := Vector3.ZERO


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		return
	# A sleeping body ignores the thrusters.
	can_sleep = false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(camera_rig):
		camera_rig = _find_camera_rig(self)
	if fly_without_pilot and is_instance_valid(camera_rig):
		camera_rig.input_enabled = true
		camera_rig.camera.current = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super._physics_process(delta)
	if not engine_state:
		_cutting_spin = false
		return

	if _is_piloted():
		_cutting_spin = false
		_turn_toward(camera_rig.get_aim_basis(), delta)
		_thrust(delta)
		return

	if _gravity.length_squared() > MINIMUM_GRAVITY * MINIMUM_GRAVITY:
		# Nobody is flying it, but it still hovers and rights itself against the gravity.
		_cutting_spin = false
		_turn_toward(_upright_basis(-_gravity.normalized()), delta)
	elif _cutting_spin:
		_cut_spin(delta)


## Someone is flying it: they sit in a seat (or the debug flag is on), and the ship has a rig.
func _is_piloted() -> bool:
	return is_instance_valid(camera_rig) and (fly_without_pilot or has_local_control())


## With the engine running the ship hovers: the engine pushes back exactly as hard as gravity
## pulls, so it feels no gravity and does not fall. Gravity is still there to be measured, which
## the camera rig and the self-righting need, so the pull is cancelled rather than switched off.
## With the engine off nothing is cancelled and the ship falls like any heavy object.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint():
		return
	_gravity = state.total_gravity
	if engine_state:
		state.apply_central_force(-_gravity * mass)


## The orientation the ship has now, turned the shortest way so that its up is [param up].
func _upright_basis(up: Vector3) -> Basis:
	var current := global_basis.orthonormalized()
	return Basis(Quaternion(current.y, up)) * current


## The velocity the pilot is asking for, in world space: the held directions along the camera's
## own right, up and forward, however fast they are allowed to go.
func get_wanted_velocity() -> Vector3:
	if not is_instance_valid(camera_rig) or InGameUIHandler.is_ui_open:
		return Vector3.ZERO
	var wanted := Vector3(
		Input.get_axis(MOVE_LEFT, MOVE_RIGHT),
		Input.get_action_strength(MOVE_UP) * (0.0 if is_start_key_in_use() else 1.0) - Input.get_action_strength(MOVE_DOWN),
		Input.get_axis(MOVE_FORWARD, MOVE_BACK),
	)
	if wanted.length() > 1.0:
		wanted = wanted.normalized()
	wanted.x *= right_direction_multiplier if wanted.x > 0.0 else left_direction_multiplier
	wanted.y *= up_direction_multiplier if wanted.y > 0.0 else down_direction_multiplier
	wanted.z *= backward_direction_multiplier if wanted.z > 0.0 else forward_direction_multiplier
	return camera_rig.get_aim_basis() * wanted * max_speed * _speed_scale()


## Boosting and moving precisely both scale how fast the ship goes and how hard it pushes.
func _speed_scale() -> float:
	var factor := 1.0
	if Input.is_action_pressed(BOOST):
		factor *= boost_multiplier
	if Input.is_action_pressed(PRECISION):
		factor *= precision_multiplier
	return factor


## Pushes the ship toward the velocity asked for, no harder than the thrusters can. The push is
## an impulse on the body scaled by its mass, so a heavy ship gets going as quickly as a light
## one, and a crash still knocks it about for real.
func _thrust(delta: float) -> void:
	var change := get_wanted_velocity() - linear_velocity
	var limit := thrust_acceleration * _speed_scale() * delta
	apply_central_impulse(change.limit_length(limit) * mass)


## The pilot got up. Whatever turn the thrusters were making is stopped, at the pace they can,
## and then they let go for good: nothing damps an empty ship, so one that gets knocked
## afterwards keeps tumbling and drifting.
func _on_control_ended(_ended_controller: VehicleController) -> void:
	_cutting_spin = true


func _cut_spin(delta: float) -> void:
	angular_velocity = angular_velocity.move_toward(
		Vector3.ZERO,
		deg_to_rad(turn_acceleration_degrees) * delta,
	)
	if angular_velocity.is_zero_approx():
		_cutting_spin = false


## How far, in degrees, the ship is from facing where the rig aims.
func get_aim_error_degrees() -> float:
	if not is_instance_valid(camera_rig):
		return 0.0
	return rad_to_deg(_rotation_to(camera_rig.get_aim_basis()).get_angle())


## Speeds the ship's spin up or down toward the one that turns it onto [param target], within
## what the thrusters can do. A hit from outside changes the spin like any other rigid body, and
## this is what then brings it back.
func _turn_toward(target: Basis, delta: float) -> void:
	var error := _rotation_to(target)
	var angle := error.get_angle()
	var wanted_spin := Vector3.ZERO
	if angle > 0.0001:
		var acceleration := deg_to_rad(turn_acceleration_degrees)
		# Never faster than the ship can still stop in the angle that is left.
		var speed := minf(
			minf(deg_to_rad(max_turn_rate_degrees), angle * turn_response),
			sqrt(2.0 * acceleration * angle),
		)
		wanted_spin = error.get_axis() * speed
	angular_velocity = angular_velocity.move_toward(
		wanted_spin,
		deg_to_rad(turn_acceleration_degrees) * delta,
	)


## The shortest turn, in world space, from the ship's orientation onto [param target].
func _rotation_to(target: Basis) -> Quaternion:
	var current := global_basis.orthonormalized().get_rotation_quaternion()
	var error := target.orthonormalized().get_rotation_quaternion() * current.inverse()
	return -error if error.w < 0.0 else error


func _find_camera_rig(node: Node) -> CameraRig3D:
	for child in node.get_children():
		if child is CameraRig3D:
			return child as CameraRig3D
		var nested := _find_camera_rig(child)
		if is_instance_valid(nested):
			return nested
	return null
