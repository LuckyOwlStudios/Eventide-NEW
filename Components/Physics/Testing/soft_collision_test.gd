extends Node
## Headless checks for SoftCollision3D on real Jolt physics: a body that pushes itself away from
## others instead of colliding hard, so a pusher cannot squeeze it through a wall.
##
## godot --headless --fixed-fps 60 --path . res://Components/Physics/Testing/SoftCollisionTest.tscn
## ONLY=<name> runs one test, such as ONLY=wall.

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")

var physics_frame: Signal
var _world: Node3D
var _failures := 0


## A character that walks the way it is told, with the real controller.
class Walker extends CharacterController:
	var move := Vector2.ZERO
	var sprint := false

	func poll_intent(_delta: float) -> MoveIntent:
		var intent := MoveIntent.new()
		intent.move = move
		intent.sprint = sprint
		return intent


func _ready() -> void:
	physics_frame = get_tree().physics_frame
	_run()


func _run() -> void:
	InGameUIHandler.is_ui_open = false
	var only := OS.get_environment("ONLY")
	for test_name in [
		"wall", "riding", "heavy", "players_unmoved", "characters", "level", "margin", "defaults", "switches",
		"family", "friction", "no_controller", "engulfed", "player_scene", "ship", "cost",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	InGameUIHandler.is_ui_open = true
	if _failures == 0:
		print("Soft collision tests passed.")
	else:
		print("Soft collision tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

## The reason for all of it: a player walking an item into a wall.
func _test_wall() -> void:
	for soft in [false, true]:
		_begin_world()
		_add_static(Vector3(0.0, 1.5, -4.0), Vector3(20.0, 3.0, 0.2), PhysicsLayers.WORLD)
		var walker := _make_character(Vector3(0.0, 0.05, 0.0))
		var item := _make_item(Vector3(0.0, 0.3, -2.0), Vector3.ONE * 0.5, 5.0, soft)
		await _ticks(30)
		walker.move = Vector2(0.0, -1.0)
		var furthest := 0.0
		for tick in 240:
			await physics_frame
			furthest = minf(furthest, item.global_position.z - 0.25)
		if soft:
			_check(furthest > -3.91, "with soft collision the item stops at the wall (its face reached z=%.2f, the wall's is -3.90)" % furthest)
			_check(absf(item.global_position.x) < 0.05, "and does not squirt out sideways (x=%.2f)" % item.global_position.x)
		else:
			_check(furthest < -3.95, "with hard collision the player squeezes it into the wall (its face reached z=%.2f, the wall's is -3.90)" % furthest)
		_end_world()

	# A thin wall, a sprinting player, and a small item are the ways that would still get through.
	for config in [{"label": "a crate", "size": 0.5}, {"label": "a small item", "size": 0.12}]:
		_begin_world()
		_add_static(Vector3(0.0, 1.5, -4.0), Vector3(20.0, 3.0, 0.05), PhysicsLayers.WORLD)
		var walker := _make_character(Vector3(0.0, 0.05, 0.0))
		walker.sprint = true
		var size: float = config["size"]
		var item := _make_item(Vector3(0.0, size * 0.5 + 0.01, -2.0), Vector3.ONE * size, 2.0, true)
		await _ticks(30)
		walker.move = Vector2(0.0, -1.0)
		var furthest := 0.0
		for tick in 240:
			await physics_frame
			furthest = minf(furthest, item.global_position.z - size * 0.5)
		_check(furthest > -4.03, "%s pushed by a sprinting player does not cross a thin wall (its face reached z=%.3f, the wall's is -3.975)" % [config["label"], furthest])
		_end_world()


## A pushed item rides in front of the player, upright, instead of tipping or being walked through.
func _test_riding() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	var tall := BoxShape3D.new()
	tall.size = Vector3(0.4, 0.9, 0.4)
	var plank := BoxShape3D.new()
	plank.size = Vector3(0.2, 0.2, 1.2)
	var barrel := CylinderShape3D.new()
	barrel.radius = 0.3
	barrel.height = 0.8
	for config in [
		{"label": "a crate", "shape": box},
		{"label": "a tall box", "shape": tall},
		{"label": "a plank", "shape": plank},
		{"label": "a barrel", "shape": barrel},
	]:
		_begin_world()
		var walker := _make_character(Vector3(0.0, 0.05, 0.0))
		var shape: Shape3D = config["shape"]
		var height := shape.get_debug_mesh().get_aabb().size.y
		var item := _make_item(Vector3(0.0, height * 0.5 + 0.01, -2.0), Vector3.ONE, 5.0, true, shape)
		await _ticks(30)
		walker.move = Vector2(0.0, -1.0)
		var tilt := 0.0
		var fastest := 0.0
		for tick in 180:
			await physics_frame
			tilt = maxf(tilt, rad_to_deg(item.global_basis.y.angle_to(Vector3.UP)))
			if tick < 20:
				fastest = maxf(fastest, -item.linear_velocity.z)
		var body := walker.get_body()
		var gap := body.global_position.z - item.global_position.z
		_check(-body.global_position.z > 12.0, "the player is not slowed by %s (%.1f m in 3 s)" % [config["label"], -body.global_position.z])
		_check(gap > 0.3 and gap < 1.2, "%s is still in front of the player and right against them (%.2f m apart)" % [config["label"], gap])
		_check(tilt < 5.0, "and stays upright (%.1f degrees)" % tilt)
		_check(fastest < 6.5, "and starts without a jolt (top speed in the first third of a second %.1f m/s, the player walks at 5)" % fastest)
		_end_world()


## How heavy something feels is how fast it can be pushed along.
func _test_heavy() -> void:
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0))
	var light := _make_item(Vector3(2.0, 0.3, -2.0), Vector3.ONE * 0.5, 5.0, true)
	var heavy := _make_item(Vector3(-2.0, 0.3, -2.0), Vector3.ONE * 0.5, 200.0, true)
	(heavy.get_node("SoftCollision3D") as SoftCollision3D).maximum_speed = 1.0
	await _ticks(30)
	# Walk into each one in turn, along the line it sits on.
	walker.get_body().global_position = Vector3(2.0, 0.05, 0.0)
	await _ticks(2)
	walker.move = Vector2(0.0, -1.0)
	await _ticks(80)
	_check(light.global_position.z < -4.0, "a light item is carried along ahead of the player (z=%.2f)" % light.global_position.z)
	walker.move = Vector2.ZERO
	walker.get_body().global_position = Vector3(-2.0, 0.05, 0.0)
	await _ticks(2)
	walker.move = Vector2(0.0, -1.0)
	await _ticks(80)
	_check(-walker.get_body().global_position.z > 5.0, "the player walks straight on through one that can only be pushed along at 1 m/s (z=%.2f)" % walker.get_body().global_position.z)
	_check(heavy.global_position.z > -3.0, "which is left behind, not carried off (z=%.2f from -2)" % heavy.global_position.z)
	_end_world()


## Items cannot move a player, however they hit.
func _test_players_unmoved() -> void:
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	var body := walker.get_body()
	var before := body.global_position
	var missile := _make_item(Vector3(0.0, 1.0, 4.0), Vector3.ONE * 0.5, 500.0, true)
	missile.linear_velocity = Vector3(0.0, 0.0, -15.0)
	missile.gravity_scale = 0.0
	await _ticks(90)
	_check(before.distance_to(body.global_position) < 0.01, "a heavy item flung at a player does not move them (%.4f m)" % before.distance_to(body.global_position))
	_check(walker.is_grounded(), "and they stay on their feet")
	_end_world()

	# And a player is not slowed or lifted by items lying about.
	_begin_world()
	for index in 8:
		_make_item(Vector3(0.6 * float(index) - 2.0, 0.15, -2.0), Vector3.ONE * 0.3, 1.0, true)
	walker = _make_character(Vector3(0.0, 0.05, 0.0))
	await _ticks(30)
	walker.move = Vector2(0.0, -1.0)
	await _ticks(75)
	_check(-walker.get_body().global_position.z > 5.0, "walking through a field of small items is not slowed (%.2f m)" % -walker.get_body().global_position.z)
	_end_world()


## Characters with the node nudge themselves apart, and only the ones that have it.
func _test_characters() -> void:
	_begin_world()
	var first := _make_character(Vector3(0.0, 0.05, 0.0), true)
	var second := _make_character(Vector3(0.4, 0.05, 0.0), true)
	await _ticks(60)
	var apart := first.get_body().global_position.distance_to(second.get_body().global_position)
	_check(apart > 0.77, "two characters standing inside each other get apart (%.2f m, touching is 0.80)" % apart)
	_check(first.get_body().global_position.x < 0.0 and second.get_body().global_position.x > 0.4, "each moving away from the other")
	_end_world()

	_begin_world()
	var pusher := _make_character(Vector3(0.0, 0.05, 0.0), true)
	var stander := _make_character(Vector3(0.5, 0.05, 0.0), false)
	await _ticks(60)
	var sideways := Vector2(stander.get_body().global_position.x - 0.5, stander.get_body().global_position.z).length()
	_check(sideways < 0.001, "one without the node is never moved sideways (%.4f m)" % sideways)
	_check(pusher.get_body().global_position.distance_to(stander.get_body().global_position) > 0.78, "and the one with it makes the room itself")
	_end_world()

	# Walking into each other head on, they block each other a little instead of passing through.
	_begin_world()
	first = _make_character(Vector3(-3.0, 0.05, 0.0), true)
	second = _make_character(Vector3(3.0, 0.05, 0.0), true)
	await _ticks(30)
	first.move = Vector2(1.0, 0.0)
	second.move = Vector2(-1.0, 0.0)
	await _ticks(150)
	var gap := second.get_body().global_position.x - first.get_body().global_position.x
	_check(gap > 0.55, "two walking head on do not pass through one another (%.2f m apart, touching is 0.80)" % gap)
	_end_world()

	# The push never drives a character through a wall.
	_begin_world()
	_add_static(Vector3(0.4, 1.5, 0.0), Vector3(0.2, 3.0, 20.0), PhysicsLayers.WORLD)
	first = _make_character(Vector3(0.0, 0.05, 0.0), true)
	second = _make_character(Vector3(-0.3, 0.05, 0.0), true)
	await _ticks(90)
	_check(first.get_body().global_position.x < 0.31, "pushed against a wall, it is still stopped by it (x=%.2f, the wall is at 0.30)" % first.get_body().global_position.x)
	_end_world()


## Ground only: nothing is lifted or driven into the floor, and a hop over something is not an overlap.
func _test_level() -> void:
	_begin_world()
	var item := _make_item(Vector3(0.0, 0.26, 0.0), Vector3.ONE * 0.5, 5.0, true)
	var soft := item.get_node("SoftCollision3D") as SoftCollision3D
	await _ticks(30)
	# A slab over the item, catching the top of it by 5 cm. Each look is made on the tick the thing
	# appears (a body that is added is in the physics world at once), before the item can move.
	var slab := _add_static(Vector3(0.0, 0.5 - 0.05 + 0.25, 0.0), Vector3(1.0, 0.5, 1.0), PhysicsLayers.PLAYERS)
	_check(soft.find_contacts().is_empty(), "something only clipping the top of an item is left alone")
	soft.ground_only = false
	_check(soft.compute_push().y < -0.5, "where the push may go any way it is pushed down (%s)" % soft.compute_push().snapped(Vector3.ONE * 0.01))
	soft.ground_only = true
	slab.free()
	# A post beside it, 6 cm inside it from the side.
	var post := _add_static(Vector3(0.25 + 0.2 - 0.06, 1.0, 0.0), Vector3(0.4, 2.0, 0.4), PhysicsLayers.PLAYERS)
	var push := soft.compute_push()
	_check(push.x < -1.0 and absf(push.y) < 0.001, "something overlapping from the side pushes it sideways only (%s)" % push.snapped(Vector3.ONE * 0.01))
	_end_world()

	# With no gravity there is no up, so it goes any way.
	_begin_world(false)
	item = _make_item(Vector3(0.0, 0.26, 0.0), Vector3.ONE * 0.5, 5.0, true)
	item.gravity_scale = 0.0
	soft = item.get_node("SoftCollision3D") as SoftCollision3D
	await _ticks(2)
	slab = _add_static(Vector3(0.0, 0.5 - 0.05 + 0.25, 0.0), Vector3(1.0, 0.5, 1.0), PhysicsLayers.PLAYERS)
	_check(soft.compute_push().y < -0.5, "in zero gravity an overlap from above pushes it down (%s)" % soft.compute_push().snapped(Vector3.ONE * 0.01))
	_end_world()


## The margin is a soft skin, not overlap.
func _test_margin() -> void:
	_begin_world()
	var item := _make_item(Vector3(0.0, 0.26, 0.0), Vector3.ONE * 0.5, 5.0, true)
	var soft := item.get_node("SoftCollision3D") as SoftCollision3D
	await _ticks(30)
	var post := _add_static(Vector3(0.25 + 0.2 + 0.02, 1.0, 0.0), Vector3(0.4, 2.0, 0.4), PhysicsLayers.PLAYERS)
	var contacts := soft.find_contacts()
	_check(contacts.size() == 1 and contacts[0].overlap < 0.001, "something 2 cm away is seen, inside the margin, but is not an overlap")
	_check(soft.compute_push().length() < 0.001, "so an item is not pushed away from it (%s)" % soft.compute_push())
	post.position.x = 0.25 + 0.2 - 0.03
	await _ticks(1)
	contacts = soft.find_contacts()
	_check(contacts.size() == 1 and absf(contacts[0].overlap - 0.03) < 0.005, "3 cm inside is 3 cm of overlap (%.3f)" % (contacts[0].overlap if contacts.size() == 1 else -1.0))
	_check(absf(soft.compute_push().length() - 0.03 * soft.strength) < 0.1, "and is pushed at strength times that (%.2f m/s)" % soft.compute_push().length())
	soft.margin = 0.0
	post.position.x = 0.25 + 0.2 + 0.02
	await _ticks(1)
	_check(soft.find_contacts().is_empty(), "with no margin something 2 cm away is not seen at all")
	_end_world()


## What the node does to the body it is on when it starts.
func _test_defaults() -> void:
	_begin_world()
	var item := _make_item(Vector3(0.0, 0.3, 0.0), Vector3.ONE * 0.5, 5.0, true)
	_check(item.collision_mask & PhysicsLayers.CHARACTERS == 0, "it stops the body colliding hard with the layers it pushes away from (mask %d)" % item.collision_mask)
	_check(item.collision_mask & PhysicsLayers.WORLD != 0, "and leaves the rest of its mask alone")
	_check(item.get_node("SoftCollision3D").body == item, "it finds its body above it")
	var hard := _make_item(Vector3(2.0, 0.3, 0.0), Vector3.ONE * 0.5, 5.0, false)
	_check(hard.collision_mask & PhysicsLayers.CHARACTERS != 0, "an item without it keeps colliding hard")
	var kept := RigidBody3D.new()
	kept.collision_mask = PhysicsLayers.ITEM_MASK
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	kept.add_child(shape)
	var soft := SoftCollision3D.new()
	soft.replace_hard_collision = false
	kept.add_child(soft)
	_world.add_child(kept)
	_check(kept.collision_mask == PhysicsLayers.ITEM_MASK, "unless it is told not to touch the mask")
	_check(not soft._get_configuration_warnings().is_empty(), "and then the editor warns that the two will fight")
	_end_world()


## Off switches.
func _test_switches() -> void:
	_begin_world()
	var item := _make_item(Vector3(0.0, 0.26, 0.0), Vector3.ONE * 0.5, 5.0, true)
	var soft := item.get_node("SoftCollision3D") as SoftCollision3D
	await _ticks(30)
	# A post on the Players layer, 3 cm inside it, looked at on the tick it appears.
	_add_static(Vector3(0.25 + 0.2 - 0.03, 1.0, 0.0), Vector3(0.4, 2.0, 0.4), PhysicsLayers.PLAYERS)
	_check(not soft.find_contacts().is_empty(), "something overlapping is found")
	soft.enabled = false
	_check(soft.find_contacts().is_empty() and soft.compute_push() == Vector3.ZERO, "disabled, nothing is found or pushed")
	soft.enabled = true
	soft.push_mask = PhysicsLayers.CREATURES
	_check(soft.find_contacts().is_empty(), "layers that are not in the mask are ignored")
	soft.push_mask = PhysicsLayers.PLAYERS
	_check(not soft.find_contacts().is_empty(), "and ones that are are found")
	soft.push_mask = 0
	_check(soft.find_contacts().is_empty(), "an empty mask finds nothing")
	_end_world()

	# Only the peer that owns a body moves it.
	_begin_world()
	var owned := _make_item(Vector3(0.0, 0.3, 0.0), Vector3.ONE * 0.5, 5.0, true)
	var foreign := _make_item(Vector3(5.0, 0.3, 0.0), Vector3.ONE * 0.5, 5.0, true)
	foreign.set_multiplayer_authority(2)
	_make_character(Vector3(0.0, 0.05, 0.0))
	_make_character(Vector3(5.0, 0.05, 0.0))
	await _ticks(45)
	var owned_moved := Vector2(owned.global_position.x, owned.global_position.z).length()
	var foreign_moved := Vector2(foreign.global_position.x - 5.0, foreign.global_position.z).length()
	_check(owned_moved > 0.3, "an item this peer owns gets out of the way (%.2f m)" % owned_moved)
	_check(foreign_moved < 0.01, "one another peer owns is left to that peer (%.3f m)" % foreign_moved)
	_end_world()


## A body fastened to this one (an item held in a hand) is never pushed away from.
func _test_family() -> void:
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0))
	var held := RigidBody3D.new()
	held.collision_layer = PhysicsLayers.ITEMS
	held.collision_mask = PhysicsLayers.ITEM_MASK
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	held.add_child(shape)
	var soft := SoftCollision3D.new()
	held.add_child(soft)
	walker.get_body().add_child(held)
	held.position = Vector3(0.0, 1.0, 0.0)
	await _ticks(2)
	_check(soft.find_contacts().is_empty(), "something carried by the body it overlaps does not push itself away from it")
	_end_world()


## While pushed an item has little friction, and all of it again soon after.
func _test_friction() -> void:
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0))
	var item := _make_item(Vector3(0.0, 0.3, -2.0), Vector3.ONE * 0.5, 5.0, true)
	await _ticks(30)
	var normal: float = PhysicsServer3D.body_get_param(item.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION)
	walker.move = Vector2(0.0, -1.0)
	await _ticks(60)
	var pushed: float = PhysicsServer3D.body_get_param(item.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION)
	_check(pushed < normal * 0.5, "while pushed it has little friction (%.2f of %.2f)" % [pushed, normal])
	_check(item.continuous_cd, "and is checked for hitting things all the way along")
	walker.move = Vector2.ZERO
	await _ticks(120)
	var after: float = PhysicsServer3D.body_get_param(item.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION)
	_check(is_equal_approx(after, normal), "all of it is back once it is left alone (%.2f)" % after)
	_check(not item.continuous_cd, "and so is the rest of how it was")
	_check(item.linear_velocity.length() < 0.05, "and it comes to rest (%.2f m/s)" % item.linear_velocity.length())
	_end_world()


## A character body of any kind will do, not only one with a CharacterController.
func _test_no_controller() -> void:
	_begin_world()
	var body := CharacterBody3D.new()
	body.collision_layer = PhysicsLayers.CREATURES
	body.collision_mask = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	var soft := SoftCollision3D.new()
	soft.push_mask = PhysicsLayers.PLAYERS
	body.add_child(soft)
	body.position = Vector3(0.0, 0.05, 0.0)
	_world.add_child(body)
	# A fixed post that overlaps it, standing in for anything on the Players layer.
	_add_static(Vector3(0.55, 1.0, 0.0), Vector3(0.4, 2.0, 0.4), PhysicsLayers.PLAYERS)
	await _ticks(60)
	_check(body.global_position.x < -0.04, "a plain CharacterBody3D with the node moves itself away on its own, the 5 cm it overlaps (x=%.3f)" % body.global_position.x)
	_end_world()

	# With a controller, the controller runs it, and it does not run twice.
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0), true)
	await _ticks(2)
	_check(walker.soft_collision != null and walker.soft_collision._driven_by_controller, "a CharacterController finds the node and runs it itself")
	_end_world()


## An item that ends up inside a player is not stuck there.
func _test_engulfed() -> void:
	_begin_world()
	var walker := _make_character(Vector3(0.0, 0.05, 0.0))
	await _ticks(10)
	var item := _make_item(Vector3(0.05, 0.3, 0.0), Vector3.ONE * 0.5, 5.0, true)
	await _ticks(60)
	var apart := Vector2(item.global_position.x, item.global_position.z).distance_to(Vector2(walker.get_body().global_position.x, walker.get_body().global_position.z))
	_check(apart > 0.6, "an item dropped right inside a player works its way out sideways (%.2f m from them)" % apart)
	_check(absf(item.global_position.y - 0.25) < 0.05, "along the floor, not into it or up (y=%.2f)" % item.global_position.y)
	_end_world()


## With the real player scene.
func _test_player_scene() -> void:
	_begin_world()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	_world.add_child(player)
	var item := _make_item(Vector3(0.0, 0.3, -2.0), Vector3.ONE * 0.5, 5.0, true)
	await _ticks(60)
	var start := item.global_position
	Input.action_press(&"move_forward")
	await _ticks(90)
	Input.action_release(&"move_forward")
	_check(-player.global_position.z > 5.5, "the real player walks at full pace through it (%.2f m in 1.5 s)" % -player.global_position.z)
	_check(start.distance_to(item.global_position) > 1.5, "and the item is shoved ahead of them (%.2f m)" % start.distance_to(item.global_position))
	_check(rad_to_deg(item.global_basis.y.angle_to(Vector3.UP)) < 5.0, "upright")
	_end_world()

	# Players that carry the node push each other, with nothing but a node added to the scene.
	_begin_world()
	var first := PLAYER_SCENE.instantiate() as CharacterBody3D
	var second := PLAYER_SCENE.instantiate() as CharacterBody3D
	for player_body in [first, second]:
		var soft := SoftCollision3D.new()
		soft.push_mask = PhysicsLayers.PLAYERS
		player_body.add_child(soft)
	first.position = Vector3(0.0, 0.05, 0.0)
	second.position = Vector3(0.3, 0.05, 0.0)
	_world.add_child(first)
	_world.add_child(second)
	await _ticks(90)
	var distance := first.global_position.distance_to(second.global_position)
	_check(distance > 0.77, "two real players standing inside each other get apart (%.2f m, touching is 0.80)" % distance)
	_end_world()


## Inside a ship that is moving, the push and the carry do not disturb each other.
func _test_ship() -> void:
	_begin_world(false)
	var mule := MULE_SCENE.instantiate() as Mule
	_world.add_child(mule)
	var walker := _make_character(mule.to_global(Vector3(0.0, 0.1, 1.5)))
	var crate := _make_item(mule.to_global(Vector3(0.5, 0.3, 1.5)), Vector3.ONE * 0.5, 20.0, true)
	await _ticks(90)
	var crate_at := mule.to_local(crate.global_position)
	var player_at := mule.to_local(walker.get_body().global_position)
	_check(crate_at.distance_to(Vector3(0.5, 0.3, 1.5)) > 0.02, "a crate the player was standing inside got out of the way (%.2f m)" % crate_at.distance_to(Vector3(0.5, 0.3, 1.5)))
	mule.linear_velocity = Vector3(8.0, 0.0, 3.0)
	mule.angular_velocity = Vector3(0.0, 0.3, 0.0)
	var crate_worst := 0.0
	var player_worst := 0.0
	for tick in 180:
		await physics_frame
		await get_tree().process_frame
		crate_worst = maxf(crate_worst, mule.to_local(crate.global_position).distance_to(crate_at))
		player_worst = maxf(player_worst, mule.to_local(walker.get_body().global_position).distance_to(player_at))
	_check(crate_worst < 0.03, "while the ship flies and turns the crate stays where it was in it (%.1f cm)" % (crate_worst * 100.0))
	_check(player_worst < 0.03, "and so does the player (%.1f cm)" % (player_worst * 100.0))
	_end_world()


## What it costs, for the record: items at rest, which is nearly all of them nearly all of the time.
func _test_cost() -> void:
	for soft in [false, true]:
		_begin_world()
		for index in 200:
			_make_item(Vector3(float(index % 20) * 2.0 - 20.0, 0.3, float(index / 20) * 2.0 - 10.0), Vector3.ONE * 0.5, 5.0, soft)
		await _ticks(120)
		var start := Time.get_ticks_usec()
		await _ticks(120)
		var per_tick := float(Time.get_ticks_usec() - start) / 120.0 / 1000.0
		print("  info 200 items at rest %s: %.2f ms per tick" % ["with the node" if soft else "without it", per_tick])
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


func _begin_world(with_gravity := true) -> void:
	_world = Node3D.new()
	_world.name = "TestWorld"
	add_child(_world)
	if with_gravity:
		var field := DirectionalGravityField3D.new()
		var field_shape := CollisionShape3D.new()
		var field_box := BoxShape3D.new()
		field_box.size = Vector3(300.0, 300.0, 300.0)
		field_shape.shape = field_box
		field_shape.position = Vector3(0.0, 100.0, 0.0)
		field.add_child(field_shape)
		_world.add_child(field)
		_add_static(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0), PhysicsLayers.WORLD)


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


## A loose item, as the project makes them (Items layer, Item mask), with the node unless [param soft] is off.
func _make_item(center: Vector3, size: Vector3, mass: float, soft: bool, shape: Shape3D = null) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = PhysicsLayers.ITEMS
	body.collision_mask = PhysicsLayers.ITEM_MASK
	body.mass = mass
	var collision := CollisionShape3D.new()
	if shape == null:
		var box := BoxShape3D.new()
		box.size = size
		shape = box
	collision.shape = shape
	body.add_child(collision)
	if soft:
		var node := SoftCollision3D.new()
		node.name = "SoftCollision3D"
		body.add_child(node)
	body.position = center
	_world.add_child(body)
	return body


## A character the way the project makes players, walked by a real controller. With the node when
## [param soft] is on, pushing away from other players.
func _make_character(position: Vector3, soft := false) -> Walker:
	var body := TestCharacter.make()
	if soft:
		var node := SoftCollision3D.new()
		node.push_mask = PhysicsLayers.PLAYERS
		body.add_child(node)
	var walker := Walker.new()
	body.add_child(walker)
	body.position = position
	_world.add_child(body)
	return walker
