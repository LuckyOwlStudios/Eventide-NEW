@tool
class_name WalkingCharacter3D
extends BaseCharacter3D
## The base class for all walking characters in the game.
##
## [b]Stance.[/b] A walking character is standing or crouching. [member stance] says which, and the hitbox
## follows it: crouching swaps the standing hitbox ([member BaseCharacter3D.dimensions] and
## [member BaseCharacter3D.shape_type]) for the crouched one ([member crouch_dimensions] and
## [member crouch_shape_type]), with the feet where they were. Change it in the inspector to see the crouched
## hitbox in the editor. Standing up needs room: [method can_stand_up] looks for a ceiling first, and
## [method set_stance] stays crouched under one.
##
## [b]Speed.[/b] How fast it walks and how high it jumps are [Attribute]s ([member movement_speed],
## [member jump_height]), and so are the factors that sprinting, strolling and crouching multiply the speed
## by. A buff or a debuff changes them by adding an [AttributeModifier], without knowing anything about
## whatever moves the character. The Ground group tunes how it feels on the ground.
##
## [b]Capabilities.[/b] [method can_walk], [method can_run], [method can_crouch] and [method can_jump] say
## what it may do right now: it must be able to do it at all, and nothing may be blocking it (add to a blocker
## such as [member can_run_blocker] to stop it for a while).
##
## Whatever drives the character (a [CharacterController], an AI) decides what it wants to do and calls into
## this class; this class owns what a stance is and what the character is capable of.

## The stance changed.
signal stance_changed(stance: STANCE)

enum STANCE {
	STANDING, ## When the character is standing
	CROUCHING ## When the character is crouched down
}

## How far smaller than the standing hitbox the stand-up test is, so a wall the character only touches does not
## count as being in the way.
const STAND_CHECK_SHRINK := 0.02
## How far up the stand-up test is lifted, so the floor under the feet does not count either.
const STAND_CHECK_LIFT := 0.02

## The current stance of this character
@export var stance := STANCE.STANDING:
	set(value):
		var changed := value != stance
		stance = value
		_apply_dimensions()
		if changed and is_node_ready() and not Engine.is_editor_hint():
			stance_changed.emit(stance)

@export_group("Attributes")
## Walking speed in meters per second before any modifiers.
@export_range(0.0, 50.0, 0.1, "or_greater", "suffix:m/s") var _movement_speed: float = 3.0:
	set(value):
		_movement_speed = maxf(value, 0.0)
		movement_speed.base_value = _movement_speed
## What sprinting multiplies the speed by.
@export_range(1.0, 5.0, 0.05) var _sprint_multiplier: float = 1.5:
	set(value):
		_sprint_multiplier = value
		sprint_multiplier.base_value = _sprint_multiplier
## What crouching multiplies the speed by. Stacks with strolling: both together multiply.
@export_range(0.05, 1.0, 0.05) var _crouch_multiplier: float = 0.5:
	set(value):
		_crouch_multiplier = value
		crouch_multiplier.base_value = _crouch_multiplier
## What strolling, the slow walk, multiplies the speed by. Stacks with crouching: both together multiply.
@export_range(0.05, 1.0, 0.05) var _stroll_multiplier: float = 0.5:
	set(value):
		_stroll_multiplier = value
		stroll_multiplier.base_value = _stroll_multiplier
## How high a standing jump goes, in meters, before any modifiers.
@export_range(0.0, 20.0, 0.05, "or_greater", "suffix:m") var _jump_height: float = 1.0:
	set(value):
		_jump_height = maxf(value, 0.0)
		jump_height.base_value = _jump_height

@export_group("Ground")
## How eagerly the character reaches its target speed on the ground.
@export_range(0.0, 100.0, 0.5) var ground_acceleration := 30.0
## Steering force while airborne. Low values mean only slight air control.
@export_range(0.0, 100.0, 0.5, "suffix:m/s²") var air_acceleration := 8.0
## How long after leaving a ledge a jump is still allowed.
@export_range(0.0, 0.5, 0.01, "suffix:s") var coyote_time := 0.12
## How early before landing a jump press is remembered.
@export_range(0.0, 0.5, 0.01, "suffix:s") var jump_buffer_time := 0.12
## The tallest step the character walks up (and down) without jumping.
@export_range(0.0, 1.0, 0.01, "suffix:m") var step_height := 0.35
## Steepest slope that counts as ground.
@export_range(0.0, 89.0, 0.5, "suffix:°") var max_floor_angle := 46.0

@export_group("Crouching")
## Width and height of the hitbox while crouched.
@export var crouch_dimensions := Vector2(0.8, 0.8):
	set(value):
		crouch_dimensions = Vector2(maxf(value.x, 0.01), maxf(value.y, 0.01))
		_apply_dimensions()
## The shape of the hitbox while crouched.
@export var crouch_shape_type := ShapeType.SPHERE:
	set(value):
		crouch_shape_type = value
		_apply_dimensions()

@export_group("Capabilities")
@export var _can_crouch: bool ## Can this character crouch?
@export var _can_run: bool ## Can this character run?
@export var _can_jump: bool ## Can this character jump?

# BLOCKERS
var can_walk_blocker := ActionBlocker.new()
var can_run_blocker := ActionBlocker.new()
var can_crouch_blocker := ActionBlocker.new()
var can_jump_blocker := ActionBlocker.new()

# Attributes
var movement_speed := Attribute.new(_movement_speed)
var sprint_multiplier := Attribute.new(_sprint_multiplier)
var crouch_multiplier := Attribute.new(_crouch_multiplier)
var stroll_multiplier := Attribute.new(_stroll_multiplier)
var jump_height := Attribute.new(_jump_height)


func _get_hitbox_dimensions() -> Vector2:
	return crouch_dimensions if stance == STANCE.CROUCHING else dimensions


func _get_hitbox_shape_type() -> ShapeType:
	return crouch_shape_type if stance == STANCE.CROUCHING else shape_type


func _get_hitbox_slot() -> int:
	return 1 if stance == STANCE.CROUCHING else 0


func is_crouching() -> bool:
	return stance == STANCE.CROUCHING


## Changes the stance, and with it the hitbox. Standing up under a low ceiling does nothing and returns
## false, and the character stays crouched.
func set_stance(value: STANCE) -> bool:
	if value == stance:
		return true
	if value == STANCE.STANDING and not can_stand_up():
		return false
	stance = value
	return true


## Whether the standing hitbox would fit right now. False under a low ceiling. It is checked a hair smaller
## than the hitbox, and lifted a hair, so walls and the floor the character is merely touching do not count.
func can_stand_up() -> bool:
	if not is_inside_tree() or Engine.is_editor_hint():
		return true
	var size := Vector2(maxf(dimensions.x - STAND_CHECK_SHRINK * 2.0, 0.01), maxf(dimensions.y - STAND_CHECK_SHRINK * 2.0, 0.01))
	var shape := _new_shape(shape_type, null)
	_resize_shape(shape, size)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var check := global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, dimensions.y * 0.5, 0.0))
	check.origin += global_basis.y.normalized() * STAND_CHECK_LIFT
	query.transform = check
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func can_walk() -> bool:
	return can_walk_blocker.is_permitted()


func can_run() -> bool:
	return _can_run and can_run_blocker.is_permitted()


func can_crouch() -> bool:
	return _can_crouch and can_crouch_blocker.is_permitted()


func can_jump() -> bool:
	return _can_jump and can_jump_blocker.is_permitted()


## The body has just been moved without the character having moved, by a stair or by a correction from the
## network, and what is seen of it should glide instead of jumping. [param world_offset] is how far from where
## the body now is the view should start. A character with nothing to show does nothing.
func add_visual_offset(_world_offset: Vector3) -> void:
	pass


## Forgets any glide in progress, for a move that is meant to be seen as a jump.
func clear_visual_offset() -> void:
	pass
