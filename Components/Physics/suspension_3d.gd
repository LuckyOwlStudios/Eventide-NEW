class_name Suspension3D
extends RayCast3D
## A spring on a ray. It holds a rigid body up off whatever is below it, the way the spring of a car's
## wheel or a ship's landing leg does, and it can carry a wheel or a foot along so that part is seen
## to touch the ground.
##
## The ray is the spring. It starts at this node and ends at [member RayCast3D.target_position]: that
## far is how long the suspension is when nothing presses on it. Aim it the way the suspension points
## (down, for a wheel) and make it as long as the suspension can reach. When the ray finds ground
## closer than its end the spring is squeezed by the difference, and it pushes the body away from the
## ground along the ray: harder the more it is squeezed, with a damper riding along so the body settles
## instead of bouncing on. The push is applied where the ground is touched, so a body held up by
## several of them is held level, and tilts when they carry unequal loads. It never pulls: a body
## leaving the ground is simply let go.
##
## Whether it works at all is [member RayCast3D.enabled], and what counts as ground is
## [member RayCast3D.collision_mask], both already on RayCast3D. The body itself is never ground.
##
## [codeblock]
## # A body held up by 4 springs of strength 20, in gravity of 16 m/s2, sinks until
## # 4 x 20 x squeeze = 16, which is 0.2 m into each of them. Twice the strength, half the sink.
## [/codeblock]
##
## Moving parts: a wheel or a foot under this node (or any node you pick) is put at the point of
## contact, plus an offset, every tick. Where there is no ground it hangs at the end of the reach. So
## it stays on the ground, and rises as the spring is squeezed or pulled in.

## The suspension started or stopped touching something.
signal contact_changed(touching: bool)

## A suspension shorter than this is not one.
const MINIMUM_LENGTH := 0.001
## Gravity weaker than this is taken to be this much when working out how hard the grip can hold.
const MINIMUM_GRAVITY := 1.0
## Grip never stops more than this share of a slide in one physics step, so it settles instead of
## jittering.
const GRIP_STEP_SHARE := 0.5
## A slide slower than this is not a slide.
const MINIMUM_SLIDE := 0.0001

## The body the spring pushes on. The first RigidBody3D above this node (its parent, or further up)
## when left empty.
@export var rigid_body: RigidBody3D

## How hard the spring pushes back for every meter it is squeezed, as an acceleration of the body: a
## strength of 20 pushes with 20 m/s2 worth of force (20 times its mass) per meter, whatever the body
## weighs, so the same number suits a car and a ship. Springs add up: with several, each carries its
## share, and the body sinks until together they hold its weight.
@export_range(0.0, 500.0, 0.5, "or_greater", "suffix:m/s² per m") var strength := 20.0

## How much the spring resists being squeezed or let out, which is what stops the bouncing. Zero never
## stops it. One would stop the bounce of a body held up by this spring alone; several springs share
## the body, so each wants less than that, about one over the square root of how many there are.
@export_range(0.0, 2.0, 0.01, "or_greater") var dampening := 0.4

## How far out the suspension is, from 1 (fully out, working normally) to 0 (pulled all the way in).
## Pulling it in shortens how far it reaches, so the ground has to be closer to touch it, and the
## moving parts rise with it. At 0 it does nothing. Retractable landing gear is driven with this.
@export_range(0.0, 1.0, 0.01) var extension := 1.0:
	set(value):
		extension = clampf(value, 0.0, 1.0)
		_move_parts()

@export_group("Grip")
## How well the foot holds against sliding along the ground, as a share of the weight on it (a
## coefficient of friction). Zero is ice: whatever slides keeps sliding. One holds a body on a fair
## slope. A wheel wants none of this, since it rolls.
@export_range(0.0, 2.0, 0.05, "or_greater") var grip := 0.0

@export_group("Moving Parts")
## The node put at the point of contact: a wheel or a foot. This node's own children are moved when
## it is left empty. Each one is placed along the ray by the suspension, so it rests on the ground and
## rises with the spring; where it sits across the ray stays as you placed it. Parts that have to keep
## their places relative to each other (a leg and its foot) go under one node, which is the one moved.
@export var moved_node: Node3D
## Shifts the moving parts from the point of contact, in this node's space. A wheel whose middle is
## its radius above the ground is lifted by that, and a model whose origin is not at its bottom is
## moved by the difference.
@export var moved_offset := Vector3.ZERO

var _touching := false
var _compression := 0.0
var _spring_force := 0.0
var _axis := Vector3.DOWN
var _contact_point := Vector3.ZERO
var _contact_normal := Vector3.UP
var _parts: Array[Node3D] = []
## Where each part is across the ray, in this node's space: its position less the part along the ray.
var _sideways: Array[Vector3] = []
var _applied := Vector3.INF


func _ready() -> void:
	if not is_instance_valid(rigid_body):
		rigid_body = _find_rigid_body()
	if not is_instance_valid(rigid_body):
		push_warning("%s needs a RigidBody3D to hold up. Put it under one, or set Rigid Body." % get_path())
		set_physics_process(false)
		return
	# The ray starts inside the body it holds up; that body is never the ground.
	add_exception(rigid_body)
	_collect_parts()
	_move_parts()
	for part in _parts:
		part.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(rigid_body):
		return
	var was_touching := _touching
	_measure_contact()
	if _touching:
		_push(delta)
	_move_parts()
	if _touching != was_touching:
		contact_changed.emit(_touching)


## Whether the suspension is pressing on ground right now.
func is_touching() -> bool:
	return _touching


## How far, in meters, the spring is squeezed. Zero when it touches nothing.
func get_compression() -> float:
	return _compression


## How hard the spring pushes the body away from the ground, in newtons: the weight it is carrying,
## when the body is at rest. Zero when it touches nothing.
func get_spring_force() -> float:
	return _spring_force


## How long the suspension is right now, in meters: to the ground it touches, or to the end of its
## reach when it touches nothing.
func get_length() -> float:
	var reach := _get_full_length() * extension
	if not _touching:
		return reach
	return reach - _compression


## How long the suspension is when it is fully out and nothing presses on it, in meters.
func get_full_length() -> float:
	return _get_full_length()


## The direction the spring points in, away from the body and toward the ground, in world space.
func get_axis() -> Vector3:
	return _axis


## Where the ground is touched, in world space. Only meaningful while touching.
func get_contact_point() -> Vector3:
	return _contact_point


## Which way the ground faces where it is touched, in world space. Only meaningful while touching.
func get_contact_normal() -> Vector3:
	return _contact_normal


## The first RigidBody3D above this node.
func _find_rigid_body() -> RigidBody3D:
	var node := get_parent()
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null


func _get_full_length() -> float:
	return (to_global(target_position) - global_position).length()


## Works out whether the ray reaches ground, and by how much that squeezes the spring.
func _measure_contact() -> void:
	_touching = false
	_compression = 0.0
	_spring_force = 0.0
	var origin := global_position
	var to_end := to_global(target_position) - origin
	var full := to_end.length()
	if full < MINIMUM_LENGTH:
		return
	_axis = to_end / full
	if not enabled or extension <= 0.0 or not is_colliding():
		return
	var point := get_collision_point()
	var squeeze := full * extension - (point - origin).dot(_axis)
	if squeeze <= 0.0:
		return
	_touching = true
	_compression = squeeze
	_contact_point = point
	_contact_normal = get_collision_normal()


## Pushes the body away from the ground: the spring, the damper and the grip, at the point touched.
## What the body pushes on, if it can move, is pushed back on in return.
func _push(delta: float) -> void:
	if rigid_body.sleeping:
		return
	var state := PhysicsServer3D.body_get_direct_state(rigid_body.get_rid())
	if state == null:
		return
	var offset := _contact_point - state.transform.origin
	var relative := state.get_velocity_at_local_position(offset) - _get_ground_velocity()
	# How fast the body is closing in on the ground along the spring: positive means being squeezed.
	var closing := relative.dot(_axis)
	var damping := dampening * 2.0 * sqrt(strength)
	_spring_force = maxf(rigid_body.mass * (strength * _compression + damping * closing), 0.0)
	if _spring_force <= 0.0:
		return
	var force := -_axis * _spring_force
	if grip > 0.0:
		force += _get_grip_force(relative, state.total_gravity.length(), delta)
	rigid_body.apply_force(force, offset)
	var ground := get_collider() as RigidBody3D
	if is_instance_valid(ground) and ground != rigid_body:
		ground.apply_force(-force, _contact_point - ground.global_position)


## The force that holds the foot against sliding along the ground, opposite to the slide and no more
## than the grip allows for the weight on it. It is also no more than stops the slide within a step
## for the share of the body this foot carries (its load over gravity), so a slow slide dies away
## smoothly instead of the foot flicking back and forth.
func _get_grip_force(relative: Vector3, gravity: float, delta: float) -> Vector3:
	var slide := relative - _contact_normal * relative.dot(_contact_normal)
	var speed := slide.length()
	if speed < MINIMUM_SLIDE:
		return Vector3.ZERO
	var weight := _spring_force * maxf((-_axis).dot(_contact_normal), 0.0)
	var holding := minf(grip, GRIP_STEP_SHARE * speed / (maxf(gravity, MINIMUM_GRAVITY) * delta))
	return -slide / speed * weight * holding


## How fast the ground is moving where it is touched.
func _get_ground_velocity() -> Vector3:
	var collider := get_collider()
	if collider == null or collider is Area3D:
		return Vector3.ZERO
	var state := PhysicsServer3D.body_get_direct_state(get_collider_rid())
	if state == null:
		return Vector3.ZERO
	return state.get_velocity_at_local_position(_contact_point - state.transform.origin)


func _collect_parts() -> void:
	_parts.clear()
	_sideways.clear()
	var nodes: Array[Node3D] = []
	if is_instance_valid(moved_node):
		nodes.append(moved_node)
	else:
		for child in get_children():
			if child is Node3D:
				nodes.append(child as Node3D)
	var direction := target_position.normalized()
	for node in nodes:
		var spot := to_local(node.global_position)
		_parts.append(node)
		_sideways.append(spot - direction * spot.dot(direction))
	_applied = Vector3.INF


## Puts the moving parts at the ground where it is touched, and at the end of the reach where it is not.
func _move_parts() -> void:
	if _parts.is_empty():
		return
	var direction := target_position.normalized()
	var length := target_position.length() * extension
	if _touching:
		length = to_local(_contact_point).dot(direction)
	var along := direction * length + moved_offset
	var changed := not along.is_equal_approx(_applied)
	_applied = along
	for index in _parts.size():
		var part := _parts[index]
		if not is_instance_valid(part):
			continue
		var wanted := _sideways[index] + along
		if part.get_parent() == self:
			if changed:
				part.position = wanted
		else:
			# Not carried along by this node, so it is put back in place every tick.
			part.global_position = to_global(wanted)
