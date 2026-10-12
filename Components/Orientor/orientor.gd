@icon("uid://m0wnphocenlk")
class_name Orientator
extends Node
## Aligns its parent's local up axis opposite effective gravity.
##
## The parent is usually a PhysicsBody3D, which feels gravity itself. Any other Node3D
## can be oriented too (a camera rig, say) as long as it is given a [member gravity_source],
## the body whose gravity it should follow, or is told the gravity directly through
## [method orient_to_gravity].

## The body's local axis that should point away from gravity.
@export var local_up_axis := Vector3.UP
## How quickly the target follows gravity. Set to 0 for immediate alignment.
@export_range(0.0, 60.0, 0.5) var orientation_speed := 10.0
## Prevents a RigidBody3D from tumbling while preserving spin around its new up axis.
@export var stabilize_rigid_body := true
## Gravity weaker than this is ignored, avoiding an undefined orientation near zero gravity.
@export_range(0.0, 1.0, 0.001) var minimum_gravity := 0.001
## Body whose gravity is followed. Leave empty to use the parent, when it is a body.
## Needed when the parent is a plain Node3D and this node steps itself.
@export var gravity_source: PhysicsBody3D:
	set(value):
		gravity_source = value
		if is_node_ready():
			_resolve_target()
			set_physics_process(step_automatically and _gravity_body != null)
## Aligns itself every physics tick. Turn this off when something else, such as a
## CharacterController, calls [method orient_to_gravity] so the alignment can be replayed.
@export var step_automatically := true:
	set(value):
		step_automatically = value
		if is_node_ready():
			set_physics_process(step_automatically and _gravity_body != null)

var gravity_vector := Vector3.ZERO
var up_direction := Vector3.UP

## What gets rotated: the parent.
var _target: Node3D
## What gravity is read from.
var _gravity_body: PhysicsBody3D


func _ready() -> void:
	_resolve_target()
	set_physics_process(_gravity_body != null and step_automatically)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target) or not is_instance_valid(_gravity_body):
		_resolve_target()
		if _target == null or _gravity_body == null:
			set_physics_process(false)
			return

	orient_to_gravity(sample_gravity(), delta)


## Immediately samples and applies the current effective gravity.
func update_orientation(delta: float = 0.0) -> void:
	orient_to_gravity(sample_gravity(), delta)


## True when there is a body to read gravity from.
func has_gravity_source() -> bool:
	if not is_instance_valid(_gravity_body):
		_resolve_target()
	return _gravity_body != null


## The gravity the source body feels right now, or zero when there is no source.
func sample_gravity() -> Vector3:
	if not has_gravity_source():
		return Vector3.ZERO
	var direct_state := PhysicsServer3D.body_get_direct_state(_gravity_body.get_rid())
	return direct_state.total_gravity if direct_state else Vector3.ZERO


## Aligns the target using a supplied gravity vector. Useful for custom gravity systems too.
func orient_to_gravity(new_gravity: Vector3, delta: float = 0.0) -> void:
	if not is_instance_valid(_target):
		_resolve_target()
	if _target == null or new_gravity.length_squared() <= minimum_gravity * minimum_gravity:
		return

	gravity_vector = new_gravity
	up_direction = -new_gravity.normalized()

	var current_basis := _target.global_basis
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
	_target.global_basis = Basis(next_rotation).scaled_local(current_basis.get_scale())

	if stabilize_rigid_body and _target is RigidBody3D:
		var rigid_body := _target as RigidBody3D
		rigid_body.angular_velocity = up_direction * rigid_body.angular_velocity.dot(up_direction)

func _resolve_target() -> void:
	_target = get_parent() as Node3D
	_gravity_body = gravity_source if is_instance_valid(gravity_source) else _target as PhysicsBody3D
	if _target == null and is_inside_tree():
		push_error("Orientator must be a direct child of a Node3D.")


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
