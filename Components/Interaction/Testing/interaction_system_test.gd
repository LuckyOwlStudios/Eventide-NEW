extends Node3D

const INTERACTION_RAY_SCRIPT := preload("res://Components/Interaction/interaction_raycast_3d.gd")
const INTERACTABLE_SCRIPT := preload("res://Components/Interaction/interactable_object_3d.gd")
const INTERACTION_OPTION_SCRIPT := preload("res://Components/Interaction/interaction_option.gd")
const INTERACTION_PROMPTER_SCENE := preload("res://Components/UI/Interaction/InteractableObjectPrompter.tscn")

var _failures := 0
var _interaction_count := 0
var _triggered_indices: Array[int] = []


func _ready() -> void:
	_add_test_action(&"test_toggle", _mouse_event(MOUSE_BUTTON_LEFT))
	_add_test_action(&"test_hold", _key_event(KEY_H))
	var default_interactable := Area3D.new()
	default_interactable.set_script(INTERACTABLE_SCRIPT)
	_check(default_interactable.interaction_options.size() == 1, "new interactable starts with one option")
	_check(default_interactable.get_interaction_option(0).input_action == &"interact", "default option uses the interact action")
	_check(default_interactable.get_interaction_option(0).prompt == "Interact", "default option supplies the prompt")
	default_interactable.free()
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	var ray := RayCast3D.new()
	ray.set_script(INTERACTION_RAY_SCRIPT)
	ray.interaction_source = self
	ray.interaction_distance = 3.0
	ray.use_input_action = false
	var prompter := INTERACTION_PROMPTER_SCENE.instantiate() as InteractableObjectPrompter
	ray.interaction_prompter = prompter
	ray.add_child(prompter)
	add_child(ray)

	var interactable := Area3D.new()
	interactable.set_script(INTERACTABLE_SCRIPT)
	interactable.name = "TestInteractable"
	interactable.position = Vector3(0.0, 0.0, -2.0)
	var options: Array[InteractionOption] = [
		_make_option(&"pickup", &"interact", "To Pickup"),
		_make_option(&"toggle", &"test_toggle", "To Toggle"),
		_make_option(&"charge", &"test_hold", "To Charge", INTERACTION_OPTION_SCRIPT.TriggerType.HOLD),
	]
	interactable.interaction_options = options
	interactable.interacted.connect(func(_interactor: Node3D): _interaction_count += 1)
	interactable.interaction_option_interacted.connect(
		func(_interactor: Node3D, option_index: int): _triggered_indices.append(option_index)
	)
	var hover_geometry := MeshInstance3D.new()
	hover_geometry.mesh = BoxMesh.new()
	var hover_overlay := StandardMaterial3D.new()
	var hover_geometries: Array[GeometryInstance3D] = [hover_geometry]
	interactable.hover_geometry_instance = hover_geometries
	interactable.hover_material_overlay = hover_overlay
	add_child(interactable)
	interactable.add_child(hover_geometry)
	interactable.add_child(_make_shape())

	await get_tree().physics_frame
	await get_tree().physics_frame
	ray.force_raycast_update()
	ray._physics_process(0.0)
	_check(ray.get_focused_interactable() == interactable, "ray detects InteractableObject3D Area")
	_check(interactable._hover_overlay_applied, "focused interactable records hover state")
	_check(prompter.option_list.visible, "interaction option list appears while focused")
	_check(prompter.option_list.get_child_count() == 3, "all available interaction options appear together")
	_check(prompter.get_entry(0).key_bind_label.text == "F", "entry includes current input binding")
	_check(prompter.get_entry(0).description_label.text == "TO PICKUP", "entry includes option prompt")
	prompter._update_screen_position()
	_check(prompter.selector.visible, "selector appears for an opted-in interactable")
	_check(prompter.selector.size.x > 0.0 and prompter.selector.size.y > 0.0, "selector encloses a projected 3D box")
	_check(
		is_equal_approx(prompter.selector.size.x, prompter.selector.size.y),
		"equal selector width and height remain square on screen"
	)
	_check(
		prompter.option_list.position.x >= prompter.selector.position.x + prompter.selector.size.x,
		"interaction options appear to the right of the selector"
	)
	var near_selector_width := prompter.selector.size.x
	interactable.position.z = -2.5
	prompter._update_screen_position()
	_check(prompter.selector.size.x < near_selector_width, "selector shrinks as the object moves away")
	interactable.position.z = -2.0
	interactable.show_interaction_selector = false
	prompter._update_screen_position()
	_check(not prompter.selector.visible, "selector can be disabled per interactable")
	interactable.show_interaction_selector = true
	prompter._update_screen_position()
	_check(ray.try_interact(), "interaction succeeds")
	_check(_interaction_count == 1, "interacted signal emitted once")
	_check(_triggered_indices == [0], "interaction callback receives option index")
	_check(ray.get_interaction_source() == self, "configured interaction source is forwarded")
	_check(ray.try_interact_option(1), "specific interaction option succeeds")
	_check(_triggered_indices == [0, 1], "second option reports its own index")
	ray.use_input_action = true
	Input.action_press(&"test_hold")
	ray._physics_process(0.25)
	_check(is_equal_approx(prompter.get_entry(2).hold_progress.value, 0.5), "hold entry displays progress")
	ray._physics_process(0.35)
	Input.action_release(&"test_hold")
	_check(_triggered_indices == [0, 1, 2], "hold option triggers after its duration")
	ray.use_input_action = false

	var blocker := StaticBody3D.new()
	blocker.position = Vector3(0.0, 0.0, -1.0)
	add_child(blocker)
	blocker.add_child(_make_shape())
	await get_tree().physics_frame
	ray.force_raycast_update()
	ray._physics_process(0.0)
	_check(ray.get_focused_interactable() == null, "ordinary physics body blocks interaction")
	_check(hover_geometry.material_overlay == null, "losing focus restores previous geometry overlay")
	_check(not prompter.option_list.visible, "interaction option list hides when blocked")
	_check(not ray.try_interact(), "blocked interaction fails")

	interactable.interaction_options[0].one_shot = true
	blocker.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	ray.force_raycast_update()
	ray._physics_process(0.0)
	_check(ray.try_interact(), "one-shot option succeeds once")
	_check(interactable.interaction_enabled, "one-shot option leaves its object enabled")
	_check(not ray.try_interact_option(0), "used one-shot option cannot repeat")

	print("INTERACTION SYSTEM TESTS: ", "PASS" if _failures == 0 else "FAIL (%s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _make_option(
	id: StringName,
	action: StringName,
	prompt: String,
	type: int = INTERACTION_OPTION_SCRIPT.TriggerType.PRESS
) -> InteractionOption:
	var option := INTERACTION_OPTION_SCRIPT.new()
	option.option_id = id
	option.input_action = action
	option.prompt = prompt
	option.trigger_type = type
	option.hold_duration_seconds = 0.5
	return option


func _add_test_action(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)


func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event


func _make_shape() -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	collision.shape = shape
	return collision


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("INTERACTION TEST FAILED: " + message)
