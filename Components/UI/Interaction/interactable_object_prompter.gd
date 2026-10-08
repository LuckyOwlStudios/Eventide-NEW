class_name InteractableObjectPrompter
extends Node3D

## Displays every available interaction beside a projected screen-space selector.

signal entry_action_pressed(interactable: InteractableObject3D, option_index: int)
signal entry_interaction_succeeded(interactable: InteractableObject3D, option_index: int)

const KEY_BIND_INTERACTION_ENTRY := preload("res://Components/UI/Interaction/KeyBindInteractionEntry.tscn")

## Offset from the selector's right edge. When the selector is disabled, this is
## applied to the object's Prompt Anchor instead.
@export var screen_offset := Vector2(18.0, 0.0)
@export_range(0.0, 128.0, 1.0) var screen_margin := 20.0

@onready var selector: TextureRect = %Selector
@onready var option_list: VBoxContainer = %OptionList

var _interaction_ray: InteractionRayCast3D
var _interactable_object: InteractableObject3D
var _option_indices: Array[int] = []
var _entries: Dictionary[int, KeybindInteractionEntry] = {}

func _ready() -> void:
	selector.hide()
	option_list.hide()

func _process(_delta: float) -> void:
	_update_screen_position()

func bind_to_interaction_ray(interaction_ray: InteractionRayCast3D) -> void:
	if _interaction_ray == interaction_ray:
		return
	_disconnect_interaction_ray()
	_interaction_ray = interaction_ray
	if not is_instance_valid(_interaction_ray):
		clear()
		return
	_interaction_ray.hold_progress_changed.connect(_on_hold_progress_changed)
	_interaction_ray.interaction_option_succeeded.connect(_on_interaction_option_succeeded)

func display_options(interactable: InteractableObject3D, option_indices: Array[int]) -> void:
	if not is_instance_valid(interactable) or option_indices.is_empty():
		clear()
		return
	if _interactable_object == interactable and _option_indices == option_indices:
		option_list.show()
		return
	_interactable_object = interactable
	_option_indices = option_indices.duplicate()
	_rebuild_entries()
	option_list.show()
	_update_screen_position()

func clear() -> void:
	_interactable_object = null
	_option_indices.clear()
	_entries.clear()
	for child in option_list.get_children():
		option_list.remove_child(child)
		child.queue_free()
	selector.hide()
	option_list.hide()

func get_entry(option_index: int) -> KeybindInteractionEntry:
	return _entries.get(option_index)

func _rebuild_entries() -> void:
	_entries.clear()
	for child in option_list.get_children():
		option_list.remove_child(child)
		child.queue_free()
	for option_index in _option_indices:
		var option := _interactable_object.get_interaction_option(option_index) as InteractionOption
		if option == null:
			continue
		var entry := KEY_BIND_INTERACTION_ENTRY.instantiate() as KeybindInteractionEntry
		option_list.add_child(entry)
		entry.setup(_interactable_object, option, option_index)
		entry.action_pressed.connect(_on_entry_action_pressed)
		entry.interaction_succeeded.connect(_on_entry_interaction_succeeded)
		_entries[option_index] = entry

func _update_screen_position() -> void:
	if not is_instance_valid(_interactable_object):
		return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		_set_prompt_visible(false)
		return
	var prompt_position := _interactable_object.get_prompt_world_position()
	if camera.is_position_behind(prompt_position):
		_set_prompt_visible(false)
		return
	option_list.show()
	var desired_position: Vector2
	if _interactable_object.show_interaction_selector:
		var selector_rect := _project_selector_rect(camera)
		if selector_rect.has_area():
			selector.position = selector_rect.position
			selector.size = selector_rect.size
			selector.show()
			desired_position = Vector2(
				selector_rect.end.x,
				selector_rect.get_center().y - option_list.size.y * 0.5
			) + screen_offset
		else:
			selector.hide()
			desired_position = camera.unproject_position(prompt_position) + screen_offset
	else:
		selector.hide()
		desired_position = (
			camera.unproject_position(prompt_position)
			- Vector2(0.0, option_list.size.y * 0.5)
			+ screen_offset
		)
	var viewport_size := get_viewport().get_visible_rect().size
	var maximum_position := Vector2(
		maxf(screen_margin, viewport_size.x - option_list.size.x - screen_margin),
		maxf(screen_margin, viewport_size.y - option_list.size.y - screen_margin)
	)
	option_list.position = desired_position.clamp(
		Vector2(screen_margin, screen_margin),
		maximum_position
	)

func _project_selector_rect(camera: Camera3D) -> Rect2:
	var minimum_point := Vector2(INF, INF)
	var maximum_point := Vector2(-INF, -INF)
	var has_projected_corner := false
	for world_corner in _interactable_object.get_selector_world_corners():
		if camera.is_position_behind(world_corner):
			continue
		var screen_point := camera.unproject_position(world_corner)
		minimum_point = minimum_point.min(screen_point)
		maximum_point = maximum_point.max(screen_point)
		has_projected_corner = true
	if not has_projected_corner:
		return Rect2()
	var padding := Vector2.ONE * _interactable_object.selector_screen_padding
	var projected_rect := Rect2(
		minimum_point - padding,
		maximum_point - minimum_point + padding * 2.0
	)
	return _preserve_selector_aspect(projected_rect)

func _preserve_selector_aspect(projected_rect: Rect2) -> Rect2:
	var object_scale := _interactable_object.global_transform.basis.get_scale().abs()
	var target_width := absf(_interactable_object.selector_size.x * object_scale.x)
	var target_height := absf(_interactable_object.selector_size.y * object_scale.y)
	if target_width <= 0.0001 or target_height <= 0.0001:
		return projected_rect
	var target_aspect := target_width / target_height
	var adjusted_size := projected_rect.size
	var projected_aspect := adjusted_size.x / maxf(adjusted_size.y, 0.0001)
	if projected_aspect < target_aspect:
		adjusted_size.x = adjusted_size.y * target_aspect
	elif projected_aspect > target_aspect:
		adjusted_size.y = adjusted_size.x / target_aspect
	return Rect2(projected_rect.get_center() - adjusted_size * 0.5, adjusted_size)

func _set_prompt_visible(is_visible: bool) -> void:
	option_list.visible = is_visible
	selector.visible = is_visible and _interactable_object.show_interaction_selector

func _on_hold_progress_changed(
		interactable: Area3D,
		option_index: int,
		progress: float
) -> void:
	if interactable != _interactable_object:
		return
	var entry := get_entry(option_index)
	if is_instance_valid(entry):
		entry.set_hold_progress(progress)

func _on_interaction_option_succeeded(
		interactable: Area3D,
		_interactor: Node3D,
		option_index: int
) -> void:
	if interactable != _interactable_object:
		return
	var entry := get_entry(option_index)
	if is_instance_valid(entry):
		entry.notify_interaction_succeeded()

func _on_entry_action_pressed(option_index: int) -> void:
	if is_instance_valid(_interactable_object):
		entry_action_pressed.emit(_interactable_object, option_index)

func _on_entry_interaction_succeeded(option_index: int) -> void:
	if is_instance_valid(_interactable_object):
		entry_interaction_succeeded.emit(_interactable_object, option_index)

func _disconnect_interaction_ray() -> void:
	if not is_instance_valid(_interaction_ray):
		return
	if _interaction_ray.hold_progress_changed.is_connected(_on_hold_progress_changed):
		_interaction_ray.hold_progress_changed.disconnect(_on_hold_progress_changed)
	if _interaction_ray.interaction_option_succeeded.is_connected(_on_interaction_option_succeeded):
		_interaction_ray.interaction_option_succeeded.disconnect(_on_interaction_option_succeeded)
