@tool
@icon("uid://bljri5paty5p")
class_name SoftCollision3D
extends Node
## Lets a body push itself away from other bodies, softly, instead of colliding with them hard.
##
## A hard collision between a character and an item is a wall that only one of them feels: the
## character cannot be moved at all, so a character that walks an item into a wall squeezes the
## item into it, and through it. With this node the two do not collide hard. Every physics tick the
## body looks for whatever overlaps it among the layers in [member push_mask] and moves itself away
## from it, by ordinary means: an impulse for a RigidBody3D, a collide-and-slide step for a
## CharacterBody3D. Real walls still stop it, so nothing is ever pushed through one. What does the
## pushing just walks over it when it cannot get away.
##
## Put it under a RigidBody3D or a CharacterBody3D. One node serves both. Whoever carries one pushes
## only itself, so the rules are set per body: an item with one gets out of the way of players, a
## player with one gets out of the way of other players, and a body without one is never moved.
##
## A rigid body is carried along by what moves into it: it takes on that speed, so it rides in front
## of a walking player the way a shoved crate does, and slides while it is pushed instead of tipping
## over. A character is only nudged apart, so characters slide past each other instead of one
## carrying the other.
##
## A CharacterController finds the node next to it and runs it inside its own tick, so the push is
## part of what a client predicts and replays. Anything else runs it itself, once per physics tick.

## The most bodies pushed away from at the same time.
const MAXIMUM_NEIGHBORS := 8
## The most contact points read back from one body.
const MAXIMUM_CONTACTS := 16
## Anything pushing with less than this is not worth moving for.
const MINIMUM_PUSH := 0.001
## With a ground-only push, an overlap this shallow that is mostly up or down is something clipping the
## top or bottom of the body (a hop over a crate), not something to move away from.
const CLIPPING_DEPTH := 0.1
## How long a rigid body keeps its reduced friction after the last push, in physics ticks, so a gap
## of a tick or two between pushes does not bring it back and tip the body.
const FRICTION_HOLD_TICKS := 6

## The body that pushes itself away. Its parent when left empty.
@export var body: PhysicsBody3D

## Turns the pushing on or off.
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			_restore_body()

## The layers of the bodies this one pushes itself away from.
@export_flags_3d_physics var push_mask: int = PhysicsLayers.CHARACTERS:
	set(value):
		push_mask = value
		_query.collision_mask = value
		_make_collision_soft()

## How hard it pushes: the speed it is pushed away at, in meters per second for every meter of
## overlap. More makes a firmer push that shows less overlap; less lets bodies sink into each other
## before they give way.
@export_range(0.0, 200.0, 0.5, "or_greater", "suffix:m/s per m") var strength := 40.0

## The fastest the body can be pushed along. Keeps a body that is squeezed from shooting away, and is
## how heavy something feels: with a low maximum a player walking into it shoves it along slowly and
## walks through it, where with a high one it keeps right ahead of them.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m/s") var maximum_speed := 8.0

## A soft skin around the body. A rigid body starts taking on the speed of what moves into it when it
## is this close, before they touch, so there is no jolt when they meet.
@export_range(0.0, 0.5, 0.005, "or_greater", "suffix:m") var margin := 0.04:
	set(value):
		margin = value
		_query.margin = value

## While there is gravity, push only sideways, never up or down. Items and people on the ground are
## not lifted or driven into the floor by what overlaps them. With no gravity the push goes any way.
@export var ground_only := true

## How much of its friction a rigid body keeps while it is being pushed, from none to all of it. At
## full friction a box pushed along the floor tips forward and a ball runs away rolling; with less it
## slides along in front of the pusher. It has all of it back soon after the pushing stops.
@export_range(0.0, 1.0, 0.01) var friction_while_pushed := 0.1

## Takes the layers it pushes away from out of the body's own collision mask, so the body does not
## also collide hard with them. Leave this on for the push to be the only thing between them. The
## other body must not scan this one's layer either, or it will still collide hard from its side.
@export var replace_hard_collision := true

## Only the peer that owns the body pushes it. Turn this off for a body that every peer simulates.
@export var authority_only := true

var _driven_by_controller := false
var _rigid: RigidBody3D
var _shapes: Array[CollisionShape3D] = []
var _shapes_dirty := true
var _self_exclude: Array[RID] = []
var _query := PhysicsShapeQueryParameters3D.new()
var _normal_friction := -1.0
var _friction_hold := 0
var _normal_continuous := false
var _motion := PhysicsTestMotionParameters3D.new()
var _motion_result := PhysicsTestMotionResult3D.new()


## One body this one overlaps, or is within the margin of.
class Contact:
	## The body it is.
	var other: Node3D
	## Which way to move to get clear of it. A unit vector.
	var direction := Vector3.ZERO
	## How far inside it the body is, not counting the margin. Zero when only close.
	var overlap := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(body):
		body = get_parent() as PhysicsBody3D
	if not is_instance_valid(body):
		push_warning("%s needs a RigidBody3D or CharacterBody3D to push." % get_path())
		set_physics_process(false)
		return
	_rigid = body as RigidBody3D
	_self_exclude = [body.get_rid()]
	_query.collision_mask = push_mask
	_query.margin = margin
	_query.collide_with_areas = false
	body.child_order_changed.connect(_on_body_children_changed)
	_make_collision_soft()


func _exit_tree() -> void:
	_restore_body()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _driven_by_controller or not _can_push():
		return
	if authority_only and not body.is_multiplayer_authority():
		return
	if _rigid != null:
		push_rigid_body(_rigid)
	elif body is CharacterBody3D:
		apply_to_character(delta)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var target := body if body != null else get_parent() as PhysicsBody3D
	if not (target is RigidBody3D or target is CharacterBody3D):
		warnings.append("This node pushes a RigidBody3D or a CharacterBody3D. Make it a child of one, or set Body.")
		return warnings
	var has_shape := false
	for child in target.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			has_shape = true
			break
	if not has_shape:
		warnings.append("The body has no collision shape, so there is nothing to find overlaps with.")
	if push_mask == 0:
		warnings.append("Push Mask is empty, so nothing is pushed away from.")
	if not replace_hard_collision and target.collision_mask & push_mask != 0:
		warnings.append("The body still collides hard with some of the layers it pushes away from, so the two fight.")
	return warnings


## Called by a CharacterController that runs this node inside its own tick.
func set_driven_by_controller(value := true) -> void:
	_driven_by_controller = value


## How fast, in meters per second, the body is being pushed away right now, in world space. Zero when
## nothing overlaps it.
func compute_push() -> Vector3:
	var total := Vector3.ZERO
	for contact in find_contacts():
		total += contact.direction * _get_speed(contact, false)
	return total.limit_length(maximum_speed)


## Everything the body overlaps, or is within the margin of, among the layers it pushes away from.
func find_contacts() -> Array[Contact]:
	if push_mask == 0 or not _can_push():
		return []
	return _find_contacts()


func _find_contacts() -> Array[Contact]:
	var contacts: Array[Contact] = []
	var space := body.get_world_3d().direct_space_state
	# Most bodies most of the time have nothing near them, so that is found out first and cheaply.
	var neighbors := _find_neighbors(space)
	if neighbors.is_empty():
		return contacts
	var exclude := _get_excluded()
	for exception in exclude:
		neighbors.erase(exception)
	var up := _get_up()
	for neighbor: RID in neighbors:
		# Each is measured alone, so a crowd pushes by the sum of its members, not by whichever
		# touches the most points.
		var others: Array[RID] = exclude.duplicate()
		for other: RID in neighbors:
			if other != neighbor:
				others.append(other)
		var contact := _measure(space, others, up, neighbors[neighbor])
		if contact != null:
			contacts.append(contact)
	return contacts


## Moves the character away from what overlaps it, for one tick of [param delta]. Slides along walls.
func apply_to_character(delta: float) -> void:
	var character := body as CharacterBody3D
	if character == null:
		return
	var push := compute_push()
	if push.length_squared() < MINIMUM_PUSH * MINIMUM_PUSH:
		return
	var remaining := push * delta
	for attempt in 2:
		var collision := character.move_and_collide(remaining)
		if collision == null:
			return
		remaining = collision.get_remainder().slide(collision.get_normal())


## Gives the body the speed of what moves into it, plus a push out of whatever it overlaps, by an
## impulse just big enough to get there.
func push_rigid_body(rigid: RigidBody3D) -> void:
	if rigid.freeze:
		return
	var wanted := Vector3.ZERO
	if push_mask != 0:
		for contact in _find_contacts():
			wanted += contact.direction * _get_speed(contact, true)
	var speed := wanted.length()
	_set_pushed(rigid, speed >= MINIMUM_PUSH)
	if speed < MINIMUM_PUSH:
		return
	var direction := wanted / speed
	# It is brought up to the speed wanted, but never beyond the room there is ahead: a body that is
	# about to hit something is slowed to stop at it. Left to the engine it would cross a thin wall
	# in a single tick, and a push is one of the few things that moves a body that fast.
	var current := rigid.linear_velocity.dot(direction)
	var final := minf(maxf(current, speed), _get_clear_speed(rigid, direction, maxf(current, speed)))
	if not is_equal_approx(final, current):
		rigid.apply_central_impulse(direction * (final - current) * rigid.mass)


## The most of [param speed] the body can have along [param direction] for one tick without running
## into something it collides with.
func _get_clear_speed(rigid: RigidBody3D, direction: Vector3, speed: float) -> float:
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	_motion.from = rigid.global_transform
	_motion.motion = direction * speed * step
	if not PhysicsServer3D.body_test_motion(rigid.get_rid(), _motion, _motion_result):
		return speed
	# The travel also holds the little the engine moved the body to get it out of a touching surface.
	return maxf(_motion_result.get_travel().dot(direction), 0.0) / step


## How fast the body is moved away from one thing it overlaps: faster the deeper the overlap, plus,
## when [param follow] is on, the speed that thing is coming at it, and never more than the maximum.
func _get_speed(contact: Contact, follow: bool) -> float:
	var speed := strength * contact.overlap
	if follow:
		speed += _get_follow_speed(contact)
	return minf(speed, maximum_speed)


## How fast the other body is going toward this one: the speed this one is carried along at.
func _get_follow_speed(contact: Contact) -> float:
	var velocity := Vector3.ZERO
	if contact.other is CharacterBody3D:
		velocity = (contact.other as CharacterBody3D).velocity
	elif contact.other is RigidBody3D:
		velocity = (contact.other as RigidBody3D).linear_velocity
	return maxf(velocity.dot(contact.direction), 0.0)


## While something pushes a body it keeps only part of its friction with the ground, and it is checked
## for hitting things along the whole way instead of tick by tick, so a push at speed cannot drive it
## into a thin wall. It is as it was a moment after the pushing stops.
func _set_pushed(rigid: RigidBody3D, pushed: bool) -> void:
	if pushed:
		_friction_hold = FRICTION_HOLD_TICKS
		if _normal_friction < 0.0:
			var rid := rigid.get_rid()
			_normal_friction = PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION)
			_normal_continuous = rigid.continuous_cd
			PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, _normal_friction * friction_while_pushed)
			rigid.continuous_cd = true
	elif _normal_friction >= 0.0:
		_friction_hold -= 1
		if _friction_hold <= 0:
			_restore_body()


func _restore_body() -> void:
	if _normal_friction < 0.0:
		return
	var rigid := body as RigidBody3D
	if is_instance_valid(rigid):
		PhysicsServer3D.body_set_param(rigid.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION, _normal_friction)
		rigid.continuous_cd = _normal_continuous
	_normal_friction = -1.0


func _can_push() -> bool:
	return enabled and not Engine.is_editor_hint() and is_instance_valid(body) and body.is_inside_tree()


func _make_collision_soft() -> void:
	if replace_hard_collision and not Engine.is_editor_hint() and is_instance_valid(body):
		body.collision_mask &= ~push_mask


## The body's own collision shapes. Which ones there are is remembered; whether one is switched off,
## and what it is shaped like right now (a crouching character has swapped it), is looked at each time.
func _get_shapes() -> Array[CollisionShape3D]:
	if _shapes_dirty:
		_shapes.clear()
		for child in body.get_children():
			if child is CollisionShape3D:
				_shapes.append(child as CollisionShape3D)
		_shapes_dirty = false
	return _shapes


func _on_body_children_changed() -> void:
	_shapes_dirty = true


## The things never pushed away from: the body itself and whatever it has agreed not to collide with.
func _get_excluded() -> Array[RID]:
	var exclude: Array[RID] = [body.get_rid()]
	for exception in body.get_collision_exceptions():
		exclude.append(exception.get_rid())
	return exclude


## The bodies overlapping this one, or within the margin of it, by their physics RID.
func _find_neighbors(space: PhysicsDirectSpaceState3D) -> Dictionary[RID, Node3D]:
	var neighbors: Dictionary[RID, Node3D] = {}
	_query.exclude = _self_exclude
	for shape in _get_shapes():
		if shape.disabled or shape.shape == null:
			continue
		_query.shape_rid = shape.shape.get_rid()
		_query.transform = shape.global_transform
		for hit in space.intersect_shape(_query, MAXIMUM_NEIGHBORS):
			var other := hit["collider"] as Node3D
			if other != null and not _is_family(other):
				neighbors[hit["rid"]] = other
	return neighbors


## How the body overlaps the one body that is left once everything in [param exclude] is ignored.
## Null when it only clips the top or bottom of it.
func _measure(space: PhysicsDirectSpaceState3D, exclude: Array[RID], up: Vector3, other: Node3D) -> Contact:
	_query.exclude = exclude
	var way_out := Vector3.ZERO
	for shape in _get_shapes():
		if shape.disabled or shape.shape == null:
			continue
		_query.shape_rid = shape.shape.get_rid()
		_query.transform = shape.global_transform
		# Contacts come as pairs of points: one on this body, one on the other. From ours to theirs
		# is the way into the other body, so from theirs to ours is the way out.
		var contacts := space.collide_shape(_query, MAXIMUM_CONTACTS)
		for index in range(0, contacts.size() - 1, 2):
			var candidate := contacts[index + 1] - contacts[index]
			if candidate.length_squared() > way_out.length_squared():
				way_out = candidate
	if way_out.length() < MINIMUM_PUSH:
		return null
	if up != Vector3.ZERO:
		way_out = _level_way_out(way_out, up, other)
		if way_out == Vector3.ZERO:
			return null
	var contact := Contact.new()
	contact.other = other
	contact.direction = way_out.normalized()
	# The way out counts the margin, which is not overlap.
	contact.overlap = maxf(way_out.length() - margin, 0.0)
	return contact


## A way out that does not go up or down. Usually that is just the sideways part of it. But a body
## that has ended up inside the other (an item inside a character's capsule) has its shortest way out
## through the floor, and that would leave it stuck: it is moved away from the other's middle
## instead, as far as the real way out is long. Something only clipping the top or the bottom is
## left alone (zero).
func _level_way_out(way_out: Vector3, up: Vector3, other: Node3D) -> Vector3:
	var level := way_out.slide(up)
	var depth := way_out.length()
	if level.length() >= depth * 0.5:
		return level
	if depth <= CLIPPING_DEPTH:
		return Vector3.ZERO
	var apart := (body.global_position - other.global_position).slide(up)
	if apart.length_squared() < MINIMUM_PUSH * MINIMUM_PUSH:
		# Exactly on top of each other: any sideways direction will do.
		apart = Vector3.RIGHT.slide(up)
		if apart.length_squared() < 0.01:
			apart = Vector3.FORWARD.slide(up)
	return apart.normalized() * depth


## The direction up while there is gravity and the push is ground only, otherwise zero.
func _get_up() -> Vector3:
	if not ground_only:
		return Vector3.ZERO
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null or state.total_gravity.length_squared() < 0.000001:
		return Vector3.ZERO
	return -state.total_gravity.normalized()


## A body fastened to this one (an item in a hand) moves with it, so it is never pushed away from.
func _is_family(other: Node) -> bool:
	return other != null and (body.is_ancestor_of(other) or other.is_ancestor_of(body))
