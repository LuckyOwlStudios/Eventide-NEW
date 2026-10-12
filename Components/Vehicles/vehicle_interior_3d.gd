@icon("uid://vfansj5yl4d4")
class_name VehicleInterior3D
extends DirectionalGravityField3D
## The inside of a vehicle: gravity for the people and things in it, and a steady place for them to
## be while the vehicle moves.
##
## Put it on an Area3D inside a vehicle, shaped like the space people can be in. Everything of the
## kinds in its mask (characters, items and vehicles) that is inside is carried along with the
## vehicle: each physics tick it is moved by exactly how far the vehicle moved and turned, and its
## velocity is turned with it. To the things inside, the vehicle is standing still. They walk, fall,
## roll and drive about in its own space, whatever the vehicle is doing, and they do not need to be
## children of it, so people, loose crates and cars all work the same way.
##
## The walls and floors have to be the vehicle's Vehicle Interiors parts (see [PhysicsLayers]):
## those are bodies the engine only teleports along, so they never shove anyone. The vehicle's own
## rigid body is a solid box around it all; things inside are told to ignore it, and the vehicle must
## stay off the layers they scan, which is what [member Vehicle3D.walkable_interior] does.
##
## Momentum crosses the doorway. A crate thrown out of a ship leaves at the ship's speed plus the
## throw, and something drifting in arrives with its speed measured against the ship.
##
## One level only: a ship you can walk around in can carry cars and people, but a second walkable
## vehicle inside it is not carried with its own interior.

signal occupant_entered(body: PhysicsBody3D)
signal occupant_left(body: PhysicsBody3D)

## Runs before characters, items and vehicles take their own step, so they are in place first.
const TICK_PRIORITY := -100

## The vehicle this is the inside of. The nearest RigidBody3D above this node when left empty.
@export var vehicle: RigidBody3D
## Hands momentum across the doorway: things leaving keep the vehicle's speed, and things arriving
## are measured against it. Off, they keep their own velocity unchanged.
@export var exchange_velocity := true

static var _interiors: Array[VehicleInterior3D] = []

var _inside: Array[PhysicsBody3D] = []
## Whose frame each body is in right now, by instance id. Kept while a body is switched off for a
## moment (a seated player has no collision), so it does not look as if it had left.
var _owned: Dictionary = {}
var _previous := Transform3D.IDENTITY
var _ticked_frame := -1


func _enter_tree() -> void:
	# Before the base class: it would fill in the mask of a field out in the world.
	if collision_mask == 1:
		collision_mask = PhysicsLayers.INTERIOR_GRAVITY_MASK
	super._enter_tree()
	_interiors.append(self)


func _exit_tree() -> void:
	_interiors.erase(self)
	for body in _inside.duplicate():
		_leave(body)


func _ready() -> void:
	super._ready()
	process_physics_priority = TICK_PRIORITY
	if not is_instance_valid(vehicle):
		vehicle = _find_vehicle()
	if not is_instance_valid(vehicle):
		push_warning("%s has no vehicle (a RigidBody3D above it), so nothing inside is carried." % get_path())
		return
	_previous = vehicle.global_transform
	if collision_mask & vehicle.collision_layer != 0:
		push_warning("%s pulls and carries its own vehicle, because the vehicle is on a layer it scans. Give the vehicle walkable_interior." % get_path())
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	tick()


## Carries what is inside by how far the vehicle moved since the last tick.
func tick() -> void:
	if not is_instance_valid(vehicle):
		return
	var frame := Engine.get_physics_frames()
	if _ticked_frame == frame:
		return
	_ticked_frame = frame

	var now := vehicle.global_transform
	var change := now * _previous.affine_inverse()
	change.basis = change.basis.orthonormalized()
	_previous = now

	for id in _owned.keys():
		if not is_instance_id_valid(id):
			_owned.erase(id)
	for body in _inside.duplicate():
		if not is_instance_valid(body):
			_inside.erase(body)
			continue
		if not _owned.has(body.get_instance_id()):
			_take(body)
		if _rides_on_something_carried(body):
			continue
		_carry(body, change)


## How fast the point is going through the world, because of this vehicle.
func get_velocity_at(point: Vector3) -> Vector3:
	if not is_instance_valid(vehicle):
		return Vector3.ZERO
	var state := PhysicsServer3D.body_get_direct_state(vehicle.get_rid())
	if state == null:
		return vehicle.linear_velocity
	return state.get_velocity_at_local_position(point - vehicle.global_position)


func get_occupants() -> Array[PhysicsBody3D]:
	return _inside.duplicate()


func _find_vehicle() -> RigidBody3D:
	var node := get_parent()
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null


func _on_body_entered(body: Node3D) -> void:
	var physics_body := body as PhysicsBody3D
	if physics_body == null or physics_body == vehicle or _inside.has(physics_body):
		return
	_inside.append(physics_body)


func _on_body_exited(body: Node3D) -> void:
	var physics_body := body as PhysicsBody3D
	if physics_body == null or not _inside.has(physics_body):
		return
	_inside.erase(physics_body)
	# A body with no collision at all (sitting in a seat) is only switched off, not gone.
	if physics_body.collision_layer == 0:
		return
	_leave(physics_body)


## The body steps into this vehicle's frame: its velocity is worked out in the world and given back
## measured against the vehicle, and it stops colliding with the vehicle's own body.
func _take(body: PhysicsBody3D) -> void:
	if exchange_velocity:
		_set_velocity(body, _get_velocity(body) - get_velocity_at(body.global_position))
		_set_angular_velocity(body, _get_angular_velocity(body) - vehicle.angular_velocity)
	if is_instance_valid(vehicle):
		body.add_collision_exception_with(vehicle)
	_owned[body.get_instance_id()] = true
	occupant_entered.emit(body)


## The body goes back to the world with the vehicle's speed added to its own.
func _leave(body: PhysicsBody3D) -> void:
	_inside.erase(body)
	if not is_instance_valid(body) or not _owned.erase(body.get_instance_id()):
		return
	if exchange_velocity and is_instance_valid(vehicle):
		_set_velocity(body, _get_velocity(body) + get_velocity_at(body.global_position))
		_set_angular_velocity(body, _get_angular_velocity(body) + vehicle.angular_velocity)
	if is_instance_valid(vehicle):
		body.remove_collision_exception_with(vehicle)
	occupant_left.emit(body)


func _carry(body: PhysicsBody3D, change: Transform3D) -> void:
	var moved := change * body.global_transform
	if body is CharacterBody3D:
		_teleport_character(body as CharacterBody3D, moved)
	body.global_transform = moved
	_set_velocity(body, change.basis * _get_velocity(body))
	_set_angular_velocity(body, change.basis * _get_angular_velocity(body))


## Puts the character at [param destination] without the physics engine treating it as having moved
## there. A character is a kinematic body, and the engine moves one to a new transform by giving it
## the speed to get there in a tick, which here would be the ship's speed: it would shove every
## crate it touches. A static body is simply placed (this is also what happens to the walls), so the
## body is switched to static for the moment it takes to place it.
func _teleport_character(body: CharacterBody3D, destination: Transform3D) -> void:
	var rid := body.get_rid()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, destination)
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_KINEMATIC)


## Something fastened to the vehicle, or to another thing being carried (a held item, say), moves
## with its parent already.
func _rides_on_something_carried(body: PhysicsBody3D) -> bool:
	var node := body.get_parent()
	while node != null:
		if node == vehicle or (node is PhysicsBody3D and _inside.has(node)):
			return true
		node = node.get_parent()
	return false


func _get_velocity(body: PhysicsBody3D) -> Vector3:
	if body is CharacterBody3D:
		return (body as CharacterBody3D).velocity
	if body is RigidBody3D:
		return (body as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _set_velocity(body: PhysicsBody3D, value: Vector3) -> void:
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = value
	elif body is RigidBody3D:
		(body as RigidBody3D).linear_velocity = value


func _get_angular_velocity(body: PhysicsBody3D) -> Vector3:
	return (body as RigidBody3D).angular_velocity if body is RigidBody3D else Vector3.ZERO


func _set_angular_velocity(body: PhysicsBody3D, value: Vector3) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).angular_velocity = value
