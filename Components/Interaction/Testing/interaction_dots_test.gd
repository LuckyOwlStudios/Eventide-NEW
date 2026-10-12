extends Node
## Checks the dots shown on interactables that are in reach but not being looked at. Each interactable
## owns its dot; the prompter of the player in reach only says which of them may show it.
##
## godot --headless --fixed-fps 60 --path . res://Components/Interaction/Testing/InteractionDotsTest.tscn

const PROMPTER_SCENE := preload("res://Components/UI/Interaction/InteractableObjectPrompter.tscn")

var _failures := 0
var _world: Node3D
var _prompter: InteractableObjectPrompter
var _camera: Camera3D


func _ready() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	var player := Node3D.new()
	_world.add_child(player)
	var camera := Camera3D.new()
	_camera = camera
	player.add_child(camera)
	camera.current = true
	var ray := InteractionRayCast3D.new()
	ray.interaction_source = player
	_prompter = PROMPTER_SCENE.instantiate() as InteractableObjectPrompter
	ray.interaction_prompter = _prompter
	ray.add_child(_prompter)
	player.add_child(ray)
	await _frames(2)

	# Offset sideways: an object dead ahead is the one the ray looks at, and gets the full interface.
	var near := _interactable(Vector3(2.0, 0.0, -2.0))
	var middle := _interactable(Vector3(-2.0, 0.0, -6.0))
	var far := _interactable(Vector3(3.0, 0.0, -12.0))
	await _frames(3)

	print("Every interactable carries its own dot")
	_check(near.get_dot() != null and near.get_dot().get_parent() == near, "the dot is a child of the interactable")
	_check(not near.get_children().has(near.get_dot()), "kept out of the way of code that walks the children")
	_check(near.get_dot().mesh.material != middle.get_dot().mesh.material, "each with a material of its own")
	_check(near.get_dot().position.is_zero_approx(), "sitting at the middle of the selector box")
	near.selector_local_offset = Vector3(0.0, 0.5, 0.0)
	_check(near.get_dot().position.is_equal_approx(Vector3(0.0, 0.5, 0.0)), "and following it when that moves")
	near.selector_local_offset = Vector3.ZERO

	print("Dots show within reach")
	_check(_dot_shown(near) and _dot_shown(middle), "usable objects within the distance have a dot")
	_check(not _dot_shown(far), "one beyond the distance does not")

	print("The distance is the material's fade distance")
	var material := near.get_dot().mesh.material as BaseMaterial3D
	_check(is_equal_approx(material.distance_fade_min_distance, 8.0), "the default Dot Distance is on the material")
	_check(material.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA, "which fades the dot out with distance")
	near.dot_distance = 12.0
	_check(is_equal_approx(material.distance_fade_min_distance, 12.0), "changing it changes the material")
	_check(is_equal_approx((middle.get_dot().mesh.material as BaseMaterial3D).distance_fade_min_distance, 8.0), "and no other object's")
	near.dot_distance = 8.0
	far.dot_distance = 20.0
	await _frames(2)
	_check(_dot_shown(far), "a bigger Dot Distance shows a farther dot")
	near.dot_distance = 1.5
	await _frames(2)
	_check(not _dot_shown(near), "and a smaller one hides a nearer one")
	near.dot_distance = 8.0
	far.dot_distance = 8.0

	print("Looking at one swaps its dot for the full interface")
	var target := _interactable(Vector3(0.0, 0.0, -2.5))
	await _frames(4)
	_check(_prompter.is_showing_prompt() and _prompter.option_list.visible, "looking straight at an object shows its options")
	_check(not target.get_dot().visible, "and its dot goes")
	_check(_dot_shown(near) and _dot_shown(middle), "while the others keep theirs")
	target.position.x = 4.0
	await _frames(4)
	_check(not _prompter.is_showing_prompt(), "looking away hides the options")
	_check(_dot_shown(target), "and gives it its dot back")
	target.free()

	print("Dots are left off where they should not show")
	near.show_distance_dot = false
	await _frames(2)
	_check(not _dot_shown(near), "an object with its dot turned off")
	near.show_distance_dot = true
	near.interaction_enabled = false
	await _frames(2)
	_check(not _dot_shown(near), "a disabled object")
	near.interaction_enabled = true
	near.interaction_options[0].enabled = false
	await _frames(2)
	_check(not _dot_shown(near), "an object with nothing available to do")
	near.interaction_options[0].enabled = true

	var behind := _interactable(Vector3(0.0, 0.0, 3.0))
	await _frames(2)
	_check(not _dot_shown(behind), "an object behind the camera")
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(10.0, 10.0, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.0, 0.0, -4.0)
	_world.add_child(wall)
	await _frames(3)
	_check(not _dot_shown(middle) and not _dot_shown(far), "objects hidden behind a wall (the dot is drawn over everything, so this is checked)")
	_check(_dot_shown(near), "while the one in front of it still shows")
	var stuck_on_wall := _interactable(Vector3(2.0, 0.0, -3.9))
	await _frames(3)
	_check(_dot_shown(stuck_on_wall), "and a button fixed to the wall itself is not hidden by it")
	wall.free()

	print("Dots follow the player who owns them")
	var other_ray := InteractionRayCast3D.new()
	other_ray.interaction_source = player
	other_ray.set_multiplayer_authority(2)
	var other_prompter := PROMPTER_SCENE.instantiate() as InteractableObjectPrompter
	other_ray.interaction_prompter = other_prompter
	other_ray.add_child(other_prompter)
	player.add_child(other_ray)
	await _frames(3)
	_check(_dot_shown(near), "another player's prompter does not switch them off")
	other_ray.free()
	ray.interaction_enabled = false
	await _frames(2)
	_check(not _dot_shown(near) and not _dot_shown(middle), "no dots while interaction is off (sitting in a vehicle, say)")
	ray.interaction_enabled = true
	_prompter.dots_enabled = false
	await _frames(2)
	_check(not _dot_shown(near) and not _dot_shown(middle), "or when the prompter's dots are turned off")
	_prompter.dots_enabled = true
	await _frames(2)
	_check(_dot_shown(near), "and they come back")

	_world.free()
	if _failures == 0:
		print("Interaction dot tests passed.")
	else:
		print("Interaction dot tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _interactable(at: Vector3) -> InteractableObject3D:
	var interactable := InteractableObject3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	interactable.add_child(shape)
	interactable.position = at
	_world.add_child(interactable)
	return interactable


func _dot_shown(interactable: InteractableObject3D) -> bool:
	return interactable.get_dot().visible


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
