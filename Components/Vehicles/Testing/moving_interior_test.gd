extends Node
## Checks that people, loose items and vehicles inside the Mule stay put in it while it flies, turns
## and tumbles, and keep their momentum when they leave.
##
## godot --headless --fixed-fps 60 --path . res://Components/Vehicles/Testing/MovingInteriorTest.tscn

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

var _failures := 0
var _world: Node3D
var _mule: Mule
var _player: CharacterBody3D
var _crate: RigidBody3D
var _car: Vehicle3D

## Where each thing is in the ship, while a stretch is being watched, and how far it strayed.
var _watching := false
var _places: Dictionary = {}
var _worst: Dictionary = {}


func _ready() -> void:
	_run()


func _physics_process(_delta: float) -> void:
	if not _watching:
		return
	for body: Node3D in _places:
		_worst[body] = maxf(_worst[body], _local(body).distance_to(_places[body]))


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	InGameUIHandler.is_ui_open = false

	_mule = MULE_SCENE.instantiate() as Mule
	_world.add_child(_mule)
	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	_player.position = Vector3(0.0, 0.1, 1.5)
	_world.add_child(_player)
	_crate = _make_crate(Vector3(0.8, 0.4, 0.0))
	_car = _make_car(Vector3(-1.2, 0.5, 3.6))
	await _frames(120)
	var interior := _mule.get_node("Area") as VehicleInterior3D
	_check(interior != null, "the Mule's inside is a VehicleInterior3D")
	var occupants := interior.get_occupants()
	_check(occupants.has(_player) and occupants.has(_crate) and occupants.has(_car), "it has the player, the crate and the car (%d things)" % occupants.size())
	_check(_player.is_on_floor(), "the player stands on the floor of the bay")

	print("Flying straight and turning")
	_mule.linear_velocity = Vector3(5.0, 0.0, 3.0)
	_mule.angular_velocity = Vector3(0.0, 0.4, 0.0)
	_watch()
	await _frames(300)
	_check(_mule.global_position.length() > 10.0, "the ship went somewhere (%.1f m)" % _mule.global_position.length())
	_report("while flying and turning", 0.04)

	print("Pressed against the wall while the ship strafes, with a crate right in its way")
	_player.global_position = _mule.to_global(Vector3(1.5, 0.1, 0.0))
	await _frames(30)
	# The crate goes flat against the player on the side the ship is heading, so a player that is
	# carried like something moving at the ship's speed would knock it away.
	var against := _local(_player) + Vector3(-0.35 - 0.3 - 0.015, 0.0, 0.0)
	_crate.global_transform = _mule.global_transform * Transform3D(Basis.IDENTITY, Vector3(against.x, 0.31, against.z))
	_crate.linear_velocity = Vector3.ZERO
	_crate.angular_velocity = Vector3.ZERO
	await _frames(30)
	_mule.linear_velocity = Vector3(-8.0, 0.0, 0.0)
	_mule.angular_velocity = Vector3.ZERO
	_watch()
	await _frames(180)
	_report("against a wall", 0.04)
	_check(_worst[_crate] < 0.005, "and the crate in the way is not shoved at all (%.2f cm)" % (_worst[_crate] * 100.0))

	print("Tumbling")
	_mule.angular_velocity = Vector3(0.3, 0.2, 0.25)
	_watch()
	await _frames(300)
	_report("while tumbling", 0.10)
	_check(_player.is_on_floor(), "the player still stands on the floor")

	print("Walking about inside")
	_crate.global_transform = _mule.global_transform * Transform3D(Basis.IDENTITY, Vector3(1.4, 0.31, 5.0))
	_crate.linear_velocity = Vector3.ZERO
	_crate.angular_velocity = Vector3.ZERO
	_mule.linear_velocity = Vector3.ZERO
	_mule.angular_velocity = Vector3.ZERO
	# Upright again after the tumble, with the player facing along the ship.
	_mule.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 50.0, 0.0))
	await _frames(20)
	_player.global_basis = _mule.global_basis
	var start := Vector3(0.0, 0.1, 1.5)
	_player.global_position = _mule.to_global(start)
	await _frames(40)
	var begin := _local(_player)
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	var still_walk := _local(_player) - begin
	_mule.linear_velocity = Vector3(5.0, 1.0, 3.0)
	_mule.angular_velocity = Vector3(0.0, 0.4, 0.0)
	_player.global_position = _mule.to_global(start)
	await _frames(40)
	begin = _local(_player)
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	var moving_walk := _local(_player) - begin
	_check(still_walk.length() > 1.0, "someone walking in a ship at rest covers ground (%.2f m)" % still_walk.length())
	_check(moving_walk.distance_to(still_walk) < still_walk.length() * 0.15, "and in one that flies and turns they go the same way just as far (%.2f m against %.2f m)" % [moving_walk.length(), still_walk.length()])

	print("Sitting down and getting up in a moving ship")
	_mule.linear_velocity = Vector3(6.0, 0.0, 2.0)
	_mule.angular_velocity = Vector3(0.0, 0.2, 0.0)
	var seat := _mule.find_child("PilotSeat", true, false) as VehicleSeat3D
	var pilot := _player.get_node("VehicleController") as VehicleController
	_player.global_position = seat.get_dismount_transform().origin
	await _frames(40)
	_check(pilot.enter_seat(seat), "the player can sit in the pilot seat while the ship flies")
	await _frames(60)
	_check(_player.global_position.distance_to(seat.get_seat_transform().origin) < 0.1, "and stays in it")
	_check(pilot.exit_seat(), "and get up again")
	await _frames(40)
	_check(_player.velocity.length() < 3.0, "without being flung (moving %.2f m/s against the ship)" % _player.velocity.length())
	_check(_local(_player).distance_to(_mule.to_local(seat.get_dismount_transform().origin)) < 1.0, "or left behind (%.2f m from where they got off)" % _local(_player).distance_to(_mule.to_local(seat.get_dismount_transform().origin)))

	print("Momentum across the doorway")
	_watching = false
	_mule.angular_velocity = Vector3.ZERO
	_mule.linear_velocity = Vector3(5.0, 0.0, 0.0)
	await _frames(5)
	_crate.global_position = _mule.to_global(Vector3(0.0, 10.0, 0.0))
	await _frames(6)
	_check(_crate.linear_velocity.distance_to(Vector3(5.0, 0.0, 0.0)) < 0.5, "a crate that leaves the ship keeps the ship's speed (%s)" % _crate.linear_velocity.snapped(Vector3.ONE * 0.01))
	_crate.linear_velocity = Vector3(5.0, 0.0, 0.0)
	_crate.global_position = _mule.to_global(Vector3(0.0, 1.0, 1.0))
	await _frames(6)
	_check(absf(_crate.linear_velocity.x) < 1.0, "and one that comes in is measured against it (%s)" % _crate.linear_velocity.snapped(Vector3.ONE * 0.01))

	print("Without the carry, as a check that this test can fail")
	_mule.angular_velocity = Vector3(0.0, 0.4, 0.0)
	_mule.linear_velocity = Vector3(-8.0, 0.0, 0.0)
	_player.global_position = _mule.to_global(Vector3(1.5, 0.1, 0.0))
	await _frames(30)
	interior.set_physics_process(false)
	_watch()
	await _frames(120)
	_watching = false
	_check(_worst[_player] > 0.2, "left uncarried, the player is thrown around (%.0f cm)" % (_worst[_player] * 100.0))
	interior.set_physics_process(true)

	_world.free()
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Moving interior tests passed.")
	else:
		print("Moving interior tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Starts watching how far the player, the crate and the car stray from where they are now in the ship.
func _watch() -> void:
	_places = {_player: _local(_player), _crate: _local(_crate), _car: _local(_car)}
	_worst = {_player: 0.0, _crate: 0.0, _car: 0.0}
	_watching = true


func _report(label: String, allowed: float) -> void:
	_watching = false
	for body: Node3D in _worst:
		_check(_worst[body] < allowed, "the %s stays within %.0f cm of its place in the ship %s (worst %.1f cm)" % [body.name if body != _crate and body != _car else ("crate" if body == _crate else "car"), allowed * 100.0, label, _worst[body] * 100.0])


func _local(body: Node3D) -> Vector3:
	return _mule.global_transform.affine_inverse() * body.global_position


func _make_crate(at: Vector3) -> RigidBody3D:
	var crate := RigidBody3D.new()
	crate.collision_layer = PhysicsLayers.ITEMS
	crate.collision_mask = PhysicsLayers.ITEM_MASK
	crate.mass = 20.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	crate.add_child(shape)
	_world.add_child(crate)
	crate.global_position = _mule.to_global(at)
	return crate


func _make_car(at: Vector3) -> Vehicle3D:
	var car := Vehicle3D.new()
	car.mass = 800.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.8, 2.4)
	shape.shape = box
	car.add_child(shape)
	_world.add_child(car)
	car.global_position = _mule.to_global(at)
	return car


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
