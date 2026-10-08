@icon("uid://m0wnphocenlk")
class_name Orientor
extends Node
## Aligns its parent PhysicsBody3D's local up axis opposite effective gravity.

## The body's local axis that should point away from gravity.
@export var local_up_axis := Vector3.UP
## How quickly the target follows gravity. Set to 0 for immediate alignment.
@export_range(0.0, 60.0, 0.5) var orientation_speed := 10.0
## Prevents a RigidBody3D from tumbling while preserving spin around its new up axis.
@export var stabilize_rigid_body := true
## Gravity weaker than this is ignored, avoiding an undefined orientation near zero gravity.
@export_range(0.0, 1.0, 0.001) var minimum_gravity := 0.001

var gravity_vector := Vector3.ZERO
var up_direction := Vector3.UP

var _body: PhysicsBody3D


func _ready() -> void:
	_resolve_body()
	set_physics_process(_body != null)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body):
		_resolve_body()
		if _body == null:
			set_physics_process(false)
			return

	var direct_state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	if direct_state == null:
		return

	orient_to_gravity(direct_state.total_gravity, delta)


## Immediately samples and applies the body's current effective gravity.
func update_orientation(delta: float = 0.0) -> void:
	if _body == null:
		_resolve_body()
	if _body == null:
		return

	var direct_state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	if direct_state:
		orient_to_gravity(direct_state.total_gravity, delta)


## Aligns the target using a supplied gravity vector. Useful for custom gravity systems too.
func orient_to_gravity(new_gravity: Vector3, delta: float = 0.0) -> void:
	if _body == null:
		_resolve_body()
	if _body == null or new_gravity.length_squared() <= minimum_gravity * minimum_gravity:
		return

	gravity_vector = new_gravity
	up_direction = -new_gravity.normalized()

	var current_basis := _body.global_basis
	var normalized_local_up := local_up_axis.normalized()
	if normalized_local_up.is_zero_approx():
		normalized_local_up = Vector3.UP

	var current_up := (current_basis.orthonormalized() * normalized_local_up).normalized()
	var alignment := _get_alignment_rotation(current_up, up_direction, current_basis)
	var current_rotation := current_basis.orthonormalized().get_rotation_quaternion()
	var target_rotation := (alignment * current_rotation).normalized()
	var interpolation_weight := 1.0
	if orientation_speed > 0.0 and delta > 0.0:
		interpolation_weight = 1.0 - exp(-orientation_speed * delta)

	var next_rotation := current_rotation.slerp(target_rotation, interpolation_weight)
	_body.global_basis = Basis(next_rotation).scaled_local(current_basis.get_scale())

	if stabilize_rigid_body and _body is RigidBody3D:
		var rigid_body := _body as RigidBody3D
		rigid_body.angular_velocity = up_direction * rigid_body.angular_velocity.dot(up_direction)


func _resolve_body() -> void:
	_body = get_parent() as PhysicsBody3D
	if _body == null and is_inside_tree():
		push_error("Orientor must be a direct child of a PhysicsBody3D.")


func _get_alignment_rotation(
	from_direction: Vector3,
	to_direction: Vector3,
	current_basis: Basis,
) -> Quaternion:
	var direction_dot := clampf(from_direction.dot(to_direction), -1.0, 1.0)
	if direction_dot > 0.999999:
		return Quaternion.IDENTITY
	if direction_dot < -0.999999:
		# A 180-degree turn has no unique axis. Prefer the target's current right axis.
		var turn_axis := current_basis.orthonormalized().x
		turn_axis = turn_axis - from_direction * turn_axis.dot(from_direction)
		if turn_axis.is_zero_approx():
			turn_axis = current_basis.orthonormalized().z
			turn_axis = turn_axis - from_direction * turn_axis.dot(from_direction)
		return Quaternion(turn_axis.normalized(), PI)
	return Quaternion(from_direction, to_direction)
