extends Node
## Checks what a jump takes along and what it deletes, with the real Mule, the real Player and the
## things a level has lying about: items, a car, a creature, scenery, asteroids.
##
## godot --headless --fixed-fps 60 --path . res://Components/Jump/Testing/JumpPurgeTest.tscn

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const BATTERY := preload("res://Game/Registry/Items/Battery/battery_item.tres")

var _failures := 0
var _world: Node3D
var _mule: Mule
var _interiors: Array[VehicleInterior3D]


func _ready() -> void:
	_run()


func _run() -> void:
	InGameUIHandler.is_ui_open = false
	_world = Node3D.new()
	add_child(_world)
	_mule = MULE_SCENE.instantiate() as Mule
	_world.add_child(_mule)
	await _frames(5)
	_interiors = JumpPurge.get_interiors(_mule)

	await _test_containment()
	await _test_rules()
	await _test_recall()
	await _test_groups()

	_world.free()
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Jump purge tests passed.")
	else:
		print("Jump purge tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Is a point inside the ship? -------------------------------------------------------

func _test_containment() -> void:
	print("Inside the ship")
	_check(_interiors.size() == 1, "the Mule has one interior")
	var interior := _interiors[0]
	_check(interior.contains_point(_mule.to_global(Vector3(0.0, 1.0, 0.0))), "the middle of the hold is inside")
	_check(interior.contains_point(_mule.to_global(Vector3(1.9, 0.1, 7.5))), "so is a corner of it")
	_check(not interior.contains_point(_mule.to_global(Vector3(0.0, 1.0, 9.0))), "a point beyond its end is not")
	_check(not interior.contains_point(_mule.to_global(Vector3(0.0, 4.0, 0.0))), "nor one above it")
	_check(not interior.contains_point(_mule.to_global(Vector3(30.0, 1.0, 0.0))), "nor one far off to the side")
	_mule.global_transform = Transform3D(Basis(Vector3.UP, 1.0).rotated(Vector3.RIGHT, 0.6), Vector3(500.0, -300.0, 70.0))
	await _frames(2)
	_check(interior.contains_point(_mule.to_global(Vector3(0.5, 1.0, 3.0))) and not interior.contains_point(_mule.to_global(Vector3(0.0, 1.0, 12.0))), "wherever the ship is and however it is turned")
	_mule.global_transform = Transform3D.IDENTITY
	await _frames(2)
	# The other shapes.
	var area := VehicleInterior3D.new()
	var holder := Node3D.new()
	_world.add_child(holder)
	holder.add_child(area)
	holder.position = Vector3(100.0, 0.0, 0.0)
	var shapes: Array[Shape3D] = []
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.0
	capsule.height = 4.0
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.5
	cylinder.height = 3.0
	shapes.append_array([sphere, capsule, cylinder])
	var answers: Array[bool] = []
	for shape in shapes:
		var node := CollisionShape3D.new()
		node.shape = shape
		area.add_child(node)
		answers.append(area.contains_point(Vector3(100.0, 0.0, 0.0)))
		answers.append(area.contains_point(Vector3(100.0, 1.9, 0.0)) if shape is CapsuleShape3D else area.contains_point(Vector3(101.0, 0.0, 0.0)))
		answers.append(not area.contains_point(Vector3(100.0, 5.0, 0.0)))
		node.free()
	_check(not answers.has(false), "spheres, capsules and cylinders are measured exactly (%s)" % str(answers))
	holder.free()


# --- What goes, what stays ----------------------------------------------------------------

func _test_rules() -> void:
	print("What a jump keeps and what it deletes")
	var streamer := ChunkStreamer.new()
	_world.add_child(streamer)
	streamer.track(_mule)
	streamer.begin_system(StarSystem.create(5, 0, SystemTuning.new(), _mule.global_position))
	streamer.load_all_now()
	_check(streamer.get_asteroid_count() > 100, "there is an asteroid field around (%d)" % streamer.get_asteroid_count())

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector3(0.0, 0.1, 1.5)
	_world.add_child(player)
	var out_player := PLAYER_SCENE.instantiate() as Player
	out_player.position = Vector3(300.0, 5.0, 0.0)
	_world.add_child(out_player)

	var crate_in := _make_crate(_mule.to_global(Vector3(0.8, 0.4, 2.0)))
	var crate_out := _make_crate(Vector3(200.0, 0.0, 50.0))
	var crate_far := _make_crate(Vector3(-4000.0, 10.0, 0.0))
	var car_in := _make_car(_mule.to_global(Vector3(-1.2, 0.5, 3.6)))
	var car_out := _make_car(Vector3(0.0, 0.0, 400.0))
	var creature_in := _make_creature(_mule.to_global(Vector3(1.0, 0.1, -3.0)))
	var creature_out := _make_creature(Vector3(-150.0, 0.0, 0.0))
	var item_in := BATTERY.spawn_in_world(BATTERY.create_instance(), _world, Transform3D(Basis.IDENTITY, _mule.to_global(Vector3(-1.0, 0.4, -2.0))))
	var item_out := BATTERY.spawn_in_world(BATTERY.create_instance(), _world, Transform3D(Basis.IDENTITY, Vector3(80.0, 0.0, 80.0)))
	var scenery := CSGBox3D.new()
	scenery.add_to_group(JumpPurge.PURGE_GROUP)
	_world.add_child(scenery)
	scenery.global_position = Vector3(40.0, 0.0, 40.0)
	var plain := Node3D.new()
	var plain_child := MeshInstance3D.new()
	plain.add_child(plain_child)
	_world.add_child(plain)
	plain.global_position = Vector3(10.0, 0.0, 10.0)
	# Something belonging to a car that is inside the ship, and something the ship itself carries.
	var cargo_on_car := _make_crate(Vector3.ZERO)
	_world.remove_child(cargo_on_car)
	car_in.add_child(cargo_on_car)
	var on_hull := _make_crate(Vector3.ZERO)
	_world.remove_child(on_hull)
	_mule.add_child(on_hull)
	on_hull.position = Vector3(0.0, 40.0, 0.0)
	await _frames(30)

	# A held item and a carried one belong to the player and stay with them.
	var holder := player.find_child("ItemHolder", true, false) as ItemHolder
	_check(holder != null, "the Player has an item holder")
	var held_before := player.find_children("*", "ItemActor", true, false).size()

	var interiors := _interiors
	_check(JumpPurge.stays(_mule, _mule, interiors) and JumpPurge.stays(player, _mule, interiors), "the ship and a player always stay")
	_check(JumpPurge.stays(crate_in, _mule, interiors) and not JumpPurge.stays(crate_out, _mule, interiors), "a crate inside stays and one outside does not")
	_check(JumpPurge.is_purgeable(crate_out) and JumpPurge.is_purgeable(car_out) and JumpPurge.is_purgeable(creature_out) and JumpPurge.is_purgeable(item_out) and JumpPurge.is_purgeable(scenery), "items, vehicles, creatures, tagged scenery and loose item actors are the kinds that can be deleted")
	_check(not JumpPurge.is_purgeable(plain) and not JumpPurge.is_purgeable(player) and not JumpPurge.is_purgeable(streamer), "ordinary nodes, players and the streamer are not")

	var report := JumpPurge.purge(_world, _mule, streamer)
	await _frames(3)
	print("  info %s" % str({"items": report["items"], "vehicles": report["vehicles"], "creatures": report["creatures"], "scenery": report["scenery"]}))
	_check(is_instance_valid(_mule) and is_instance_valid(player) and is_instance_valid(out_player), "the ship and both players are still there")
	_check(is_instance_valid(crate_in) and is_instance_valid(item_in) and is_instance_valid(car_in) and is_instance_valid(creature_in), "everything inside the ship is still there: crate, battery, car and creature")
	_check(is_instance_valid(cargo_on_car) and is_instance_valid(on_hull), "so is whatever is fastened to the car or to the hull")
	_check(not is_instance_valid(crate_out) and not is_instance_valid(crate_far), "crates outside are gone, near and far")
	_check(not is_instance_valid(car_out), "the car outside is gone")
	_check(not is_instance_valid(creature_out), "the creature outside is gone")
	_check(not is_instance_valid(item_out), "the battery outside is gone")
	_check(not is_instance_valid(scenery), "and so is tagged scenery")
	_check(is_instance_valid(plain) and is_instance_valid(plain_child), "ordinary nodes are left alone")
	_check(report["items"] == 3 and report["vehicles"] == 1 and report["creatures"] == 1 and report["scenery"] == 1, "and the report counts them: 3 items, 1 vehicle, 1 creature, 1 scenery")
	_check(streamer.get_asteroid_count() > 100 and streamer.get_child_count() > 10, "asteroids are not touched by the purge itself (the streamer clears them)")
	_check(player.find_children("*", "ItemActor", true, false).size() == held_before, "nothing the player carries was touched")
	streamer.clear()
	_check(streamer.get_child_count() == 0, "and the streamer clears them all")

	# Held items go with the player even when the player is far from the ship.
	var rig_holder := out_player.find_child("ItemHolder", true, false) as ItemHolder
	var carried_far := out_player.find_children("*", "ItemActor", true, false)
	var kept_after := JumpPurge.purge(_world, _mule, null)
	await _frames(3)
	_check(is_instance_valid(out_player) and out_player.find_children("*", "ItemActor", true, false).size() == carried_far.size(), "a player outside the ship keeps what they carry (%d actors)" % carried_far.size())
	_check(kept_after["items"] == 0 and kept_after["vehicles"] == 0, "and a second jump with nothing left outside deletes nothing")
	if rig_holder == null:
		print("  info the Player has no ItemHolder under that name")
	player.free()
	out_player.free()
	for node: Node in [crate_in, car_in, creature_in, item_in, plain]:
		if is_instance_valid(node):
			node.free()
	streamer.free()


func _test_recall() -> void:
	print("Bringing players aboard")
	var inside := PLAYER_SCENE.instantiate() as Player
	inside.position = Vector3(0.0, 0.1, 1.5)
	_world.add_child(inside)
	var outside_a := PLAYER_SCENE.instantiate() as Player
	var outside_b := PLAYER_SCENE.instantiate() as Player
	_world.add_child(outside_a)
	_world.add_child(outside_b)
	outside_a.global_position = Vector3(500.0, 20.0, 0.0)
	outside_b.global_position = Vector3(0.0, 0.0, -900.0)
	_mule.linear_velocity = Vector3.ZERO
	await _frames(40)
	_check(JumpPurge.is_aboard(inside, _mule, _interiors) and not JumpPurge.is_aboard(outside_a, _mule, _interiors), "one player is aboard and two are not")
	var inside_before := inside.global_position
	var brought := JumpPurge.recall_players(_world, _mule)
	_check(brought.size() == 2 and brought.has(outside_a) and brought.has(outside_b) and not brought.has(inside), "the two outside are brought and the one aboard is left alone")
	_check(inside.global_position.is_equal_approx(inside_before), "the one aboard did not move")
	_check(_interiors[0].contains_point(outside_a.global_position) and _interiors[0].contains_point(outside_b.global_position), "both are now inside the ship")
	_check(outside_a.global_position.distance_to(outside_b.global_position) > 0.9, "and not on top of each other (%.2f m apart)" % outside_a.global_position.distance_to(outside_b.global_position))
	await _frames(90)
	_check(JumpPurge.is_aboard(outside_a, _mule, _interiors) and JumpPurge.is_aboard(outside_b, _mule, _interiors), "they stay aboard")
	_check(outside_a.is_on_floor() and outside_b.is_on_floor(), "and stand on the floor of the hold")
	_check(outside_a.global_basis.y.dot(_mule.global_basis.y) > 0.99, "upright in the ship")
	# The same thing with the ship moving and turned: they arrive at rest in it.
	_mule.global_transform = Transform3D(Basis(Vector3.UP, 0.8), Vector3(2000.0, 300.0, -800.0))
	_mule.linear_velocity = Vector3(6.0, 0.0, 2.0)
	await _frames(30)
	outside_a.global_position = Vector3(0.0, 0.0, 0.0)
	var again := JumpPurge.recall_players(_world, _mule, _mule.linear_velocity)
	var placed_at := _mule.to_local(outside_a.global_position)
	await _frames(60)
	# Inside the ship a body's velocity is kept relative to the ship (see VehicleInterior3D).
	var drift := _mule.to_local(outside_a.global_position).distance_to(placed_at)
	_check(again.has(outside_a) and JumpPurge.is_aboard(outside_a, _mule, _interiors), "in a moving ship they are brought too")
	_check(outside_a.velocity.length() < 1.0 and drift < 0.3, "and arrive at rest in it, not flying across it (%.2f m/s against the ship, %.0f cm from where they were put)" % [outside_a.velocity.length(), drift * 100.0])
	_mule.linear_velocity = Vector3.ZERO
	_mule.global_transform = Transform3D.IDENTITY
	inside.free()
	outside_a.free()
	outside_b.free()
	await _frames(5)

	# A marker in the ship's tree says where to put people.
	var marker := Marker3D.new()
	marker.add_to_group(JumpPurge.RECALL_POINT_GROUP)
	_mule.add_child(marker)
	marker.position = Vector3(1.0, 0.1, -3.0)
	var stranded := PLAYER_SCENE.instantiate() as Player
	_world.add_child(stranded)
	stranded.global_position = Vector3(50.0, 0.0, 0.0)
	JumpPurge.recall_players(_world, _mule)
	_check(stranded.global_position.distance_to(_mule.to_global(marker.position)) < 0.01, "a marker in the group ship_recall is where they are put")
	stranded.free()
	marker.free()

	# Sitting in one of the ship's seats counts as being aboard, even outside the hold's box.
	var pilot := PLAYER_SCENE.instantiate() as Player
	_world.add_child(pilot)
	var seat := _mule.find_child("PilotSeat", true, false) as VehicleSeat3D
	pilot.global_position = seat.get_dismount_transform().origin
	await _frames(40)
	var seat_controller := pilot.get_node("VehicleController") as VehicleController
	_check(seat_controller.enter_seat(seat), "a player can sit in the pilot seat")
	await _frames(40)
	pilot.global_position = Vector3(900.0, 0.0, 0.0)
	await _frames(2)
	var seats := SeatController.find_on_actor(pilot)
	_check(seats != null and is_instance_valid(seats.current_seat) and JumpPurge.is_aboard(pilot, _mule, _interiors), "someone sitting in the ship's seat is aboard wherever they are measured")
	seat_controller.exit_seat()
	pilot.free()


func _test_groups() -> void:
	print("Groups")
	var keeper := RigidBody3D.new()
	keeper.collision_layer = PhysicsLayers.ITEMS
	keeper.add_to_group(JumpPurge.KEEP_GROUP)
	_world.add_child(keeper)
	keeper.global_position = Vector3(700.0, 0.0, 0.0)
	var vehicle_keeper := Vehicle3D.new()
	vehicle_keeper.add_to_group(JumpPurge.KEEP_GROUP)
	_world.add_child(vehicle_keeper)
	vehicle_keeper.global_position = Vector3(-700.0, 0.0, 0.0)
	var other_ship := Vehicle3D.new()
	_world.add_child(other_ship)
	other_ship.global_position = Vector3(0.0, 900.0, 0.0)
	await _frames(3)
	JumpPurge.purge(_world, _mule)
	await _frames(3)
	_check(is_instance_valid(keeper) and is_instance_valid(vehicle_keeper), "things in the jump_keep group stay wherever they are")
	_check(not is_instance_valid(other_ship), "while another ship that is not the main one is deleted")
	if is_instance_valid(keeper):
		keeper.free()
	if is_instance_valid(vehicle_keeper):
		vehicle_keeper.free()


# --- Helpers --------------------------------------------------------------------------------

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
	crate.global_position = at
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
	car.global_position = at
	return car


func _make_creature(at: Vector3) -> WalkingCharacter3D:
	var creature := TestCharacter.make("Creature", PhysicsLayers.CREATURES, PhysicsLayers.CREATURE_MASK)
	_world.add_child(creature)
	creature.global_position = at
	return creature


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame
