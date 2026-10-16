extends Node
## Drives the real Player scene through Input Map actions to check the wiring:
## the controller -> the character's speed, stamina, the head and the Rotator.
##
## godot --headless --fixed-fps 60 --path . res://Components/Movement/Testing/PlayerSceneTest.tscn

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

var physics_frame: Signal
var _failures := 0
var _world: Node3D


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300.0, 200.0, 300.0)
	field_shape.shape = field_box
	field_shape.position = Vector3(0.0, 80.0, 0.0)
	field.add_child(field_shape)
	_world.add_child(field)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector3(0.0, 0.05, 0.0)
	_world.add_child(player)
	var controller := player.get_node("PlayerCharacterController") as CharacterController
	var stamina := player.get_node("StaminaAttribute") as Stamina
	var head := player.get_node("Head") as Node3D
	await _ticks(40)

	_check(controller.is_grounded(), "the player settles on the ground")
	_check(controller.net_sync != null, "the controller found its net sync")
	_check(not controller.is_physics_processing(), "the net sync drives the controller, not the controller itself")
	_check(controller.get_body() == player and player.movement_speed.value == 5.0, "the controller moves the player, whose speed attribute is 5 (%.1f)" % player.movement_speed.value)

	var start := player.global_position
	Input.action_press("move_forward")
	await _ticks(60)
	var walked := start.distance_to(player.global_position)
	_check(walked > 4.3 and walked < 5.2, "holding forward walks about 5 m in a second (%.2f)" % walked)

	var before := stamina.stamina
	Input.action_press("sprint")
	await _ticks(60)
	_check(before - stamina.stamina > 10.0, "sprinting spends stamina (%.1f -> %.1f)" % [before, stamina.stamina])
	_check(controller.is_sprinting(), "and is reported as sprinting")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _ticks(20)

	var jump_event := InputEventAction.new()
	jump_event.action = &"jump"
	jump_event.pressed = true
	Input.parse_input_event(jump_event)
	Input.action_press("jump")
	var peak := 0.0
	for tick in 60:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		if tick == 2:
			Input.action_release("jump")
	_check(peak > 0.8 and peak < 1.2, "pressing jump jumps about a meter (%.2f)" % peak)

	Input.action_press("crouch")
	await _ticks(45)
	_check(controller.is_crouching(), "holding crouch crouches")
	_check(head.position.y < 0.8, "and the head drops (%.2f)" % head.position.y)
	Input.action_release("crouch")
	await _ticks(45)
	_check(not controller.is_crouching(), "releasing crouch stands up")
	_check(head.position.y > 1.5, "and the head comes back (%.2f)" % head.position.y)

	controller.movement_blocker.add(5, "test lock")
	var locked_at := player.global_position
	Input.action_press("move_forward")
	await _ticks(30)
	_check(player.global_position.distance_to(locked_at) < 0.01, "a locked player stays put")
	controller.movement_blocker.remove(5)
	await _ticks(30)
	_check(player.global_position.distance_to(locked_at) > 1.0, "and moves again once unlocked")
	Input.action_release("move_forward")

	if _failures == 0:
		print("Player scene tests passed.")
	else:
		print("Player scene tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
