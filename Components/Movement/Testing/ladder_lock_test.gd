extends Node
## Checks that mounting a ladder locks the new CharacterController and that leaving it
## hands control back.
##
## godot --headless --fixed-fps 60 --path . res://Components/Movement/Testing/LadderLockTest.tscn

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

var physics_frame: Signal
var _failures := 0


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300.0, 200.0, 300.0)
	field_shape.shape = field_box
	field_shape.position = Vector3(0.0, 80.0, 0.0)
	field.add_child(field_shape)
	world.add_child(field)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	world.add_child(floor_body)

	var ladder := Ladder3D.new()
	ladder.height = 4.0
	ladder.position = Vector3(0.0, 0.0, -3.0)
	world.add_child(ladder)

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.05, 0.0)
	world.add_child(player)
	var controller := player.get_node("PlayerCharacterController") as CharacterController
	var climber := player.get_node("LadderController") as LadderController
	await _ticks(30)

	_check(climber.mount(ladder, 0.0), "mounting the ladder works")
	await _ticks(40)
	_check(climber.is_climbing(), "the climber is on the ladder")
	_check(not controller.is_movement_permitted(), "the controller is locked while on the ladder")

	Input.action_press("move_forward")
	await _ticks(30)
	Input.action_release("move_forward")
	_check(climber.get_climb_height() > ladder.climb_speed * 0.4, "forward climbs (%.2f m)" % climber.get_climb_height())
	_check(player.global_position.y > ladder.climb_speed * 0.4, "and the body rides up with it (y=%.2f)" % player.global_position.y)
	_check(absf(player.global_position.z + 3.0 - ladder.climb_offset) < 0.05, "while staying on the ladder (z=%.2f)" % player.global_position.z)

	climber.jump_off()
	await _ticks(2)
	_check(controller.is_movement_permitted(), "jumping off unlocks the controller")
	await _ticks(90)
	_check(controller.is_grounded(), "and the player lands again")
	var landed_at := player.global_position
	Input.action_press("move_back")
	await _ticks(30)
	Input.action_release("move_back")
	_check(player.global_position.distance_to(landed_at) > 1.5, "and can walk (%.2f m)" % player.global_position.distance_to(landed_at))

	if _failures == 0:
		print("Ladder lock tests passed.")
	else:
		print("Ladder lock tests FAILED: %d check(s)." % _failures)
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
