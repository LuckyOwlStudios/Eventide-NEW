@tool
class_name BaseCharacter3D
extends CharacterBody3D
## The root of nearly every character: a body of a given size and shape.
##
## Set [member dimensions] and [member shape_type] in the inspector and the collision shape follows, in the
## editor as well as in the game. The feet are at the origin. Everything else (a head, a point of view, how
## the character walks) belongs to the scenes that extend this one.
##
## A subclass that changes its hitbox, a crouching character say, overrides [method _get_hitbox_dimensions] and
## [method _get_hitbox_shape_type] and calls [method _apply_dimensions] when the answer changes.

enum ShapeType {
	CAPSULE,
	SPHERE,
	BOX,
	CYLINDER,
}

@export_group("Body")
## Width and height of the character, in meters. A capsule is as wide as the first and as tall as the second.
@export var dimensions := Vector2(0.8, 1.8):
	set(value):
		dimensions = Vector2(maxf(value.x, 0.01), maxf(value.y, 0.01))
		_apply_dimensions()
## What shape the body collides with. The shape in the scene is replaced by one of this kind.
@export var shape_type := ShapeType.CAPSULE:
	set(value):
		shape_type = value
		_apply_dimensions()

@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")

## The shape of each kind this character has had, so a change of kind swaps between shapes that exist.
var _shapes: Dictionary[int, Shape3D] = {}


func _ready() -> void:
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape3D")
	_apply_dimensions()
	if Engine.is_editor_hint():
		return
	# Base collisions: it is in no layer of its own (subclasses choose), and sees the world, vehicles and
	# vehicle interiors.
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, true)
	set_collision_mask_value(4, true)
	set_collision_mask_value(5, true)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null("CollisionShape3D") == null:
		warnings.append("A BaseCharacter3D needs a CollisionShape3D child named CollisionShape3D.")
	return warnings


## The size the body has right now. Subclasses whose size changes (a crouch) answer for it here.
func _get_hitbox_dimensions() -> Vector2:
	return dimensions


## The kind of shape the body has right now.
func _get_hitbox_shape_type() -> ShapeType:
	return shape_type


## Which of its hitboxes the body has right now, 0 for the usual one. Each has a shape of its own, so two that are
## the same kind (a standing and a crouched capsule) do not share one.
func _get_hitbox_slot() -> int:
	return 0


## Fits the collision shape to the hitbox. Does nothing until the nodes are there.
func _apply_dimensions() -> void:
	if not is_node_ready() or not is_instance_valid(collision_shape):
		return
	var size := _get_hitbox_dimensions()
	var shape := _get_shape(_get_hitbox_shape_type(), size, _get_hitbox_slot())
	if collision_shape.shape != shape:
		collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, size.y * 0.5, 0.0)


## The shape of kind [param type] for hitbox [param slot], made for this character alone, resized to fill
## [param size]. One is kept for each, so changing back and forth (a crouch) swaps between shapes that exist.
func _get_shape(type: ShapeType, size: Vector2, slot: int = 0) -> Shape3D:
	var key := slot * 16 + type
	var shape: Shape3D = _shapes.get(key)
	if shape == null:
		shape = _new_shape(type, collision_shape.shape)
		# The one in the scene belongs to the first hitbox that asked for it.
		if _shapes.values().has(shape):
			shape = _new_shape(type, null)
		_shapes[key] = shape
	_resize_shape(shape, size)
	return shape

## The shape in the scene when it is of kind [param type] and made for this character alone (editing a shared
## one would resize every character made from the same scene), otherwise a new one.
func _new_shape(type: ShapeType, current: Shape3D) -> Shape3D:
	var own := current != null and (current.resource_local_to_scene or current.resource_path.is_empty())
	match type:
		ShapeType.SPHERE:
			return current if own and current is SphereShape3D else SphereShape3D.new()
		ShapeType.BOX:
			return current if own and current is BoxShape3D else BoxShape3D.new()
		ShapeType.CYLINDER:
			return current if own and current is CylinderShape3D else CylinderShape3D.new()
	return current if own and current is CapsuleShape3D else CapsuleShape3D.new()


func _resize_shape(shape: Shape3D, size: Vector2) -> void:
	if shape is SphereShape3D:
		(shape as SphereShape3D).radius = size.y * 0.5
	elif shape is BoxShape3D:
		(shape as BoxShape3D).size = Vector3(size.x, size.y, size.x)
	elif shape is CylinderShape3D:
		(shape as CylinderShape3D).radius = size.x * 0.5
		(shape as CylinderShape3D).height = size.y
	elif shape is CapsuleShape3D:
		(shape as CapsuleShape3D).radius = minf(size.x * 0.5, size.y * 0.5)
		(shape as CapsuleShape3D).height = size.y
