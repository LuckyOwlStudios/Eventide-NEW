## Reusable interaction detector that points along its local -Z axis.
## It reads every available InteractionOption from the focused object, handles
## press/double-press/hold input, and updates the attached option prompter.
class_name InteractionRayCast3D
extends RayCast3D

const INTERACTABLE_OBJECT_SCRIPT := preload("res://Components/Interaction/interactable_object_3d.gd")
const INTERACTION_OPTION_SCRIPT := preload("res://Components/Interaction/interaction_option.gd")

signal focused_interactable_changed(previous: Area3D, current: Area3D)
signal interaction_requested(interactable: Area3D, interactor: Node3D)
signal interaction_succeeded(interactable: Area3D, interactor: Node3D)
signal interaction_failed(interactable: Area3D, interactor: Node3D)
signal interaction_option_requested(interactable: Area3D, interactor: Node3D, option_index: int)
signal interaction_option_succeeded(interactable: Area3D, interactor: Node3D, option_index: int)
signal hold_progress_changed(interactable: Area3D, option_index: int, progress: float)

@export_category("Interaction")
## Master switch for detection, prompts, and interaction input.
@export var interaction_enabled := true:
	set(value):
		interaction_enabled = value
		enabled = value
		if not interaction_enabled:
			_set_focused_interactable(null)

## Maximum reach of the interaction ray in meters.
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m") var interaction_distance := 3.0:
	set(value):
		interaction_distance = maxf(value, 0.1)
		target_position = Vector3(0.0, 0.0, -interaction_distance)

## Handles each InteractionOption's Input Map action automatically. Disable this
## when another controller will call try_interact_option() manually.
@export var use_input_action := true

## Prevents replicated copies belonging to other peers from reading local input.
@export var input_requires_multiplayer_authority := true

## Marks a successful interaction input as handled.
@export var consume_successful_input := true

@export_category("Interactor")
## Actor passed to can_interact and interact callbacks.
@export var interaction_source: Node3D

## Screen-space list that displays every currently available interaction.
@export var interaction_prompter: InteractableObjectPrompter

@export_category("Runtime Diagnostics (read only)")
## Live description of the focused object and displayed option.
@export_multiline var runtime_status := "Start the game to inspect interaction targeting."

var _focused_interactable: Area3D
var _available_option_indices: Array[int] = []
var _hold_elapsed: Dictionary = {}
var _hold_completed: Dictionary = {}
var _last_press_time_msec: Dictionary = {}


func _enter_tree() -> void:
	# By default it looks at interactables and at the solid things that can hide them. A
	# mask a scene set to something other than Godot's stock value of 1 is left alone.
	if collision_mask == 1:
		collision_mask = PhysicsLayers.INTERACTION_RAY_MASK


func _ready() -> void:
	target_position = Vector3(0.0, 0.0, -interaction_distance)
	collide_with_areas = true
	enabled = interaction_enabled
	if not is_instance_valid(interaction_prompter):
		for child in get_children():
			if child is InteractableObjectPrompter:
				interaction_prompter = child
				break
	if is_instance_valid(interaction_prompter):
		interaction_prompter.bind_to_interaction_ray(self)
		interaction_prompter.clear()
	else:
		push_warning("[InteractionRayCast3D] Assign an InteractableObjectPrompter.")
	_update_focus()
	_refresh_available_options(0.0)
	_update_interaction_prompter()


func _exit_tree() -> void:
	_set_focused_interactable(null)


func _physics_process(delta: float) -> void:
	if input_requires_multiplayer_authority and not is_multiplayer_authority():
		_set_focused_interactable(null)
		_update_interaction_prompter()
		return
	_update_focus()
	_refresh_available_options(delta)
	if use_input_action:
		_process_hold_options(delta)
	_update_interaction_prompter()
	_update_runtime_status()


func _unhandled_input(event: InputEvent) -> void:
	if not interaction_enabled or not use_input_action:
		return
	if input_requires_multiplayer_authority and not is_multiplayer_authority():
		return
	if event is InputEventKey and event.echo:
		return
	# The focused object can be freed (picked up, say) before the next physics frame notices.
	if not is_instance_valid(_focused_interactable):
		return
	var succeeded := false
	for option_index in _available_option_indices:
		var option: Resource = _focused_interactable.get_interaction_option(option_index)
		if option == null or int(option.trigger_type) == INTERACTION_OPTION_SCRIPT.TriggerType.HOLD:
			continue
		if not event.is_action_pressed(StringName(option.input_action)):
			continue
		if int(option.trigger_type) == INTERACTION_OPTION_SCRIPT.TriggerType.DOUBLE_PRESS:
			if _register_double_press(option_index, float(option.double_press_window_seconds)):
				succeeded = try_interact_option(option_index) or succeeded
		else:
			succeeded = try_interact_option(option_index) or succeeded
	if succeeded and consume_successful_input:
		get_viewport().set_input_as_handled()


## Uses the first available option. Useful for generic controller integrations.
func try_interact() -> bool:
	if _available_option_indices.is_empty():
		interaction_failed.emit(_focused_interactable, get_interaction_source())
		return false
	return try_interact_option(_available_option_indices[0])


## Attempts one exported Interaction Options array index directly.
func try_interact_option(option_index: int) -> bool:
	if not interaction_enabled:
		interaction_failed.emit(null, get_interaction_source())
		return false
	force_raycast_update()
	_update_focus()
	_refresh_available_options(0.0)
	var interactor := get_interaction_source()
	var target := _focused_interactable
	if (
		not is_instance_valid(target)
		or option_index not in _available_option_indices
		or not target.can_interact(interactor, option_index)
	):
		interaction_failed.emit(target, interactor)
		return false
	interaction_requested.emit(target, interactor)
	interaction_option_requested.emit(target, interactor, option_index)
	if not target.interact_at(interactor, get_collision_point(), option_index):
		interaction_failed.emit(target, interactor)
		return false
	interaction_succeeded.emit(target, interactor)
	interaction_option_succeeded.emit(target, interactor, option_index)
	_refresh_available_options(0.0)
	return true


func get_focused_interactable() -> Area3D:
	return _focused_interactable if is_instance_valid(_focused_interactable) else null


func get_displayed_option_index() -> int:
	if _available_option_indices.is_empty():
		return -1
	return _available_option_indices[0]


func get_available_option_indices() -> Array[int]:
	return _available_option_indices.duplicate()


func get_interaction_source() -> Node3D:
	if is_instance_valid(interaction_source):
		return interaction_source
	return get_parent() as Node3D


func _update_focus() -> void:
	var next: Area3D
	if interaction_enabled and is_colliding():
		next = _interactable_from_collider(get_collider())
		if is_instance_valid(next):
			var options: Array[int] = next.get_available_interaction_indices(get_interaction_source())
			if options.is_empty():
				next = null
	_set_focused_interactable(next)


func _interactable_from_collider(collider: Object) -> Area3D:
	if collider is INTERACTABLE_OBJECT_SCRIPT:
		return collider
	if collider is Area3D and collider.has_meta(INTERACTABLE_OBJECT_SCRIPT.INTERACTION_TARGET_META):
		var mapped_target: Variant = collider.get_meta(
			INTERACTABLE_OBJECT_SCRIPT.INTERACTION_TARGET_META
		)
		if is_instance_valid(mapped_target) and mapped_target is INTERACTABLE_OBJECT_SCRIPT:
			return mapped_target
	return null


func _set_focused_interactable(value: Area3D) -> void:
	if _focused_interactable == value:
		return
	var previous := _focused_interactable
	if is_instance_valid(previous):
		previous.set_interaction_hovered(self, false)
	_focused_interactable = value
	if is_instance_valid(_focused_interactable):
		_focused_interactable.set_interaction_hovered(self, true)
	_available_option_indices.clear()
	_reset_input_state()
	focused_interactable_changed.emit(previous, _focused_interactable)
	_update_interaction_prompter()


func _refresh_available_options(delta: float) -> void:
	if not is_instance_valid(_focused_interactable):
		_available_option_indices.clear()
		return
	var updated: Array[int] = _focused_interactable.get_available_interaction_indices(get_interaction_source())
	if updated != _available_option_indices:
		_available_option_indices = updated
		_update_interaction_prompter()


func _process_hold_options(delta: float) -> void:
	if not is_instance_valid(_focused_interactable):
		_reset_hold_state()
		return
	for option_index in _available_option_indices:
		var option: Resource = _focused_interactable.get_interaction_option(option_index)
		if option == null or int(option.trigger_type) != INTERACTION_OPTION_SCRIPT.TriggerType.HOLD:
			continue
		var action := StringName(option.input_action)
		if Input.is_action_pressed(action):
			if bool(_hold_completed.get(option_index, false)):
				continue
			var elapsed := float(_hold_elapsed.get(option_index, 0.0)) + delta
			_hold_elapsed[option_index] = elapsed
			var duration := maxf(float(option.hold_duration_seconds), 0.1)
			var progress := clampf(elapsed / duration, 0.0, 1.0)
			hold_progress_changed.emit(_focused_interactable, option_index, progress)
			if progress >= 1.0:
				_hold_completed[option_index] = true
				try_interact_option(option_index)
		else:
			if _hold_elapsed.has(option_index):
				hold_progress_changed.emit(_focused_interactable, option_index, 0.0)
			_hold_elapsed.erase(option_index)
			_hold_completed.erase(option_index)


func _register_double_press(option_index: int, window_seconds: float) -> bool:
	var now := Time.get_ticks_msec()
	var previous := int(_last_press_time_msec.get(option_index, -1))
	_last_press_time_msec[option_index] = now
	if previous < 0 or now - previous > roundi(maxf(window_seconds, 0.1) * 1000.0):
		return false
	_last_press_time_msec.erase(option_index)
	return true


func _reset_input_state() -> void:
	_last_press_time_msec.clear()
	_reset_hold_state()


func _reset_hold_state() -> void:
	_hold_elapsed.clear()
	_hold_completed.clear()


func _update_interaction_prompter() -> void:
	if not is_inside_tree() or not is_instance_valid(interaction_prompter):
		return
	if not interaction_enabled or not is_instance_valid(_focused_interactable):
		interaction_prompter.clear()
		return
	interaction_prompter.display_options(
		_focused_interactable as InteractableObject3D,
		_available_option_indices
	)


func _update_runtime_status() -> void:
	if not interaction_enabled:
		runtime_status = "Interaction disabled."
	elif is_instance_valid(_focused_interactable):
		var distance := global_position.distance_to(get_collision_point())
		runtime_status = "Target: %s\nOption: %s\nAvailable: %s\nDistance: %.2f m" % [
			_focused_interactable.name,
			get_displayed_option_index(),
			_available_option_indices.size(),
			distance,
		]
	elif is_colliding():
		runtime_status = "Blocked by non-interactable: %s" % get_collider()
	else:
		runtime_status = "No interactable in range."
