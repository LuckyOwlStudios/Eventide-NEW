@tool
class_name Player
extends WalkingCharacter3D
## The Player in game.
##
## [b]Head.[/b] The [code]Head[/code] node is where the player sees from. It sits at [member head_height] of the
## way up the hitbox, so crouching, which shrinks the hitbox, lowers it, smoothly. Whatever looks through it
## (the camera, the held item) hangs from it.
##
## [b]Perspectives.[/b] The player is seen two ways: from inside, through their own eyes, or from outside, as a
## body in the world. [member perspective] says which one this machine has (by default, first person for
## the player at the keyboard and third person for everybody else), and [method set_first_person] changes it,
## to spectate a player, say. Under [member first_person_root] goes what only the one looking through the
## player's eyes sees (arms); under the [code]Model[/code] node goes what the world sees. From inside the
## model is not drawn but still casts its shadow, so it is never in the way of the camera and the player
## can still see their own shadow. From outside the first person root is hidden and the model is drawn as
## authored.
##
## [b]Facing.[/b] Looking around turns the yaw pivot under the head, not the body, so the model is turned to
## follow it, smoothly: it faces where the player looks.

## The perspective changed. [param first_person] is whether this machine now looks through the player's eyes.
signal perspective_changed(first_person: bool)

## The render layer the model's meshes are on, as seen from the layer masks of lights and cameras. Lights that
## belong to the one looking through the player's eyes leave it out, so the player's own body never shadows
## their own flashlight.
const OWN_BODY_LAYER := 1 << 19
## The most a stair or a correction may move the view off the body.
const MAXIMUM_VISUAL_OFFSET := 1.0

enum Perspective {
	## First person for the player at this machine, third person for everyone else.
	AUTO,
	## Seen through the character's own eyes.
	FIRST_PERSON,
	## Seen from outside, as a body in the world.
	THIRD_PERSON,
}

@export var health: Health
@export var stamina: Stamina

@export_group("Head")
## How high the head is, from 0 at the feet to 1 at the top of the current hitbox.
@export_range(0.0, 1.0, 0.01) var head_height := 0.9:
	set(value):
		head_height = value
		_apply_dimensions()
## How quickly the head rises and lowers with the hitbox.
@export_range(0.0, 60.0, 0.5) var head_follow_speed := 14.0
## How quickly a stair step or a network correction fades out of the view, instead of jumping it.
@export_range(0.0, 60.0, 0.5) var correction_smoothing_speed := 12.0

@export_group("Perspective")
@export var perspective := Perspective.AUTO:
	set(value):
		perspective = value
		if is_node_ready():
			refresh_perspective()
## What only the one looking through the player's eyes sees. Found as "FirstPersonRoot" under the camera
## when left empty.
@export var first_person_root: Node3D
## Whether the model turns to follow where the player looks.
@export var model_follows_look := true
## How quickly it catches up. 0 turns it at once.
@export_range(0.0, 60.0, 0.5) var model_turn_speed := 12.0

## The head of this player: the point of view, and the node that moves up and down with the stance.
@onready var head: Node3D = get_node_or_null("Head")
## What the world sees of the player: its model.
@onready var third_person_root: Node3D = get_node_or_null("Model")

var _first_person := false
var _head_y := 0.0
var _head_placed := false
## How far from where the body is the view still is, in the world. It fades away (see
## [member correction_smoothing_speed]).
var _visual_offset := Vector3.ZERO
var _model_rest_yaw := 0.0
## Mesh to the shadow mode it had, for putting it back.
var _original_shadows: Dictionary[GeometryInstance3D, int] = {}


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(first_person_root):
		first_person_root = get_node_or_null("Head/YawPivot/PitchPivot/Camera3D/FirstPersonRoot")
	if is_instance_valid(third_person_root):
		_model_rest_yaw = third_person_root.rotation.y
	refresh_perspective()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_follow_head(delta)
	_face_model(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_paste") and health:
		health.decrease(20.0)
	if event.is_action_pressed("ui_copy") and health:
		health.increase(20.0)


## Where the head rests, which is where it is at the current stance, before a stair or a correction
## moves the view off it.
func get_head_rest_position() -> Vector3:
	return Vector3(0.0, _head_y if _head_placed else _get_head_target(), 0.0)


## A stair or a correction from the network moved the body, so the view starts where it was and glides to
## where the body is now.
func add_visual_offset(world_offset: Vector3) -> void:
	_visual_offset = (_visual_offset + world_offset).limit_length(MAXIMUM_VISUAL_OFFSET)


func clear_visual_offset() -> void:
	_visual_offset = Vector3.ZERO


## Where the player sees from, and which way. A camera looking through the player sits here.
func get_view_transform() -> Transform3D:
	return head.global_transform if head != null else global_transform


## True when this machine looks through the player's eyes.
func is_first_person() -> bool:
	return _first_person


## Looks through the player's eyes (true) or sees them from outside (false), whatever [member perspective]
## says, until [method refresh_perspective]. Spectating somebody is one call.
func set_first_person(value: bool) -> void:
	var changed := value != _first_person
	_first_person = value
	_apply_perspective()
	if changed:
		perspective_changed.emit(value)


## Works out the perspective from [member perspective] again.
func refresh_perspective() -> void:
	set_first_person(_wants_first_person())


func _apply_dimensions() -> void:
	super._apply_dimensions()
	if not is_node_ready():
		return
	# In the editor the head is where the numbers put it. In the game it only starts there, and then follows.
	if Engine.is_editor_hint() or not _head_placed:
		_head_y = _get_head_target()
		_head_placed = true
		if is_instance_valid(head):
			head.position = Vector3(0.0, _head_y, 0.0)


func _get_head_target() -> float:
	return _get_hitbox_dimensions().y * head_height


func _follow_head(delta: float) -> void:
	var target := _get_head_target()
	_head_y = target if head_follow_speed <= 0.0 else lerpf(_head_y, target, 1.0 - exp(-head_follow_speed * delta))
	_visual_offset = _visual_offset.lerp(Vector3.ZERO, 1.0 if correction_smoothing_speed <= 0.0 else 1.0 - exp(-correction_smoothing_speed * delta))
	if _visual_offset.length_squared() < 0.00000001:
		_visual_offset = Vector3.ZERO
	if is_instance_valid(head):
		head.position = Vector3(0.0, _head_y, 0.0) + _to_parent_space(head, _visual_offset)


## [param world_vector] as the head's parent sees it.
func _to_parent_space(node: Node3D, world_vector: Vector3) -> Vector3:
	var parent := node.get_parent_node_3d()
	if parent == null:
		return world_vector
	return parent.global_basis.orthonormalized().inverse() * world_vector


func _face_model(delta: float) -> void:
	if not model_follows_look or not is_instance_valid(third_person_root) or not is_instance_valid(head):
		return
	var yaw_pivot := head.get_node_or_null("YawPivot") as Node3D
	if yaw_pivot == null:
		return
	var weight := 1.0 if model_turn_speed <= 0.0 else 1.0 - exp(-model_turn_speed * delta)
	third_person_root.rotation.y = lerp_angle(third_person_root.rotation.y, _model_rest_yaw + yaw_pivot.rotation.y, weight)


func _wants_first_person() -> bool:
	match perspective:
		Perspective.FIRST_PERSON:
			return true
		Perspective.THIRD_PERSON:
			return false
	return NetworkSession.is_local_authority(self)


func _apply_perspective() -> void:
	if is_instance_valid(first_person_root):
		first_person_root.visible = _first_person
	if not is_instance_valid(third_person_root):
		return
	for mesh in _find_meshes(third_person_root):
		if _first_person:
			if not _original_shadows.has(mesh):
				_original_shadows[mesh] = mesh.cast_shadow
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif _original_shadows.has(mesh):
			mesh.cast_shadow = _original_shadows[mesh] as GeometryInstance3D.ShadowCastingSetting
			_original_shadows.erase(mesh)
		mesh.layers |= OWN_BODY_LAYER


func _find_meshes(root: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		found.append(root as GeometryInstance3D)
	for child in root.get_children():
		found.append_array(_find_meshes(child))
	return found
