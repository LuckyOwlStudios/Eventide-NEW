## Base Area3D for anything that can be targeted by InteractionRayCast3D.
## New instances begin with one "Interact" option using the interact Input Map
## action (F by default). Add more InteractionOption resources as needed.
class_name InteractableObject3D
extends Area3D

const INTERACTION_OPTION_SCRIPT := preload("res://Components/Interaction/interaction_option.gd")
const DOT_SCENE := preload("res://Components/UI/Interaction/InteractableDot.tscn")
const PROMPT_SCENE := preload("res://Components/UI/Interaction/InteractablePrompt.tscn")

## Every interactable in the tree is in this group, which is how prompters decide which dots to turn on.
const GROUP: StringName = &"interactable_objects"

## An ordinary Area3D may store an InteractableObject3D under this metadata key.
## InteractionRayCast3D will then treat that area as this interaction target. This
## is useful when gameplay components need a freely shaped interaction volume
## without making the volume itself own the gameplay behavior.
const INTERACTION_TARGET_META: StringName = &"interaction_target"

## Compatibility signal emitted for every accepted option request.
signal interaction_requested(interactor: Node3D)
## Compatibility signal emitted after any option succeeds.
signal interacted(interactor: Node3D)
## Includes the selected array index for objects with multiple options.
signal interaction_option_requested(interactor: Node3D, option_index: int)
## Includes the selected array index after that option succeeds.
signal interaction_option_interacted(interactor: Node3D, option_index: int)
signal interaction_enabled_changed(is_enabled: bool)

## Master switch. Disabled objects and all their options are ignored.
@export var interaction_enabled := true

## Every action lives here. Each InteractionOption defines its own input
## action, prompt, trigger type, timing, cooldown, and one-shot behavior.
@export var interaction_options: Array[InteractionOption] = [
	INTERACTION_OPTION_SCRIPT.new().duplicate()
]

@export_group("Interaction Prompt")
## Optional Node3D that precisely marks where the interaction list is anchored.
@export var prompt_anchor: Node3D

## Local-space offset used above this Area3D or Prompt Anchor.
@export var prompt_local_offset := Vector3(0.0, 0.5, 0.0)

## Centers the prompt list on its anchor point instead of placing it beside it.
## Only applies while the selector is disabled, since the selector is what the
## prompt otherwise sits next to.
@export var center_prompt := false

@export_group("Interaction Selector")
## Draws Selector.svg around this object while it is targeted.
@export var show_interaction_selector := true

## Local-space box projected to the screen to size the selector. This box follows
## this node's position, rotation, and scale, so it naturally shrinks with distance.
@export_custom(PROPERTY_HINT_LINK, "") var selector_size: Vector3 = Vector3.ONE

## Moves the center of the selector box without moving the interaction Area3D.
@export var selector_local_offset := Vector3.ZERO:
	set(value):
		selector_local_offset = value
		if is_instance_valid(_dot):
			_dot.position = get_selector_center_local()

## Extra screen-space room between the projected object and selector corners.
@export_range(0.0, 64.0, 1.0, "or_greater", "suffix:px") var selector_screen_padding := 8.0

@export_group("Distance Dot")
## Shows a small dot on this object while it can be used but the player is not looking at it.
## The dot is a child of this node, fades out with distance, and is hidden while the object is
## looked at (the selector and options take its place).
@export var show_distance_dot := true

## How far away the dot still shows. It is fully visible up close and fades out toward this.
## This is the Distance Fade Min Distance of the dot's material.
@export_range(0.5, 100.0, 0.5, "or_greater", "suffix:m") var dot_distance := 8.0:
	set(value):
		dot_distance = value
		_apply_dot_distance()

@export_group("Hover Outline")
## Mesh, CSG shape, or other GeometryInstance3D that receives the hover overlay.
## Leave empty when this interactable should not display an outline.
@export var hover_geometry_instance: Array[GeometryInstance3D]

## Material assigned to Hover Geometry Instance's Material Overlay while any
## interaction ray is focused on this object. Its previous overlay is restored.
@export var hover_material_overlay: Material = preload("uid://fsuw6gbhwd7j")

@export_category("Runtime Diagnostics (read only)")
## Updated after interactions and useful from the Remote Inspector.
@export_multiline var runtime_status := "Ready for interaction."

var _last_option_times_msec: Dictionary = {}
var _used_one_shot_options: Dictionary = {}
var _hover_sources: Dictionary = {}
var _overlay_before_hover: Material
var _hover_overlay_applied := false
var _dot: MeshInstance3D
## What the prompter of the player in reach says about this object's dot (see set_dot_allowed).
var _dot_allowed := false
var _prompt: InteractablePrompt

func _init() -> void:
	if interaction_options.is_empty():
		interaction_options.append(_create_default_interaction_option())

func _enter_tree() -> void:
	# Only the interaction ray looks at interactables, so they sit on their own layer and
	# scan nothing. Anything a scene set to something other than Godot's stock value of 1
	# is left alone. (This cannot live in _init: a scene applies its saved properties
	# before assigning the script, so _init would overwrite them.)
	if collision_layer == 1:
		collision_layer = PhysicsLayers.INTERACTABLES
	if collision_mask == 1:
		collision_mask = PhysicsLayers.INTERACTABLE_MASK

func _ready() -> void:
	monitorable = true
	add_to_group(GROUP)
	_create_dot()
	_update_runtime_status()

func _exit_tree() -> void:
	_set_hover_overlay_applied(false)

## Middle of the selector box in this node's local space. Override this and
## get_selector_half_size_local() for objects whose box is not simply Selector Size.
func get_selector_center_local() -> Vector3:
	return selector_local_offset

## Half the selector box's size along each of this node's own axes.
func get_selector_half_size_local() -> Vector3:
	return selector_size.abs() * 0.5

## World-space position of the distance dot: the middle of the selector box.
func get_dot_world_position() -> Vector3:
	return to_global(get_selector_center_local())

## The dot node, so scenes and tests can look at or restyle it.
func get_dot() -> MeshInstance3D:
	return _dot

## Called every frame by the prompter of the player who is in reach (never by other players'): says
## whether this object is worth a dot for them right now. The dot also needs [member show_distance_dot]
## and [member interaction_enabled], and stays hidden while an interaction ray is looking at the object.
func set_dot_allowed(allowed: bool) -> void:
	_dot_allowed = allowed
	_update_dot_visibility()

func _create_dot() -> void:
	_dot = DOT_SCENE.instantiate() as MeshInstance3D
	_dot.name = &"Dot"
	_dot.position = get_selector_center_local()
	_dot.visible = false
	# Internal, so code that walks this node's children never meets it.
	add_child(_dot, false, Node.INTERNAL_MODE_BACK)
	_apply_dot_distance()

func _apply_dot_distance() -> void:
	if not is_instance_valid(_dot):
		return
	var material := _dot.mesh.material as BaseMaterial3D
	if material != null:
		material.distance_fade_min_distance = dot_distance

func _update_dot_visibility() -> void:
	if not is_instance_valid(_dot):
		return
	_dot.visible = (
		_dot_allowed
		and show_distance_dot
		and interaction_enabled
		and _hover_sources.is_empty()
	)

## Where the prompt hangs, in this object's local space: the middle of the selector box while the
## selector is on, otherwise the prompt spot (which follows [param focus_point] on objects that
## want that, such as ladders).
func get_prompt_anchor_local(focus_point: Vector3 = Vector3.INF) -> Vector3:
	if show_interaction_selector:
		return get_selector_center_local()
	if focus_point.is_finite():
		return to_local(get_prompt_world_position_for(focus_point))
	return to_local(get_prompt_world_position())

## The selector and options of this object, a child of it like the dot (made the first time it is
## needed). Because it is part of the object, a ship at full speed carries it along, drawn as smoothly
## as the ship itself. The player's prompter gives it the options texture and sizes it; call
## hide_prompt() when the player looks away.
func show_prompt(options_texture: Texture2D) -> InteractablePrompt:
	if not is_instance_valid(_prompt):
		_prompt = PROMPT_SCENE.instantiate() as InteractablePrompt
		# Internal, so code that walks this node's children never meets it.
		add_child(_prompt, false, Node.INTERNAL_MODE_BACK)
	_prompt.set_options_texture(options_texture)
	_prompt.position = get_prompt_anchor_local()
	# It may have been left somewhere else, and must not slide from there.
	_prompt.reset_physics_interpolation()
	return _prompt


func hide_prompt() -> void:
	if is_instance_valid(_prompt):
		_prompt.visible = false


## The prompt of this object, or null if it has never been looked at.
func get_prompt() -> InteractablePrompt:
	return _prompt if is_instance_valid(_prompt) else null


## Moves the prompt while it is showing, for prompts that follow where the player looks.
func update_prompt_anchor(focus_point: Vector3 = Vector3.INF) -> void:
	if not is_instance_valid(_prompt):
		return
	var wanted := get_prompt_anchor_local(focus_point)
	if not _prompt.position.is_equal_approx(wanted):
		_prompt.position = wanted

## Half the selector box's width along [param direction] (a unit vector in world space), counting
## this object's rotation and scale. With the camera's right and up it gives the box's size on screen.
func get_selector_half_extent(direction: Vector3) -> float:
	var half := get_selector_half_size_local()
	return (
		absf(direction.dot(global_transform.basis.x * half.x))
		+ absf(direction.dot(global_transform.basis.y * half.y))
		+ absf(direction.dot(global_transform.basis.z * half.z))
	)

## World-space position where the interaction prompt should be placed.
func get_prompt_world_position() -> Vector3:
	if is_instance_valid(prompt_anchor):
		return prompt_anchor.to_global(prompt_local_offset)
	return to_global(prompt_local_offset)

## Prompt position while an interaction ray is looking at [param focus_point] on
## this object. Override it for long objects whose prompt should follow the
## player's gaze; the default ignores the gaze.
func get_prompt_world_position_for(_focus_point: Vector3) -> Vector3:
	return get_prompt_world_position()

## Called by interaction rays as focus enters or leaves this object. Tracking
## each ray separately prevents one player from removing another player's hover.
func set_interaction_hovered(source: Object, hovered: bool) -> void:
	if source == null:
		return
	var source_id := source.get_instance_id()
	if hovered:
		_hover_sources[source_id] = weakref(source)
	else:
		_hover_sources.erase(source_id)
	_prune_hover_sources()
	_set_hover_overlay_applied(not _hover_sources.is_empty())
	_update_dot_visibility()

func _prune_hover_sources() -> void:
	for source_id in _hover_sources.keys():
		var source_reference: WeakRef = _hover_sources[source_id]
		if source_reference.get_ref() == null:
			_hover_sources.erase(source_id)

func _set_hover_overlay_applied(value: bool) -> void:
	if _hover_overlay_applied == value:
		return
	if value:
		if hover_geometry_instance.is_empty() or hover_material_overlay == null:
			return
		#_overlay_before_hover = hover_geometry_instance.material_overlay
		#hover_geometry_instance.material_overlay = hover_material_overlay
		_hover_overlay_applied = true
	elif _hover_overlay_applied:
		#if not hover_geometry_instance.is_empty():
			#for mesh in hover_geometry_instance:
				#mesh.material_overlay = _overlay_before_hover
		_overlay_before_hover = null
		_hover_overlay_applied = false

func get_interaction_option_count() -> int:
	return interaction_options.size()

## Returns an InteractionOption Resource, or null for an invalid custom entry.
func get_interaction_option(option_index: int) -> Resource:
	if option_index < 0 or option_index >= interaction_options.size():
		return null
	var option := interaction_options[option_index]
	return option if option is INTERACTION_OPTION_SCRIPT else null

## Finds a configured option by its stable Option ID. This is safer than storing
## an array index in long-lived gameplay code because designers may reorder it.
func find_interaction_option_index(option_id: StringName) -> int:
	for option_index in get_interaction_option_count():
		var option := get_interaction_option(option_index)
		if option != null and StringName(option.option_id) == option_id:
			return option_index
	return -1

## Indices currently available to the supplied actor. The prompt and input code
## both use this list, so unavailable options are neither shown nor triggerable.
func get_available_interaction_indices(interactor: Node3D) -> Array[int]:
	var result: Array[int] = []
	for option_index in get_interaction_option_count():
		if can_interact(interactor, option_index):
			result.append(option_index)
	return result

## Returns whether one indexed option can currently be used. Override
## _can_interact_option() for object-specific rules without replacing cooldowns.
func can_interact(interactor: Node3D, option_index: int = 0) -> bool:
	if not interaction_enabled:
		return false
	var option := get_interaction_option(option_index)
	if option == null or not bool(option.enabled):
		return false
	if _used_one_shot_options.has(option_index):
		return false
	var now := Time.get_ticks_msec()
	var option_last_time := int(_last_option_times_msec.get(option_index, -1))
	if float(option.cooldown_seconds) > 0.0 and option_last_time >= 0:
		if now - option_last_time < roundi(float(option.cooldown_seconds) * 1000.0):
			return false
	return _can_interact_option(interactor, option_index)

## Requests one indexed option and returns true when it succeeds.
func interact(interactor: Node3D, option_index: int = 0) -> bool:
	return _perform_interaction(interactor, option_index, false, Vector3.ZERO)


## Requests one indexed option with the exact world point selected by the
## interaction detector. Existing interactables continue using _interact_option;
## spatial interactables can override _interact_option_at instead.
func interact_at(
	interactor: Node3D,
	world_position: Vector3,
	option_index: int = 0,
) -> bool:
	return _perform_interaction(interactor, option_index, true, world_position)


func _perform_interaction(
	interactor: Node3D,
	option_index: int,
	has_world_position: bool,
	world_position: Vector3,
) -> bool:
	if not can_interact(interactor, option_index):
		_update_runtime_status()
		return false
	interaction_requested.emit(interactor)
	interaction_option_requested.emit(interactor, option_index)
	var accepted := (
		_interact_option_at(interactor, world_position, option_index)
		if has_world_position
		else _interact_option(interactor, option_index)
	)
	if not accepted:
		runtime_status = "Option %s was rejected by object behavior." % option_index
		return false
	var now := Time.get_ticks_msec()
	_last_option_times_msec[option_index] = now
	var option := get_interaction_option(option_index)
	if option != null and bool(option.one_shot):
		_used_one_shot_options[option_index] = true
	interacted.emit(interactor)
	interaction_option_interacted.emit(interactor, option_index)
	_update_runtime_status()
	return true

func _create_default_interaction_option() -> InteractionOption:
	var option := INTERACTION_OPTION_SCRIPT.new() as InteractionOption
	option.option_id = &"interact"
	option.input_action = &"interact"
	option.prompt = "Interact"
	return option


## Override this to restrict individual options. The integer is the exported
## Interaction Options array index.
func _can_interact_option(_interactor: Node3D, _option_index: int) -> bool:
	return true

## Override this for indexed behavior. The default delegates to legacy
## _interact(), so existing one-action interactables continue to work.
func _interact_option(interactor: Node3D, _option_index: int) -> bool:
	return _interact(interactor)


## Override this when interaction behavior depends on the selected world point.
## By default it preserves existing _interact_option behavior.
func _interact_option_at(
	interactor: Node3D,
	_world_position: Vector3,
	option_index: int,
) -> bool:
	return _interact_option(interactor, option_index)

## Existing one-action objects may continue overriding this method.
func _interact(_interactor: Node3D) -> bool:
	return true

func set_interaction_enabled(value: bool) -> void:
	if interaction_enabled == value:
		return
	interaction_enabled = value
	if not interaction_enabled:
		_hover_sources.clear()
		_set_hover_overlay_applied(false)
	_update_dot_visibility()
	interaction_enabled_changed.emit(interaction_enabled)
	_update_runtime_status()

func _update_runtime_status() -> void:
	if not interaction_enabled:
		runtime_status = "Interaction disabled."
		return
	runtime_status = "%s configured interaction option(s)." % get_interaction_option_count()
