## Base Area3D for anything that can be targeted by InteractionRayCast3D.
## New instances begin with one "Interact" option using the interact Input Map
## action (F by default). Add more InteractionOption resources as needed.
class_name InteractableObject3D
extends Area3D

const INTERACTION_OPTION_SCRIPT := preload("res://Components/Interaction/interaction_option.gd")

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
@export var interaction_options: Array[InteractionOption] = []

@export_group("Interaction Prompt")
## Optional Node3D that precisely marks where the interaction list is anchored.
@export var prompt_anchor: Node3D

## Local-space offset used above this Area3D or Prompt Anchor.
@export var prompt_local_offset := Vector3(0.0, 0.5, 0.0)

@export_group("Interaction Selector")
## Draws Selector.svg around this object while it is targeted.
@export var show_interaction_selector := true

## Local-space box projected to the screen to size the selector. This box follows
## this node's position, rotation, and scale, so it naturally shrinks with distance.
@export_custom(PROPERTY_HINT_LINK, "") var selector_size: Vector3 = Vector3.ONE

## Moves the center of the selector box without moving the interaction Area3D.
@export var selector_local_offset := Vector3.ZERO

## Extra screen-space room between the projected object and selector corners.
@export_range(0.0, 64.0, 1.0, "or_greater", "suffix:px") var selector_screen_padding := 8.0

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

func _init() -> void:
	if interaction_options.is_empty():
		interaction_options.append(_create_default_interaction_option())

func _ready() -> void:
	monitorable = true
	_update_runtime_status()

func _exit_tree() -> void:
	_set_hover_overlay_applied(false)

## World-space position where the interaction prompt should be placed.
func get_prompt_world_position() -> Vector3:
	if is_instance_valid(prompt_anchor):
		return prompt_anchor.to_global(prompt_local_offset)
	return to_global(prompt_local_offset)

## Eight world-space corners of the configurable selector box. Projecting every
## corner keeps rotated and scaled objects enclosed by the 2D selector.
func get_selector_world_corners() -> PackedVector3Array:
	var corners := PackedVector3Array()
	var half_size := selector_size.abs() * 0.5
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var local_corner := selector_local_offset + Vector3(
					half_size.x * x_sign,
					half_size.y * y_sign,
					half_size.z * z_sign
				)
				corners.append(to_global(local_corner))
	return corners

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
	if not can_interact(interactor, option_index):
		_update_runtime_status()
		return false
	interaction_requested.emit(interactor)
	interaction_option_requested.emit(interactor, option_index)
	if not _interact_option(interactor, option_index):
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
	interaction_enabled_changed.emit(interaction_enabled)
	_update_runtime_status()

func _update_runtime_status() -> void:
	if not interaction_enabled:
		runtime_status = "Interaction disabled."
		return
	runtime_status = "%s configured interaction option(s)." % get_interaction_option_count()
