class_name ItemMotion
extends Node
## Makes the item in the holder's hand bob with the way the character moves.
##
## The mount of a first-person item hangs from the camera, so the item moves exactly as the camera does:
## when the head bobs, tilts or takes a landing, the item sits perfectly still on screen and the world
## swings behind it, which looks like a sticker on the lens. This node lets the hand trail the head. It
## takes the head's motion from [HeadMotion] (its pose, with the bob, the tilt, the jump and the landing
## in it), and moves a pivot between the camera and the item mount so the item shares only part of it,
## and a little late. The camera still moves the whole amount; the item moves against it on screen.
##
## It reads the head's pose and does not make a gait of its own, so the item bobs with the same steps as
## the footsteps and the head, follows every profile (a limp, a crouch, a creature's stride), and is
## turned down by the same accessibility settings. [member strength] is its own.
##
## [codeblock]
## Camera3D
## └─ Pivot          moved by this node
##    └─ ItemMount   where ItemHolder puts the item (and pulls it back from walls)
## [/codeblock]
## Nothing else changes: the pivot sits at the camera's origin and only turns and slides a little.

## Where the pivot is, between the camera and the holder's first-person mount.
@export var pivot: Node3D
## Found next to this node when left empty.
@export var head_motion: HeadMotion
## Whose item is in hand, for its own [member ItemActor.bob_scale]. Found next to this node when left empty.
@export var holder: ItemHolder
## Off, the item is fixed in the view as it would be with no pivot.
@export var enabled := true
## Scales all of it. Handy for an accessibility setting; 0 turns it off.
@export_range(0.0, 2.0, 0.05) var strength := 1.0
## How much of the head's motion the hand does not share: 0 moves with the head exactly, 1 holds the
## item still in the world while the head moves around it.
@export_range(0.0, 1.0, 0.01) var steadiness := 0.5
## How quickly the hand catches up with where it is going. Lower is a heavier, lazier hand.
@export_range(1.0, 60.0, 0.5) var response := 22.0

var _offset := Vector3.ZERO
var _rotation := Quaternion.IDENTITY


func _init() -> void:
	# After HeadMotion has moved the camera this frame, so the two agree on where the head is.
	process_priority = 10


func _ready() -> void:
	if not is_instance_valid(head_motion):
		head_motion = _find_sibling(HeadMotion) as HeadMotion
	if not is_instance_valid(holder):
		holder = _find_sibling(ItemHolder) as ItemHolder
	if not is_instance_valid(pivot) or not is_instance_valid(head_motion):
		push_error("[ItemMotion] needs a pivot and a HeadMotion.")
		set_process(false)


func _process(delta: float) -> void:
	if not is_instance_valid(pivot) or not is_instance_valid(head_motion):
		return
	if not enabled:
		_offset = Vector3.ZERO
		_rotation = Quaternion.IDENTITY
		pivot.transform = Transform3D.IDENTITY
		return
	var head := head_motion.get_pose()
	# The hand follows the head by the share it has; the camera is already all the way at the head's pose.
	var shared := 1.0 - get_unshared()
	var hand := Transform3D(
		Basis(Quaternion.IDENTITY.slerp(head.basis.get_rotation_quaternion(), shared)),
		head.origin * shared,
	)
	# Where that puts the item as the camera sees it, which is nowhere at all when the whole is shared.
	var wanted := head.affine_inverse() * hand
	var weight := 1.0 - exp(-response * maxf(delta, 0.0))
	_offset = _offset.lerp(wanted.origin, weight)
	_rotation = _rotation.slerp(wanted.basis.get_rotation_quaternion(), weight)
	pivot.transform = Transform3D(Basis(_rotation), _offset)


## The share of the head's motion the item does not share right now, 0 to 1, with the item in hand
## taken into account.
func get_unshared() -> float:
	var item_scale := 1.0
	if is_instance_valid(holder) and holder.has_equipped_item():
		item_scale = holder.equipped_actor.bob_scale
	return clampf(steadiness * strength * item_scale, 0.0, 1.0)


func _find_sibling(type: Variant) -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if is_instance_of(child, type):
			return child
	return null
