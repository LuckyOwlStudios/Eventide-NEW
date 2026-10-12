extends Node
## Headless checks for the physics layer setup (see PhysicsLayers), on real Jolt physics.
##
## godot --headless --fixed-fps 60 --path . res://Components/Physics/Testing/CollisionLayersTest.tscn

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const WORLD_SCENE := preload("res://Game/World.tscn")

var physics_frame: Signal
var _world: Node3D
var _failures := 0


class Walker extends CharacterController:
	var move := Vector2.ZERO

	func poll_intent(_delta: float) -> MoveIntent:
		var intent := MoveIntent.new()
		intent.move = move
		return intent


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in [
		"layer_names", "scene_setup", "scene_values_win", "characters_push_items", "items_cannot_push_characters",
		"vehicle_interiors", "hull_rules", "characters_and_creatures", "gravity_fields", "interaction_ray",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Collision layer tests passed.")
	else:
		print("Collision layer tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

## A ship you can walk inside has a hull body that characters and items never touch.
func _test_hull_rules() -> void:
	_check(PhysicsLayers.HULL_MASK & (PhysicsLayers.CHARACTERS | PhysicsLayers.ITEMS) == 0, "a hull never scans characters or items, so it cannot fill a cargo bay")
	_check(PhysicsLayers.SOLID & PhysicsLayers.HULLS == 0 and PhysicsLayers.PLAYER_MASK & PhysicsLayers.HULLS == 0, "and characters do not scan hulls")
	_check(PhysicsLayers.VEHICLE_MASK & PhysicsLayers.HULLS != 0 and PhysicsLayers.HULL_MASK & PhysicsLayers.VEHICLES != 0, "but vehicles and hulls hit each other")
	_check(PhysicsLayers.WORLD_GRAVITY_MASK & PhysicsLayers.HULLS != 0 and PhysicsLayers.INTERIOR_GRAVITY_MASK & PhysicsLayers.HULLS == 0, "world gravity pulls hulls and interior gravity does not")


## The names in Project Settings must match the PhysicsLayers constants.
func _test_layer_names() -> void:
	var expected := {
		1: ["World", PhysicsLayers.WORLD],
		2: ["Players", PhysicsLayers.PLAYERS],
		3: ["Creatures", PhysicsLayers.CREATURES],
		4: ["Vehicles", PhysicsLayers.VEHICLES],
		5: ["Vehicle Interiors", PhysicsLayers.VEHICLE_INTERIORS],
		6: ["Items", PhysicsLayers.ITEMS],
		7: ["Interactables", PhysicsLayers.INTERACTABLES],
		8: ["Projectiles", PhysicsLayers.PROJECTILES],
		9: ["Gravity Fields", PhysicsLayers.GRAVITY_FIELDS],
		10: ["Hulls", PhysicsLayers.HULLS],
	}
	for number: int in expected:
		var name := str(ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % number, ""))
		var entry: Array = expected[number]
		_check(name == entry[0], "layer %d is named '%s' (got '%s')" % [number, entry[0], name])
		_check(int(entry[1]) == 1 << (number - 1), "and PhysicsLayers uses bit %d for it" % (number - 1))
	await physics_frame


## The scenes the project ships must use the layers, not the defaults.
func _test_scene_setup() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	add_child(player)
	_check(player.collision_layer == PhysicsLayers.PLAYERS, "the player is on the Players layer (%d)" % player.collision_layer)
	_check(player.collision_mask == PhysicsLayers.PLAYER_MASK, "and scans the player mask (%d)" % player.collision_mask)
	var ray := player.get_node("HeadRoot/YawPivot/PitchPivot/Camera3D/InteractionRayCast3D") as RayCast3D
	_check(ray.collision_mask & PhysicsLayers.INTERACTABLES != 0, "the player's interaction ray can see interactables (mask %d)" % ray.collision_mask)
	var hides := ray.collision_mask & PhysicsLayers.SOLID == PhysicsLayers.SOLID
	print("  info the player's ray %s walls and hulls hiding interactables (mask %d, default is %d)" % ["has" if hides else "does NOT have", ray.collision_mask, PhysicsLayers.INTERACTION_RAY_MASK])
	player.free()

	# Nodes made in code get their class's layers once they join the tree.
	var interactable := InteractableObject3D.new()
	add_child(interactable)
	_check(interactable.collision_layer == PhysicsLayers.INTERACTABLES and interactable.collision_mask == 0, "interactables sit on their own layer and scan nothing")
	interactable.free()
	var ladder := Ladder3D.new()
	add_child(ladder)
	_check(ladder.collision_layer == PhysicsLayers.INTERACTABLES, "ladders are interactables (layer %d)" % ladder.collision_layer)
	ladder.free()
	var door_switch := DoorSwitch3D.new()
	add_child(door_switch)
	_check(door_switch.collision_layer == PhysicsLayers.INTERACTABLES, "door switches are interactables")
	door_switch.free()
	var new_ray := InteractionRayCast3D.new()
	add_child(new_ray)
	_check(new_ray.collision_mask == PhysicsLayers.INTERACTION_RAY_MASK, "a new interaction ray scans solids and interactables by default")
	new_ray.free()
	var field := DirectionalGravityField3D.new()
	add_child(field)
	_check(field.collision_layer == PhysicsLayers.GRAVITY_FIELDS, "gravity fields are on the Gravity Fields layer")
	_check(field.collision_mask == PhysicsLayers.WORLD_GRAVITY_MASK, "and pull characters, vehicles and items by default")
	field.free()

	var mule := MULE_SCENE.instantiate()
	add_child(mule)
	var interior_field := mule.get_node("Area") as Area3D
	_check(interior_field.collision_mask == PhysicsLayers.INTERIOR_GRAVITY_MASK, "the Mule's interior gravity does not pull the Mule itself (%d)" % interior_field.collision_mask)
	var hull_parts := 0
	for body in _collect_csg_roots(mule):
		hull_parts += 1
		_check(body.collision_layer == PhysicsLayers.VEHICLE_INTERIORS, "Mule part %s is on the Vehicle Interiors layer, so the ship does not collide with its own walls" % body.name)
	_check(hull_parts > 0, "found the Mule's collision parts (%d)" % hull_parts)
	var door_rays := 0
	for node in mule.find_children("*", "CurvedRayCast3D", true, false):
		door_rays += 1
		_check((node as CurvedRayCast3D).collision_mask & (PhysicsLayers.CHARACTERS | PhysicsLayers.ITEMS) == 0, "door ray %s ignores people, creatures and items, so the Mule door pushes them aside" % node.name)
	_check(door_rays >= 2, "found the Mule's door rays (%d)" % door_rays)
	mule.free()

	var world := WORLD_SCENE.instantiate()
	add_child(world)
	var scenery := 0
	for node in world.get_children():
		if node is CSGShape3D and (node as CSGShape3D).use_collision:
			scenery += 1
			_check((node as CSGShape3D).collision_layer == PhysicsLayers.WORLD, "scenery %s is on the World layer" % node.name)
	_check(scenery >= 2, "found the world's scenery (%d)" % scenery)
	for node in world.find_children("*", "DirectionalGravityField3D", true, false):
		if "Mule" in str(node.get_path()):
			continue
		_check((node as Area3D).collision_mask == PhysicsLayers.WORLD_GRAVITY_MASK, "world gravity field %s pulls characters, vehicles and items" % node.get_path())
	world.queue_free()
	await physics_frame


## Players and creatures walking into loose items shove them away without being slowed.
func _test_characters_push_items() -> void:
	for config in [
		{"label": "player", "layer": PhysicsLayers.PLAYERS, "mask": PhysicsLayers.PLAYER_MASK},
		{"label": "creature", "layer": PhysicsLayers.CREATURES, "mask": PhysicsLayers.CREATURE_MASK},
	]:
		_begin_world()
		var walker := _make_character(Vector3(0.0, 0.05, 0.0), config["layer"], config["mask"])
		var item := _make_item(Vector3(0.0, 0.3, -3.0), 1.0)
		await _ticks(30)
		var item_start := item.global_position
		walker.move = Vector2(0.0, -1.0)
		await _ticks(90)
		var body := walker.get_body()
		var travelled := -body.global_position.z
		var pushed := item_start.distance_to(item.global_position)
		_check(travelled > 5.5, "a %s walks on through the item at full pace (%.2f m in 1.5 s)" % [config["label"], travelled])
		_check(pushed > 1.0, "and the item gets shoved out of the way (%.2f m)" % pushed)
		_end_world()

	# Even a heavy crate gives way; mass only matters for how fast it slides.
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	var crate := _make_item(Vector3(0.0, 0.3, -3.0), 200.0)
	await _ticks(30)
	var crate_start := crate.global_position
	walker.move = Vector2(0.0, -1.0)
	await _ticks(90)
	print("  info heavy crate shoved %.2f m, player travelled %.2f m" % [crate_start.distance_to(crate.global_position), -walker.get_body().global_position.z])
	_check(-walker.get_body().global_position.z > 5.0, "a heavy crate does not stop the player either")
	_end_world()


## Nothing an item does can move a character, and an item sitting where a character
## stands does not get in the way of its movement.
func _test_items_cannot_push_characters() -> void:
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	await _ticks(30)
	var body := walker.get_body()
	var before := body.global_position
	var missile := _make_item(Vector3(0.0, 1.0, 4.0), 500.0)
	missile.linear_velocity = Vector3(0.0, 0.0, -15.0)
	missile.gravity_scale = 0.0
	await _ticks(90)
	var moved := before.distance_to(body.global_position)
	_check(moved < 0.01, "a heavy item flung at a player does not move them (%.4f m)" % moved)
	_check(walker.is_grounded(), "and they stay on their feet")
	_end_world()

	# Items lying around under a character's feet must not lift it or snag its stairs.
	_begin_world()
	for index in 8:
		_make_item(Vector3(0.6 * float(index) - 2.0, 0.15, -2.0), 1.0, Vector3(0.3, 0.3, 0.3))
	walker = _make_character(Vector3(0.0, 0.05, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	await _ticks(30)
	walker.move = Vector2(0.0, -1.0)
	await _ticks(75)
	_check(-walker.get_body().global_position.z > 5.0, "walking through a field of small items is not slowed (%.2f m)" % -walker.get_body().global_position.z)
	_end_world()


## Interiors carry people and things but ignore the world and cannot be pushed.
func _test_vehicle_interiors() -> void:
	# Characters and items stand on an interior floor.
	_begin_world()
	_make_interior_box(Vector3(0.0, 10.0, 0.0), Vector3(10.0, 0.2, 10.0))
	var walker := _make_character(Vector3(0.0, 11.0, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	var crate := _make_item(Vector3(3.0, 11.0, 0.0), 1.0)
	await _ticks(90)
	var body := walker.get_body()
	_check(walker.is_grounded() and absf(body.global_position.y - 10.1) < 0.05, "a player stands on an interior floor (y=%.3f)" % body.global_position.y)
	_check(absf(crate.global_position.y - 10.35) < 0.08, "so does an item (y=%.3f)" % crate.global_position.y)

	# The world does not touch it: a vehicle body falls straight through the floor.
	# A car (a vehicle body) drives about on an interior floor, since it is inside another vehicle.
	var car := _make_rigid(Vector3(-3.0, 12.0, 3.0), PhysicsLayers.VEHICLES, PhysicsLayers.VEHICLE_MASK, 100.0)
	# The solid body of the ship itself is on the Hulls layer, which never scans its own interior.
	var ship_body := _make_rigid(Vector3(3.0, 12.0, 3.0), PhysicsLayers.HULLS, PhysicsLayers.HULL_MASK, 100.0)
	await _ticks(120)
	_check(car.global_position.y > 9.0, "a car stands on an interior floor, so it can drive inside a ship (y=%.2f)" % car.global_position.y)
	_check(ship_body.global_position.y < 1.0, "while the ship's own body falls through it (y=%.2f)" % ship_body.global_position.y)
	_end_world()

	# Characters are blocked by an interior wall, and cannot budge it even if it is loose.
	_begin_world()
	var wall := _make_rigid(Vector3(0.0, 1.0, -3.0), PhysicsLayers.VEHICLE_INTERIORS, PhysicsLayers.VEHICLE_INTERIOR_MASK, 1.0, Vector3(4.0, 2.0, 0.3))
	wall.gravity_scale = 0.0
	walker = _make_character(Vector3(0.0, 0.05, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	await _ticks(30)
	var wall_start := wall.global_position
	walker.move = Vector2(0.0, -1.0)
	await _ticks(120)
	body = walker.get_body()
	_check(body.global_position.z > -2.9, "a player is stopped by an interior wall (z=%.2f)" % body.global_position.z)
	var shifted := wall_start.distance_to(wall.global_position)
	_check(shifted < 0.01, "and pushing on it does nothing (%.4f m)" % shifted)
	_end_world()


## Players walk through each other; creatures and players block one another.
func _test_characters_and_creatures() -> void:
	_begin_world()
	var first := _make_character(Vector3(0.0, 0.05, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	var second := _make_character(Vector3(0.0, 0.05, -3.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	await _ticks(30)
	first.move = Vector2(0.0, -1.0)
	await _ticks(90)
	_check(first.get_body().global_position.z < -5.0, "players pass through each other (z=%.2f)" % first.get_body().global_position.z)
	_end_world()

	_begin_world()
	var player := _make_character(Vector3(0.0, 0.05, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	var creature := _make_character(Vector3(0.0, 0.05, -3.0), PhysicsLayers.CREATURES, PhysicsLayers.CREATURE_MASK)
	await _ticks(30)
	player.move = Vector2(0.0, -1.0)
	await _ticks(90)
	_check(player.get_body().global_position.z > -2.5, "a player is stopped by a creature (z=%.2f)" % player.get_body().global_position.z)
	_check(absf(creature.get_body().global_position.z + 3.0) < 0.05, "and cannot shove it (z=%.2f)" % creature.get_body().global_position.z)
	_end_world()


## World gravity pulls everything; interior gravity only holds what is inside.
func _test_gravity_fields() -> void:
	_begin_world(false)
	# Inside a vehicle: a field that pulls toward +X, over the top of the world's.
	var interior := DirectionalGravityField3D.new()
	interior.collision_mask = PhysicsLayers.INTERIOR_GRAVITY_MASK
	interior.priority = 1
	interior.local_gravity_direction = Vector3.RIGHT
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 20.0, 20.0)
	shape.shape = box
	interior.add_child(shape)
	interior.position = Vector3(0.0, 100.0, 0.0)
	_world.add_child(interior)

	var player := _make_character(Vector3(0.0, 100.0, 0.0), PhysicsLayers.PLAYERS, PhysicsLayers.PLAYER_MASK)
	var creature := _make_character(Vector3(3.0, 100.0, 0.0), PhysicsLayers.CREATURES, PhysicsLayers.CREATURE_MASK)
	var item := _make_rigid(Vector3(-3.0, 100.0, 0.0), PhysicsLayers.ITEMS, PhysicsLayers.ITEM_MASK, 1.0)
	var hull := _make_rigid(Vector3(0.0, 100.0, 3.0), PhysicsLayers.HULLS, PhysicsLayers.HULL_MASK, 100.0)
	var car := _make_rigid(Vector3(0.0, 100.0, -3.0), PhysicsLayers.VEHICLES, PhysicsLayers.VEHICLE_MASK, 100.0)
	await _ticks(3)
	var player_gravity := _gravity_of(player.get_body())
	var creature_gravity := _gravity_of(creature.get_body())
	var item_gravity := _gravity_of(item)
	var hull_gravity := _gravity_of(hull)
	_check(player_gravity.x > 15.0 and absf(player_gravity.y) < 0.1, "interior gravity holds a player (%s)" % player_gravity)
	_check(creature_gravity.x > 15.0, "a creature (%s)" % creature_gravity)
	_check(item_gravity.x > 15.0, "and an item (%s)" % item_gravity)
	_check(_gravity_of(car).x > 15.0, "and a car")
	_check(hull_gravity.length() < 0.01, "but not the ship's own body (%s)" % hull_gravity)
	_end_world()

	# Out in the world, the vehicle is pulled as well.
	_begin_world(false)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(60.0, 60.0, 60.0)
	field_shape.shape = field_box
	field.add_child(field_shape)
	_world.add_child(field)
	var hull_outside := _make_rigid(Vector3(0.0, 0.0, 0.0), PhysicsLayers.VEHICLES, PhysicsLayers.VEHICLE_MASK, 100.0)
	var projectile := _make_rigid(Vector3(5.0, 0.0, 0.0), PhysicsLayers.PROJECTILES, PhysicsLayers.PROJECTILE_MASK, 0.1)
	await _ticks(3)
	var outside_gravity := _gravity_of(hull_outside)
	_check(outside_gravity.y < -15.0, "world gravity pulls a vehicle (%s)" % outside_gravity)
	_check(_gravity_of(projectile).length() < 0.01, "but projectiles fly straight (%s)" % _gravity_of(projectile))
	_end_world()


## The interaction ray is blocked by solid things and ignores everything else.
func _test_interaction_ray() -> void:
	_begin_world()
	var button := InteractableObject3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	button.add_child(shape)
	button.position = Vector3(0.0, 1.5, -5.0)
	_world.add_child(button)

	# Things the ray must look through.
	var bystander := _make_character(Vector3(0.0, 0.05, -2.0), PhysicsLayers.CREATURES, PhysicsLayers.CREATURE_MASK)
	var item := _make_item(Vector3(0.0, 1.5, -3.0), 1.0, Vector3(0.4, 0.4, 0.4))
	item.gravity_scale = 0.0
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(2.0, 2.0, 0.5)
	field_shape.shape = field_box
	field.add_child(field_shape)
	field.position = Vector3(0.0, 1.5, -1.5)
	_world.add_child(field)
	await _ticks(10)

	var hit := _cast(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	_check(hit.get("collider") == button, "the ray looks through characters, items and gravity fields to the button")

	# Things the ray must stop at.
	var wall := _add_static(Vector3(0.0, 1.5, -4.0), Vector3(4.0, 3.0, 0.2), PhysicsLayers.WORLD)
	await physics_frame
	hit = _cast(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	_check(hit.get("collider") == wall, "a wall in front hides the button")
	wall.free()
	var hull := _add_static(Vector3(0.0, 1.5, -4.0), Vector3(4.0, 3.0, 0.2), PhysicsLayers.VEHICLES)
	await physics_frame
	hit = _cast(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	_check(hit.get("collider") == hull, "so does a vehicle hull")
	hull.free()
	var partition := _add_static(Vector3(0.0, 1.5, -4.0), Vector3(4.0, 3.0, 0.2), PhysicsLayers.VEHICLE_INTERIORS)
	await physics_frame
	hit = _cast(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	_check(hit.get("collider") == partition, "and an interior partition")
	_end_world()


# --- Helpers -----------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _begin_world(with_floor := true) -> void:
	_world = Node3D.new()
	_world.name = "TestWorld"
	add_child(_world)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300.0, 300.0, 300.0)
	field_shape.shape = field_box
	field_shape.position = Vector3(0.0, 100.0, 0.0)
	field.add_child(field_shape)
	if with_floor:
		_world.add_child(field)
		_add_static(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0), PhysicsLayers.WORLD)
	else:
		field.free()


func _end_world() -> void:
	_world.free()
	_world = null


func _add_static(center: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


## Interiors ride on their vehicle, so they are animatable bodies.
func _make_interior_box(center: Vector3, size: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.collision_layer = PhysicsLayers.VEHICLE_INTERIORS
	body.collision_mask = PhysicsLayers.VEHICLE_INTERIOR_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


func _make_rigid(
	center: Vector3,
	layer: int,
	mask: int,
	mass: float,
	size := Vector3(0.5, 0.5, 0.5),
) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = layer
	body.collision_mask = mask
	body.mass = mass
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


func _make_item(center: Vector3, mass: float, size := Vector3(0.5, 0.5, 0.5)) -> RigidBody3D:
	return _make_rigid(center, PhysicsLayers.ITEMS, PhysicsLayers.ITEM_MASK, mass, size)


func _make_character(position: Vector3, layer: int, mask: int) -> Walker:
	var body := CharacterBody3D.new()
	body.collision_layer = layer
	body.collision_mask = mask
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	var stats := MovementAttribute.new()
	body.add_child(stats)
	var orientor := Orientator.new()
	body.add_child(orientor)
	var walker := Walker.new()
	body.add_child(walker)
	body.position = position
	_world.add_child(body)
	return walker


func _gravity_of(body: PhysicsBody3D) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return state.total_gravity if state != null else Vector3.ZERO


## A ray the way the interaction ray fires it: areas and bodies, scanning the interaction mask.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.INTERACTION_RAY_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return _world.get_world_3d().direct_space_state.intersect_ray(query)


func _collect_csg_roots(root: Node) -> Array[CSGShape3D]:
	var found: Array[CSGShape3D] = []
	for node in root.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if shape.use_collision and not (shape.get_parent() is CSGShape3D):
			found.append(shape)
	return found


## Whatever a scene saves for layers and masks must survive loading. A scene sets its
## native properties before it assigns the script, so a script that forced its own values
## in _init would silently overwrite them.
func _test_scene_values_win() -> void:
	var button := InteractableObject3D.new()
	button.collision_layer = PhysicsLayers.ITEMS
	button.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ITEMS
	var field := DirectionalGravityField3D.new()
	field.collision_layer = PhysicsLayers.PROJECTILES
	field.collision_mask = PhysicsLayers.ITEMS
	var ray := InteractionRayCast3D.new()
	ray.collision_mask = PhysicsLayers.INTERACTABLES
	var root := Node3D.new()
	for node in [button, field, ray]:
		root.add_child(node)
		node.owner = root
	var packed := PackedScene.new()
	_check(packed.pack(root) == OK, "a scene with custom layers packs")
	root.free()

	var loaded := packed.instantiate()
	add_child(loaded)
	var loaded_button := loaded.get_child(0) as InteractableObject3D
	var loaded_field := loaded.get_child(1) as DirectionalGravityField3D
	var loaded_ray := loaded.get_child(2) as InteractionRayCast3D
	_check(loaded_button.collision_layer == PhysicsLayers.ITEMS and loaded_button.collision_mask == (PhysicsLayers.WORLD | PhysicsLayers.ITEMS), "an interactable keeps the layer and mask its scene saved (%d, %d)" % [loaded_button.collision_layer, loaded_button.collision_mask])
	_check(loaded_field.collision_layer == PhysicsLayers.PROJECTILES and loaded_field.collision_mask == PhysicsLayers.ITEMS, "so does a gravity field (%d, %d)" % [loaded_field.collision_layer, loaded_field.collision_mask])
	_check(loaded_ray.collision_mask == PhysicsLayers.INTERACTABLES, "and the interaction ray (%d)" % loaded_ray.collision_mask)
	loaded.free()
	await physics_frame
