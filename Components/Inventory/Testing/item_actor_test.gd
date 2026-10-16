extends Node
## Headless checks for the item system: an item's one scene in the world and in hands, who it listens
## to, dropping and picking up with the state kept, and the same light in first and third person.
##
## godot --headless --fixed-fps 60 --path . res://Components/Inventory/Testing/ItemActorTest.tscn
## ONLY=<name> runs one test, such as ONLY=drop.

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const FLASHLIGHT: Item = preload("res://Game/Registry/Items/Flashlight/flashlight_item.tres")
const FLASHLIGHT_SCENE := preload("res://Game/Registry/Items/Flashlight/Flashlight.tscn")
const WORLD_ITEM_SCENE := preload("res://Components/Inventory/Item/WorldItem.tscn")

const FIRST := ItemActor.Presence.FIRST_PERSON
const THIRD := ItemActor.Presence.THIRD_PERSON

var _failures := 0


## An item that only counts what it is told, to see which events reach it.
class ProbeActor extends ItemActor:
	var unhandled := 0
	var raw := 0
	var carried := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"primary_action"):
			unhandled += 1

	func _input(event: InputEvent) -> void:
		if event.is_action_pressed(&"primary_action"):
			raw += 1

	func _carried_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"primary_action"):
			carried += 1


## Records where the held item is in the camera's eyes and in the world, after ItemMotion has run.
class MotionRecorder extends Node:
	var camera: Camera3D
	var mount: Node3D
	var camera_y: Array[float] = []
	var item_world_y: Array[float] = []
	var item_in_view: Array[Vector3] = []

	func _init() -> void:
		process_priority = 100

	func _process(_delta: float) -> void:
		camera_y.append(camera.global_position.y)
		item_world_y.append(mount.global_position.y)
		item_in_view.append(camera.global_transform.affine_inverse() * mount.global_position)

	func clear() -> void:
		camera_y.clear()
		item_world_y.clear()
		item_in_view.clear()


func _ready() -> void:
	_run()


## An item that counts the input it is given. It has an instance, like any real actor.
func _probe() -> ProbeActor:
	var probe := ProbeActor.new()
	probe.setup(FLASHLIGHT.create_instance())
	return probe


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in [
		"registry", "scene", "presence", "input", "flashlight", "drop", "pickup", "walls", "views",
		"player_flow", "level", "carried", "carried_input", "player_carried", "motion",
		"ladder_and_seats", "world_toggle", "seat_motion", "drop_next", "held_shadow",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Item actor tests passed.")
	else:
		print("Item actor tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_registry() -> void:
	ItemRegistry.clear()
	_check(ItemRegistry.get_item(&"flashlight") == FLASHLIGHT, "an item is found by its id")
	_check(ItemRegistry.get_item(&"nothing") == null, "an unknown id finds nothing")
	_check(ItemRegistry.get_items().has(FLASHLIGHT), "and every item can be listed")


func _test_scene() -> void:
	var actor := FLASHLIGHT_SCENE.instantiate() as FlashlightActor
	_check(actor != null, "the flashlight scene's root is a FlashlightActor, which is an ItemActor")
	_check(actor.item_id == &"flashlight", "that says which item it is")
	for path in ["CollisionShape3D", "InteractableObject3D", "SoftCollision3D", "Light", "Body", "Head", "Lightmesh"]:
		_check(actor.has_node(path), "it has %s" % path)
	_check(actor.get_node("InteractableObject3D") is ItemPickup, "its prompt is a pickup")
	_check(actor.collision_layer == PhysicsLayers.ITEMS, "it is on the items layer")
	_check(actor.collision_mask & PhysicsLayers.WORLD != 0 and actor.collision_mask & PhysicsLayers.PLAYERS == 0, "it collides with the world, and the players push it softly instead")
	add_child(actor)
	_check(actor.presence == ItemActor.Presence.WORLD and actor.is_in_world() and not actor.is_held(), "placed in a level it is an item in the world")
	_check(actor.item_instance is FlashlightInstance and actor.item == FLASHLIGHT, "which made its own flashlight")
	_check((actor.item_instance as FlashlightInstance).power_level == 100.0 and not actor.is_on, "fully charged and off")
	_check(not actor.freeze and actor.has_node("CollisionShape3D"), "and a real body, left as authored")

	# A placed item can be given its own starting state, and every copy gets a copy of it.
	var worn := FlashlightInstance.new()
	worn.item = FLASHLIGHT
	worn.power_level = 40.0
	worn.is_on = true
	var first := FLASHLIGHT_SCENE.instantiate() as FlashlightActor
	first.starting_instance = worn
	var second := FLASHLIGHT_SCENE.instantiate() as FlashlightActor
	second.starting_instance = worn
	add_child(first)
	add_child(second)
	var first_state := first.item_instance as FlashlightInstance
	var second_state := second.item_instance as FlashlightInstance
	_check(first_state != second_state and first_state != worn, "each placed copy has an instance of its own")
	_check(first_state.power_level == 40.0 and first_state.is_on and first.light.visible, "that starts as the state it was given")
	first_state.power_level = 10.0
	_check(second_state.power_level == 40.0 and worn.power_level == 40.0, "and changing one changes no other")
	first.free()
	second.free()
	actor.free()


func _test_presence() -> void:
	var rig := _make_rig(4)
	var holder: ItemHolder = rig["holder"]
	var instance := FLASHLIGHT.create_instance()

	var world := FLASHLIGHT.create_actor(instance)
	add_child(world)
	_check(world.has_node("CollisionShape3D") and world.has_node("InteractableObject3D"), "an item in the world keeps its body and its prompt")
	_check(_clipped(world) == [false, false, false], "and is drawn like anything else")
	var shared_material := (world.get_node("Body") as MeshInstance3D).get_active_material(0)
	world.free()

	var first := FLASHLIGHT.create_actor(instance)
	first.set_held(holder, FIRST)
	_check(first.holder == holder and first.is_held() and first.is_first_person() and first.is_held_locally(), "held in first person it knows who holds it")
	_check(not first.has_node("CollisionShape3D") and not first.has_node("InteractableObject3D") and not first.has_node("SoftCollision3D"), "the parts that belong to the world are gone before it enters the tree")
	_check(first.has_node("Light") and first.has_node("Body"), "and the rest stays")
	_check(first.freeze and first.collision_layer == 0 and first.collision_mask == 0, "its body is switched off")
	_check(_clipped(first) == [true, true, true], "in first person every mesh is drawn clear of walls")
	var body_material := (first.get_node("Body") as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	var head_material := (first.get_node("Head") as MeshInstance3D).get_active_material(0)
	_check(body_material != shared_material, "with copies of its materials")
	_check(body_material == head_material, "so the parts that shared one still share one")
	_check(is_equal_approx(body_material.z_clip_scale, first.first_person_clip_scale) and body_material.use_fov_override and is_equal_approx(body_material.fov_override, first.first_person_fov), "set to its own clip scale and field of view")
	var lens_material := (first.get_node("Lightmesh") as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	_check(lens_material.emission_enabled and is_equal_approx(lens_material.emission_energy_multiplier, 10.0), "and otherwise as they were: the lens still glows")
	var fresh := FLASHLIGHT.create_actor(instance)
	add_child(fresh)
	_check(_clipped(fresh) == [false, false, false] and (fresh.get_node("Body") as MeshInstance3D).get_active_material(0) == shared_material, "the scene's own materials are not touched: the next item in the world is as it was")
	fresh.free()
	first.free()

	var third := FLASHLIGHT.create_actor(instance)
	third.set_held(holder, THIRD)
	_check(third.is_third_person() and third.is_held() and not third.is_held_locally(), "held in third person it is held, but not locally")
	_check(not third.has_node("CollisionShape3D") and third.freeze, "it is as inert as the first person one")
	_check(_clipped(third) == [false, false, false], "and drawn like anything else")
	third.free()

	# Parts for some presences go in groups, and the others are freed.
	var made := {}
	for presence: ItemActor.Presence in [ItemActor.Presence.WORLD, FIRST, THIRD, ItemActor.Presence.CARRIED]:
		var actor := ItemActor.new()
		actor.setup(instance)
		actor.first_person_offset = Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
		actor.third_person_offset = Transform3D(Basis.IDENTITY, Vector3(4, 5, 6))
		actor.carried_offset = Transform3D(Basis.IDENTITY, Vector3(7, 8, 9))
		for tag in [
			["plain", []],
			["world", [ItemActor.GROUP_WORLD]],
			["first", [ItemActor.GROUP_FIRST_PERSON]],
			["third", [ItemActor.GROUP_THIRD_PERSON]],
			["held", [ItemActor.GROUP_FIRST_PERSON, ItemActor.GROUP_THIRD_PERSON]],
			["carried", [ItemActor.GROUP_CARRIED]],
			["always", [ItemActor.GROUP_ALWAYS]],
			["holder", []],
		]:
			var part := Node3D.new()
			part.name = tag[0]
			for group: StringName in tag[1]:
				part.add_to_group(group)
			actor.add_child(part)
		var nested := Node3D.new()
		nested.name = "nested"
		nested.add_to_group(ItemActor.GROUP_THIRD_PERSON)
		actor.get_node("plain").add_child(nested)
		# A plain node that holds a part for carrying has to stay for the part to hang from.
		var lamp := Node3D.new()
		lamp.name = "lamp"
		lamp.add_to_group(ItemActor.GROUP_CARRIED)
		actor.get_node("holder").add_child(lamp)
		var other := Node3D.new()
		other.name = "other"
		actor.get_node("holder").add_child(other)
		if presence == ItemActor.Presence.CARRIED:
			actor.set_carried(holder)
		elif presence != ItemActor.Presence.WORLD:
			actor.set_held(holder, presence)
		var mount := rig["mount"] as Node3D
		mount.add_child(actor)
		var kept := []
		for child in actor.get_children():
			kept.append(String(child.name))
		kept.sort()
		made[presence] = {
			"kept": kept,
			"nested": actor.has_node("plain/nested"),
			"origin": actor.transform.origin,
			"lamp": actor.has_node("holder/lamp"),
			"other": actor.has_node("holder/other"),
		}
		actor.free()
	var in_pocket: ItemActor.Presence = ItemActor.Presence.CARRIED
	_check(made[ItemActor.Presence.WORLD]["kept"] == ["always", "holder", "plain", "world"], "in the world it keeps what is plain, for the world or for always: %s" % [made[ItemActor.Presence.WORLD]["kept"]])
	_check(made[FIRST]["kept"] == ["always", "first", "held", "holder", "plain"], "in first person, what is plain or for the first person, held or always: %s" % [made[FIRST]["kept"]])
	_check(made[THIRD]["kept"] == ["always", "held", "holder", "plain", "third"] and made[THIRD]["nested"], "in third person, what is plain or for the third person, even deeper in: %s" % [made[THIRD]["kept"]])
	_check(not made[FIRST]["nested"], "and a part is only freed for its own tag")
	_check(made[FIRST]["origin"] == Vector3(1, 2, 3) and made[THIRD]["origin"] == Vector3(4, 5, 6), "a held item sits in its hand where its own offset says")
	_check(made[in_pocket]["kept"] == ["always", "carried", "holder"], "in a pocket, nothing but what is for carrying or always, and what holds it: %s" % [made[in_pocket]["kept"]])
	_check(made[in_pocket]["lamp"] and not made[in_pocket]["other"], "a part for carrying stays and its plain neighbours go")
	_check(made[in_pocket]["origin"] == Vector3(7, 8, 9), "it sits on the body where its carried offset says")
	_check(not made[ItemActor.Presence.WORLD]["lamp"] and not made[FIRST]["lamp"] and not made[THIRD]["lamp"], "and a part for carrying is nowhere else")
	_end_rig(rig)


func _test_input() -> void:
	var rig := _make_rig(4)
	var holder: ItemHolder = rig["holder"]
	var mount: Node3D = rig["mount"]

	var world := _probe()
	mount.add_child(world)
	await _press(&"primary_action")
	_check(world.unhandled == 0 and world.raw == 0, "an item in the world reads no input")
	world.free()

	var first := _probe()
	first.set_held(holder, FIRST)
	mount.add_child(first)
	await _press(&"primary_action")
	_check(first.unhandled == 1 and first.raw == 1, "an item held in first person reads input in _unhandled_input and _input")
	_check(first.can_use_input(), "and says it can")

	holder.can_use_items.add(1, "stunned")
	await _press(&"primary_action")
	_check(first.unhandled == 1 and first.raw == 1 and not first.can_use_input(), "not while the holder is blocked")
	holder.can_use_items.remove(1)
	await _press(&"primary_action")
	_check(first.unhandled == 2 and first.raw == 2, "and again once it is not")

	first.release()
	await _press(&"primary_action")
	_check(first.unhandled == 2 and first.raw == 2 and not first.is_held() and first.holder == null, "once it is let go it reads nothing, at once")
	first.free()

	var third := _probe()
	third.set_held(holder, THIRD)
	mount.add_child(third)
	await _press(&"primary_action")
	_check(third.unhandled == 0 and third.raw == 0, "an item held by somebody else reads no input")
	third.free()

	# The flashlight is written the same way: it toggles itself, and only for the player holding it.
	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	var lying := FLASHLIGHT.create_actor(light) as FlashlightActor
	add_child(lying)
	await _press(&"primary_action")
	_check(not light.is_on, "a flashlight on the ground ignores the primary action")
	lying.free()
	var watched := FLASHLIGHT.create_actor(light) as FlashlightActor
	watched.set_held(holder, THIRD)
	mount.add_child(watched)
	await _press(&"primary_action")
	_check(not light.is_on, "so does one in somebody else's hand")
	watched.free()
	var mine := FLASHLIGHT.create_actor(light) as FlashlightActor
	mine.set_held(holder, FIRST)
	mount.add_child(mine)
	await _press(&"primary_action")
	_check(light.is_on and mine.light.visible, "one in your own hand switches on with it")
	await _press(&"primary_action")
	_check(not light.is_on and not mine.light.visible, "and off with it")
	mine.free()
	_end_rig(rig)


func _test_flashlight() -> void:
	var rig := _make_rig(4)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	hotbar.add(light)
	holder.equip_item(light)
	var actor := holder.equipped_actor as FlashlightActor
	_check(not actor.light.visible and not actor.lens.visible and not actor.is_on, "a flashlight starts dark: no beam, and no glow on the lens")
	var toggles := []
	actor.toggled.connect(func(on: bool) -> void: toggles.append(on))
	actor.toggle()
	_check(light.is_on and actor.is_on and actor.light.visible and actor.lens.visible and toggles == [true], "switched on, it lights up and says so")

	actor.power_drain_per_second = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(light.power_level < 100.0 and absf(light.power_level - 97.0) < 1.5, "a lit flashlight drains its battery: %.1f" % light.power_level)
	var before := light.power_level
	actor.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not light.is_on and is_equal_approx(light.power_level, before), "and an unlit one does not")

	light.power_level = 1.0
	actor.toggle()
	_check(light.is_on, "with a little power left it can be lit")
	for i in 4:
		await get_tree().process_frame
	_check(light.power_level == 0.0 and not light.is_on and not actor.light.visible, "and the battery running out puts it out")
	actor.toggle()
	_check(not light.is_on, "with no power it cannot be lit")

	light.power_level = 50.0
	actor.toggle()
	_check(light.is_on, "charged again, it lights")
	holder.unequip_item()
	_check(light.is_on and light.power_level == 50.0, "put away it is left as it was: still lit, with its battery (a pocket that carries items keeps the beam)")
	_end_rig(rig)


func _test_drop() -> void:
	var rig := _make_rig(4)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var inventory: Inventory = rig["inventory"]
	var eye: Node3D = rig["eye"]
	holder.drop_parent = self
	# What was dropped, and where it appeared (it starts moving at once).
	var dropped := []
	holder.item_dropped.connect(func(instance: ItemInstance, actor: ItemActor) -> void: dropped.append([instance, actor, actor.global_position, actor.linear_velocity]))
	var unequipped := []
	holder.item_unequipped.connect(func(instance: ItemInstance) -> void: unequipped.append(instance))

	_check(holder.drop_equipped_item() == null, "with nothing in hand nothing is dropped")
	await _press(&"drop_item")
	_check(dropped.is_empty(), "and the drop key does nothing")

	# An item is only thrown by someone gravity pulls on. In space it is let go of and stays put.
	var light_in_space := FLASHLIGHT.create_instance()
	hotbar.add(light_in_space)
	holder.equip_item(light_in_space)
	holder.drop_equipped_item()
	_check(dropped.size() == 1 and (dropped[0][3] as Vector3).length() < 0.001, "with no gravity a dropped item is let go, not thrown: %s" % dropped[0][3])
	(dropped[0][1] as ItemActor).free()
	dropped.clear()
	unequipped.clear()

	var gravity := DirectionalGravityField3D.new()
	var gravity_shape := CollisionShape3D.new()
	var gravity_box := BoxShape3D.new()
	gravity_box.size = Vector3(100, 100, 100)
	gravity_shape.shape = gravity_box
	gravity.add_child(gravity_shape)
	add_child(gravity)
	await _frames(3)
	_check((rig["body"] as CharacterBody3D).get_gravity().length() > 1.0, "(the holder now stands in a gravity field)")

	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	light.power_level = 10.0
	hotbar.add(light)
	holder.equip_item(light)
	(holder.equipped_actor as FlashlightActor).toggle()
	_check(light.is_on, "a flashlight at 10% is switched on in hand")
	var held_actor := holder.equipped_actor
	var hand_position := held_actor.global_position
	await _press(&"drop_item")
	_check(not holder.has_equipped_item() and holder.equipped_instance == null, "the drop key empties the hand")
	_check(not inventory.has_instance(light), "the item leaves the inventory")
	_check(dropped.size() == 1 and dropped[0][0] == light and unequipped == [light], "and it is announced")
	var world: FlashlightActor = dropped[0][1]
	_check(world != null and world.is_in_world() and world.is_inside_tree() and world.get_parent() == self, "it appears in the world")
	_check(world.item_instance == light, "as the very same instance, not a copy")
	# (A lit flashlight drains a little in the frames it takes to press the key.)
	_check(world.item_instance is FlashlightInstance and absf(light.power_level - 10.0) < 0.3 and light.is_on, "with the 10% battery and still on")
	_check(world.light.visible and world.lens.visible, "and its light shining")
	_check((dropped[0][2] as Vector3).distance_to(hand_position) < 0.001, "from where the hand was")
	_check((dropped[0][3] as Vector3).distance_to(Vector3(0, 0, -holder.drop_speed)) < 0.05, "thrown forward, the way the holder looks: %s" % dropped[0][3])
	await get_tree().process_frame
	_check(not is_instance_valid(held_actor), "and the item that was in hand is gone")
	_check(world.has_node("CollisionShape3D") and not world.freeze, "the one in the world is a real body again")

	# The same flashlight, dropped again after being picked up, remembers everything.
	_check(holder.pick_up(world), "it can be picked up again")
	await get_tree().process_frame
	_check(inventory.has_instance(light) and absf(light.power_level - 10.0) < 0.3 and light.is_on, "with its state")
	holder.unequip_item()
	_check(light.is_on, "(put away, it stays lit)")

	# Facing a wall, the item appears in front of it and not inside it.
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.position = Vector3(0, 0, -0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	holder.avoid_walls = false
	holder.equip_item(light)
	await _press(&"drop_item")
	var near_wall: ItemActor = dropped[1][1]
	_check(near_wall != null and (dropped[1][2] as Vector3).z > -0.4, "with a wall in the way it lands in front of it: %.2f" % (dropped[1][2] as Vector3).z)
	wall.free()
	gravity.free()
	_end_rig(rig)


func _test_pickup() -> void:
	var rig := _make_rig(2)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var inventory: Inventory = rig["inventory"]
	var body: Node3D = rig["body"]
	var picked := []
	holder.item_picked_up.connect(func(instance: ItemInstance) -> void: picked.append(instance))

	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	light.power_level = 33.0
	light.is_on = true
	var world := FLASHLIGHT.spawn_in_world(light, self, Transform3D(Basis.IDENTITY, Vector3(0, 0, -3)))
	_check(world != null and world.is_inside_tree() and world.light.visible, "an item can be put into the world with its state")
	var pickup := world.get_node("InteractableObject3D") as ItemPickup
	_check(pickup.can_interact(body, 0), "a player with room can pick it up")
	_check(pickup.interact(body, 0), "interacting does it")
	_check(inventory.has_instance(light) and hotbar.get_slot_of(light) == 0, "it goes to the first free slot")
	_check(picked == [light] and not world.visible, "it is announced, and gone from the world at once")
	_check(holder.equipped_instance == light and holder.has_equipped_item(), "and into hand, because the hand was empty")
	_check(light.power_level == 33.0 and light.is_on, "with its state")
	await get_tree().process_frame
	_check(not is_instance_valid(world), "the item that lay in the world is gone")
	_check((holder.equipped_actor as FlashlightActor).light.visible, "and the light is still on in hand")

	# The hand is full, so the next one goes to a slot and stays there.
	var second := FLASHLIGHT.create_instance()
	var other := FLASHLIGHT.spawn_in_world(second, self, Transform3D(Basis.IDENTITY, Vector3(0, 0, -3)))
	_check(holder.pick_up(other) and holder.equipped_instance == light and hotbar.get_slot_of(second) == 1, "picking up with a full hand leaves the hand alone")

	# No room: the item stays and its prompt is not offered.
	var third := FLASHLIGHT.create_instance()
	var spare := FLASHLIGHT.spawn_in_world(third, self, Transform3D(Basis.IDENTITY, Vector3(0, 0, -3)))
	var spare_pickup := spare.get_node("InteractableObject3D") as ItemPickup
	_check(not holder.can_pick_up(spare) and not spare_pickup.can_interact(body, 0), "a full inventory cannot pick it up, and no prompt is shown")
	_check(not holder.pick_up(spare) and not inventory.has_instance(third) and is_instance_valid(spare), "and it stays where it is")

	# What is already in a hand is not in the world to be picked up.
	_check(not holder.can_pick_up(holder.equipped_actor), "an item in hand cannot be picked up")
	spare.free()
	other.free()
	_end_rig(rig)


func _test_walls() -> void:
	var rig := _make_rig(2)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var mount: Node3D = rig["mount"]
	var light := FLASHLIGHT.create_instance()
	hotbar.add(light)
	holder.equip_item(light)
	var actor := holder.equipped_actor as FlashlightActor
	var rest := mount.position
	await _frames(20)
	_check(mount.position.is_equal_approx(rest), "with nothing ahead the item stays where it is held")

	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 0.2)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.position = Vector3(0, 0, -0.5)
	await _frames(45)
	_check(mount.position.z > rest.z + 0.3, "a wall just ahead pulls the item back toward the holder: %.2f" % mount.position.z)
	_check(actor.global_position.distance_to(mount.global_position) < 0.001, "the held item keeps up with its mount while it moves, with no lag or shake")
	_check(actor.light.global_position.z > -0.4, "so its light starts outside the wall: %.2f" % actor.light.global_position.z)
	_check(is_equal_approx(mount.position.x, rest.x) and is_equal_approx(mount.position.y, rest.y), "it only moves straight back")

	wall.position = Vector3(0, 0, -3.0)
	await _frames(45)
	_check(mount.position.is_equal_approx(rest), "and returns when the wall is far away again")

	wall.position = Vector3(0, 0, -0.5)
	await _frames(45)
	holder.unequip_item()
	_check(mount.position.is_equal_approx(rest), "putting the item away leaves the mount where it belongs")
	wall.free()
	_end_rig(rig)


## The real Player scene: the same flashlight in the player's own hand, and as everyone else sees it.
## (Another player's holder is the same node with the view set to third person, which is what it picks
## by itself for a player at another machine.)
func _test_views() -> void:
	var player := _new_player()
	add_child(player)
	await get_tree().process_frame
	var holder := player.get_node("ItemHolder") as ItemHolder
	var pivot := player.get_node("Head/YawPivot/PitchPivot") as Node3D
	var instance := FLASHLIGHT.create_instance() as FlashlightInstance
	instance.is_on = true
	(player.get_node("Inventory") as Inventory).add(instance)

	# Aim somewhere that is not straight ahead, so a wrong mount shows.
	(player.get_node("Head/YawPivot") as Node3D).rotation.y = 0.7
	pivot.rotation.x = -0.35
	await get_tree().process_frame

	_check(holder.equip_item(instance), "the local player holds a flashlight")
	var mine := holder.equipped_actor as FlashlightActor
	_check(mine.is_first_person() and mine.get_parent() == holder.actor_parent, "in first person it is on the camera's mount")
	_check(mine.light.visible and _clipped(mine) == [true, true, true], "lit, and drawn clear of walls")
	holder.unequip_item()

	holder.view = ItemHolder.View.THIRD_PERSON
	_check(holder.display_item(instance), "the same instance shown the way other players see it")
	var theirs := holder.equipped_actor as FlashlightActor
	_check(theirs.is_third_person() and theirs.get_parent() == holder.third_person_parent, "it is on the character's mount")
	instance.is_on = true
	_check(theirs.light.visible and _clipped(theirs) == [false, false, false], "lit, and drawn like any other thing in the world")

	# Only the holder's own machine reads the keys.
	var first := _probe()
	first.set_held(holder, FIRST)
	player.add_child(first)
	var third := _probe()
	third.set_held(holder, THIRD)
	player.add_child(third)
	await _press(&"primary_action")
	_check(first.unhandled == 1 and third.unhandled == 0, "the holder's item hears the action and the one seen from outside does not")
	first.free()
	third.free()

	# The keys of the holder (number keys, drop) belong to the player at this machine, and nobody else's.
	_check(not holder.is_local() and holder.equipped_instance == instance, "a holder seen from outside is not the local player's")
	await _press(&"inventory_slot_1")
	await _press(&"drop_item")
	_check(holder.equipped_instance == instance and holder.has_equipped_item(), "so it does not react to this machine's number keys or drop key")
	var stray := FLASHLIGHT.create_actor(FLASHLIGHT.create_instance())
	_check(not holder.can_pick_up(stray), "nor pick anything up")
	stray.free()
	holder.view = ItemHolder.View.AUTO
	_check(holder.is_local() and holder.get_presence() == FIRST, "offline, an automatic holder is local and is seen in first person")
	await _press(&"inventory_slot_1")
	_check(holder.equipped_instance != instance, "and does react to the keys")
	player.free()


## The whole loop in the real Player scene with the real keys: look at a flashlight on the ground, pick
## it up (F), switch it on (primary action), drop it (Q), and find it lying there as it was left.
func _test_player_flow() -> void:
	var player := _new_player()
	add_child(player)
	var holder := player.get_node("ItemHolder") as ItemHolder
	var hotbar := (player.get_node("Inventory") as Inventory).get_container(&"hotbar") as InventorySlotContainer
	var starting := hotbar.get_instance(0)

	# A flashlight on the ground, two meters ahead of the camera and in the way of the interaction ray.
	var lying_instance := FLASHLIGHT.create_instance() as FlashlightInstance
	lying_instance.power_level = 62.0
	var lying := FLASHLIGHT.spawn_in_world(lying_instance, self, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, -1.5)))
	lying.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	lying.freeze = true
	await _frames(4)
	var ray := player.get_node("Head/YawPivot/PitchPivot/Camera3D/InteractionRayCast3D") as InteractionRayCast3D
	_check(ray.get_focused_interactable() == lying.get_node("InteractableObject3D"), "the player is looking at the flashlight on the ground")

	await _press(&"interact")
	_check(holder.equipped_instance == lying_instance and hotbar.get_slot_of(lying_instance) == 2, "F picks it up into the next free slot, and takes it in hand")
	_check(holder.equipped_actor.is_first_person() and (holder.equipped_actor as FlashlightActor).flashlight_instance == lying_instance, "in first person, as the instance it was")
	await get_tree().process_frame
	_check(not is_instance_valid(lying), "and it is no longer on the ground")
	_check(hotbar.get_instance(0) == starting, "the flashlight the player already had is where it was")

	await _press(&"primary_action")
	_check(lying_instance.is_on and (holder.equipped_actor as FlashlightActor).light.visible, "the primary action switches it on")

	await _press(&"drop_item")
	_check(holder.equipped_instance == starting and not hotbar.has_instance(lying_instance), "Q drops it, the slot is free and the next item in the hotbar is in hand")
	var dropped: FlashlightActor
	for child in get_children():
		if child is FlashlightActor and (child as FlashlightActor).item_instance == lying_instance:
			dropped = child
	_check(dropped != null and dropped.is_in_world(), "it is in the world again")
	_check(dropped != null and dropped.light.visible and lying_instance.is_on and absf(lying_instance.power_level - 62.0) < 0.5, "still on, and with about the same battery (%.1f%%)" % lying_instance.power_level)
	_check(dropped != null and dropped.global_position.z < -0.1 and absf(dropped.global_position.y - 1.35) < 0.1, "and in front of the player, where the hand was")

	await _press(&"drop_item")
	_check(holder.equipped_instance != null and holder.equipped_instance != starting, "Q again drops that too, and the next item (the battery) is in hand")
	player.free()
	if dropped != null:
		dropped.free()


## The real level: the flashlight placed in World.tscn knows what it is, can be picked up by the player
## standing in it, and what is dropped lands in the level itself.
func _test_level() -> void:
	var world := (load("res://Game/InGameSession.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await _frames(4)
	var spawner := world.get_node_or_null("ItemSpawner")
	var placed := (spawner.get_child(0) if spawner != null and spawner.get_child_count() > 0 else null) as ItemActor
	_check(placed != null, "the level has an item made by its item spawner")
	if placed == null:
		world.free()
		return
	_check(placed.is_in_world() and placed.item != null and placed.item_instance != null, "which found its item by id and made its own instance")
	_check(placed.collision_layer == PhysicsLayers.ITEMS and not placed.freeze, "and is a physical item")

	var player := world.get_node("Player")
	var holder := player.get_node("ItemHolder") as ItemHolder
	holder.view = ItemHolder.View.AUTO
	var pickup := placed.get_node("InteractableObject3D") as ItemPickup
	var instance := placed.item_instance
	_check(pickup.can_interact(player, 0), "the player in the level can pick it up")
	_check(pickup.interact(player, 0) and holder.equipped_instance == instance, "does, and holds it")
	await get_tree().process_frame
	_check(not is_instance_valid(placed), "it is gone from the ground")

	var dropped := holder.drop_equipped_item()
	_check(dropped != null and dropped.get_parent() == world, "dropped, it lands in the level itself")
	_check(dropped != null and dropped.item_instance == instance, "as the same item")
	world.free()


## Items carried on the body and not in hand: the actor that is there for them, when, and what happens
## to it as the item goes from a pocket to a hand to the ground to a bag.
func _test_carried() -> void:
	var rig := _make_rig(4, true)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var lamp: InventorySlotContainer = rig["lamp"]
	var bag: InventorySlotContainer = rig["bag"]
	var inventory: Inventory = rig["inventory"]
	var carry_mount: Node3D = rig["carry_mount"]
	holder.drop_parent = self

	_check(FLASHLIGHT.has_carried_parts() and ItemActor.scene_has_carried_parts(FLASHLIGHT_SCENE), "the flashlight has a part made for carrying")
	_check(not ItemActor.scene_has_carried_parts(WORLD_ITEM_SCENE) and not ItemActor.scene_has_carried_parts(null), "the bare item scene has none")
	_check(ItemActor.scene_has_carried_parts(_inherited_scene_with_carried_base()), "one is found even when it is only in the scene this one is inherited from")

	# A lit flashlight in a pocket that carries items.
	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	light.power_level = 70.0
	light.is_on = true
	hotbar.add(light)
	var pocket := holder.get_carried_actor(light) as FlashlightActor
	_check(pocket != null and holder.is_carrying(light), "a flashlight in a pocket has an actor")
	_check(pocket.is_carried() and not pocket.is_held() and not pocket.is_in_world() and pocket.holder == holder, "that is carried, not held and not in the world")
	_check(pocket.get_parent() == carry_mount and pocket.item_instance == light, "on the carry mount, for the very same instance")
	_check(pocket.freeze and pocket.collision_layer == 0 and pocket.collision_mask == 0, "inert, with no body to bump into")
	var kept := []
	for child in pocket.get_children():
		kept.append(String(child.name))
	_check(kept == ["Light"], "and with nothing but its beam: %s" % [kept])
	_check(pocket.light.visible and pocket.is_on, "which is lit, because the instance is on")
	light.is_on = false
	_check(not pocket.light.visible, "and goes out with it")
	light.is_on = true
	_check(pocket.light.visible, "and comes back")

	# Nothing of a pocket's flashlight reads the ordinary input.
	await _press(&"primary_action")
	_check(light.is_on, "the primary action does nothing to it")

	# The battery runs down in a pocket, since the beam is lit.
	pocket.power_drain_per_second = 60.0
	await _frames(3)
	_check(light.power_level < 70.0 and absf(light.power_level - 67.0) < 1.5, "a lit flashlight in a pocket drains its battery: %.1f" % light.power_level)
	pocket.power_drain_per_second = 1.0
	var charge := light.power_level

	# Into the hand: the carried actor is swapped for the held one.
	_check(holder.equip_item(light), "the flashlight is taken in hand")
	_check(not holder.is_carrying(light) and holder.get_carried_actor(light) == null, "it is no longer carried")
	_check(not pocket.visible, "the carried one is gone at once, so the beam is not doubled")
	var in_hand := holder.equipped_actor as FlashlightActor
	_check(in_hand.is_first_person() and in_hand.light.visible and in_hand.flashlight_instance == light, "and the one in hand is lit, for the same instance")
	await get_tree().process_frame
	_check(not is_instance_valid(pocket), "the carried actor is freed")

	# And back: put away, it goes on shining from the pocket.
	holder.unequip_item()
	var again := holder.get_carried_actor(light) as FlashlightActor
	_check(again != null and again.is_carried(), "put away, it is carried again")
	_check(light.is_on and again.light.visible and absf(light.power_level - charge) < 1.5, "still lit, with its battery (%.1f)" % light.power_level)
	_check(not holder.has_equipped_item(), "and the hand is empty")

	# Dropped from the hand it is not carried.
	holder.equip_item(light)
	var dropped := holder.drop_equipped_item() as FlashlightActor
	_check(dropped != null and not holder.is_carrying(light) and not inventory.has_instance(light), "a dropped item is not carried")
	_check(dropped != null and dropped.light.visible and dropped.item_instance == light, "it shines on the ground")

	# Picked up again it goes to the lamp slot, which carries too.
	_check(holder.pick_up(dropped), "it is picked up")
	_check(lamp.has_instance(light) and holder.is_carrying(light) and not holder.has_equipped_item(), "into the lamp slot, carried, and not into the hand")
	_check(light.is_on, "still lit")

	# In a bag it is covered up: its actor goes, and it goes out.
	charge = light.power_level
	_check(inventory.move(light, bag), "the flashlight is put in the bag")
	_check(not holder.is_carrying(light), "a bag carries nothing")
	_check(not light.is_on and absf(light.power_level - charge) < 0.01, "the flashlight went out, and kept its battery")
	_check(inventory.move(light, hotbar), "taken out of the bag again")
	_check(holder.is_carrying(light) and not light.is_on and not holder.get_carried_actor(light).light.visible, "carried again, and unlit as it was left")

	# An item with nothing to do in a pocket has no actor there at all.
	var plain := Item.new()
	plain.id = &"plain"
	plain.display_name = "Plain"
	var bare := ItemActor.new()
	var plain_scene := PackedScene.new()
	plain_scene.pack(bare)
	bare.free()
	plain.actor_scene = plain_scene
	var plain_instance := plain.create_instance()
	hotbar.add(plain_instance)
	_check(not plain.has_carried_parts() and not holder.is_carrying(plain_instance), "an item with no part for carrying has no actor in a pocket")
	await get_tree().process_frame
	_check(carry_mount.get_child_count() == 1, "so a pocket costs nothing for it")

	# The way another player's pockets appear on this machine: no inventory involved.
	holder.view = ItemHolder.View.THIRD_PERSON
	var theirs := FLASHLIGHT.create_instance() as FlashlightInstance
	theirs.is_on = true
	_check(holder.carry_item(theirs) and holder.get_carried_actor(theirs).get_parent() == carry_mount, "the holder can be told what is carried, without an inventory")
	_check((holder.get_carried_actor(theirs) as FlashlightActor).light.visible, "and it shines from the same mount")
	holder.stop_carrying(theirs)
	_check(not holder.is_carrying(theirs), "and be told it is gone")
	holder.view = ItemHolder.View.AUTO
	_end_rig(rig)

	# The inventory starts with it: the actor is there as soon as the scene is.
	var starting := FLASHLIGHT.create_instance() as FlashlightInstance
	starting.is_on = true
	var started_rig := _make_rig(4, true, starting)
	var started_holder: ItemHolder = started_rig["holder"]
	await get_tree().process_frame
	var started_instance := (started_rig["lamp"] as InventorySlotContainer).get_instance(0)
	_check(started_instance != null and started_holder.is_carrying(started_instance), "what the inventory starts with is carried once the scene is up")
	_end_rig(started_rig)


## Who a carried item hears: the ones in a container that listens, one key, and only for its own player.
func _test_carried_input() -> void:
	var rig := _make_rig(4, true)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var lamp: InventorySlotContainer = rig["lamp"]
	var bag: InventorySlotContainer = rig["bag"]
	var inventory: Inventory = rig["inventory"]

	var worn := FLASHLIGHT.create_instance() as FlashlightInstance
	var spare := FLASHLIGHT.create_instance() as FlashlightInstance
	lamp.add(worn)
	hotbar.add(spare)
	var worn_actor := holder.get_carried_actor(worn) as FlashlightActor
	var spare_actor := holder.get_carried_actor(spare) as FlashlightActor
	_check(worn_actor.can_use_carried_input() and not spare_actor.can_use_carried_input(), "only the lamp slot listens")

	await _press(&"toggle_flashlight")
	_check(worn.is_on and worn_actor.light.visible, "the key lights the flashlight in the lamp slot")
	_check(not spare.is_on and not spare_actor.light.visible, "and not the other flashlight in a pocket")
	await _press(&"toggle_flashlight")
	_check(not worn.is_on, "the key puts it out again")
	await _press(&"primary_action")
	_check(not worn.is_on and not spare.is_on, "the primary action switches neither")

	# With another flashlight in hand: the key is for the carried one, the click for the one in hand.
	holder.equip_item(spare)
	var hand_actor := holder.equipped_actor as FlashlightActor
	await _press(&"toggle_flashlight")
	_check(worn.is_on and not spare.is_on, "with one in hand, the key still switches the one in the lamp slot")
	await _press(&"primary_action")
	_check(spare.is_on and hand_actor.light.visible and worn.is_on, "and the primary action the one in hand")
	await _press(&"toggle_flashlight")
	_check(not worn.is_on and spare.is_on, "the key never touches the one in hand")
	holder.unequip_item()
	_check(spare.is_on and holder.is_carrying(spare), "(put away it is still lit in the pocket)")
	await _press(&"toggle_flashlight")
	_check(worn.is_on and spare.is_on, "(and the key still does not switch it)")
	worn.is_on = false

	# Blocked, or somebody else's.
	holder.can_use_items.add(1, "stunned")
	await _press(&"toggle_flashlight")
	_check(not worn.is_on and not holder.get_carried_actor(worn).can_use_carried_input(), "a blocked holder cannot switch it")
	holder.can_use_items.remove(1)
	holder.view = ItemHolder.View.THIRD_PERSON
	await _press(&"toggle_flashlight")
	_check(not worn.is_on, "nor can this machine switch another player's flashlight")
	holder.view = ItemHolder.View.AUTO
	await _press(&"toggle_flashlight")
	_check(worn.is_on, "(and again for its own player)")
	worn.is_on = false

	# A pocket that does not listen, an item that moves between them, and one in a bag.
	var item := _probe_item()
	var probe_instance := item.create_instance()
	lamp.remove(worn)
	lamp.add(probe_instance)
	var probe := holder.get_carried_actor(probe_instance) as ProbeActor
	_check(probe != null and probe.is_carried(), "a made up item with a part for carrying is carried")
	await _press(&"primary_action")
	_check(probe.carried == 1, "in the lamp slot it hears its carried input")
	_check(probe.unhandled == 0 and probe.raw == 0, "and none of the input that is for a hand")
	_check(inventory.move(probe_instance, hotbar), "moved to the hotbar")
	probe = holder.get_carried_actor(probe_instance) as ProbeActor
	await _press(&"primary_action")
	_check(probe.carried == 0, "in the hotbar it is carried and deaf (a new actor has heard nothing)")
	_check(inventory.move(probe_instance, lamp), "and moved back")
	probe = holder.get_carried_actor(probe_instance) as ProbeActor
	await _press(&"primary_action")
	_check(probe.carried == 1, "in the lamp slot again it hears it")
	_check(inventory.move(probe_instance, bag) and holder.get_carried_actor(probe_instance) == null, "in a bag it has no actor to hear anything")
	_end_rig(rig)


## The real Player: the lamp slot and the hotbar both carry, T works the lamp slot, and the carried beam
## shines from the same place relative to the head as any other carried thing.
func _test_player_carried() -> void:
	var player := _new_player()
	add_child(player)
	await _frames(3)
	var holder := player.get_node("ItemHolder") as ItemHolder
	var inventory := player.get_node("Inventory") as Inventory
	var lamp := inventory.get_container(&"lamp") as InventorySlotContainer
	var hotbar := inventory.get_container(&"hotbar") as InventorySlotContainer
	var mount := holder.carried_parent
	var pivot := player.get_node("Head/YawPivot/PitchPivot") as Node3D
	_check(InputMap.has_action(FlashlightActor.TOGGLE_ACTION), "the project has the flashlight key")
	_check(lamp != null and lamp.carrying == InventoryContainer.Carrying.READY and lamp.size == 1, "the player has a lamp slot that listens")
	_check(hotbar.carrying == InventoryContainer.Carrying.CARRIED, "and a hotbar that carries")
	_check(lamp.accepts(FLASHLIGHT.create_instance()) and not lamp.accepts(_probe_item(false).create_instance()), "which takes lamps, and nothing else")
	var worn := lamp.get_instance(0) as FlashlightInstance
	var spare := hotbar.get_instance(0) as FlashlightInstance
	_check(worn != null and spare != null and worn != spare, "the player starts with a flashlight in each")
	_check(holder.is_carrying(worn) and holder.is_carrying(spare), "both are carried")
	var worn_actor := holder.get_carried_actor(worn) as FlashlightActor
	_check(worn_actor.get_parent() == mount, "on the head's carry mount")

	# Aim somewhere that is not straight ahead, so a wrong mount shows.
	(player.get_node("Head/YawPivot") as Node3D).rotation.y = 0.7
	pivot.rotation.x = -0.35
	await get_tree().process_frame
	await _press(&"toggle_flashlight")
	_check(worn.is_on and worn_actor.light.visible and not spare.is_on, "T lights the lamp slot's flashlight")
	var beam := pivot.global_transform.affine_inverse() * worn_actor.light.global_transform
	_check(beam.origin.distance_to(mount.position + worn_actor.light.position) < 0.005, "its beam starts at the carry mount: %s" % beam.origin)
	_check(absf(beam.basis.z.dot(Vector3.BACK) - 1.0) < 0.001, "and points where the head does")

	# A hand flashlight beside it: both can be lit, and each has its own switch.
	await _press(&"inventory_slot_1")
	_check(holder.equipped_instance == spare and not holder.is_carrying(spare) and holder.is_carrying(worn), "the hotbar's flashlight is taken in hand and the other stays in its pocket")
	await _press(&"primary_action")
	_check(spare.is_on and worn.is_on, "the click lights the one in hand, and the one in the pocket stays lit")
	await _press(&"inventory_slot_1")
	_check(holder.is_carrying(spare) and spare.is_on and worn.is_on, "put away, both shine from the pockets")
	await _press(&"toggle_flashlight")
	_check(not worn.is_on and spare.is_on, "T puts out the lamp slot's and leaves the other")
	player.free()


## Held items bob. The real Player on a floor, walking: the camera bobs by the head, and the item in hand
## by only part of that, a little late.
func _test_motion() -> void:
	var world := Node3D.new()
	add_child(world)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300, 200, 300)
	field_shape.shape = field_box
	field_shape.position = Vector3(0, 80, 0)
	field.add_child(field_shape)
	world.add_child(field)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400, 1, 400)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	var player := _new_player()
	player.position = Vector3(0, 0.05, 0)
	world.add_child(player)

	var holder := player.get_node("ItemHolder") as ItemHolder
	var motion := player.get_node("ItemMotion") as ItemMotion
	var head := player.get_node("HeadMotion") as HeadMotion
	var camera := player.get_node("Head/YawPivot/PitchPivot/Camera3D") as Camera3D
	var mount := holder.actor_parent
	var pivot := mount.get_parent() as Node3D
	var rest := mount.position
	var recorder := MotionRecorder.new()
	recorder.camera = camera
	recorder.mount = mount
	player.add_child(recorder)
	_check(motion.pivot == pivot and motion.head_motion == head and motion.holder == holder, "the player's item motion is wired to the head and the mount")
	_check(motion.process_priority > head.process_priority, "and runs after the head has moved")
	_check(holder.actor_parent == mount, "the holder puts items on that mount")
	await _frames(40)
	var hotbar := (player.get_node("Inventory") as Inventory).get_container(&"hotbar") as InventorySlotContainer
	holder.equip_item(hotbar.get_instance(0))
	await _frames(10)
	_check(pivot.transform.is_equal_approx(Transform3D.IDENTITY), "standing still the item does not move")

	var settings := {
		"strength 1": {"strength": 1.0, "scale": 1.0},
		"strength 0": {"strength": 0.0, "scale": 1.0},
		"item scale 0": {"strength": 1.0, "scale": 0.0},
		"fully steady": {"strength": 1.0, "scale": 2.0, "response": 5000.0},
	}
	var results := {}
	for label: String in settings:
		motion.strength = settings[label]["strength"]
		motion.response = settings[label].get("response", 25.0)
		holder.equipped_actor.bob_scale = settings[label]["scale"]
		Input.action_release("move_forward")
		await _frames(60)
		recorder.clear()
		Input.action_press("move_forward")
		await _frames(150)
		Input.action_release("move_forward")
		var view_y: Array[float] = []
		for point in recorder.item_in_view.slice(60):
			view_y.append(point.y)
		results[label] = {
			"camera": _range(recorder.camera_y.slice(60)),
			"world": _range(recorder.item_world_y.slice(60)),
			"view": _range(view_y),
		}
	var base: Dictionary = results["strength 1"]
	_check(base["camera"] > 0.02, "walking, the camera bobs (%.3f m)" % base["camera"])
	_check(base["view"] > 0.25 * base["camera"] and base["view"] < 0.7 * base["camera"], "and the item moves in the view by about half as much, against it (%.3f of %.3f)" % [base["view"], base["camera"]])
	_check(base["world"] < 0.85 * base["camera"] and base["world"] > 0.3 * base["camera"], "so it bobs less than the camera does in the world, but does bob (%.3f of %.3f)" % [base["world"], base["camera"]])
	_check(results["strength 0"]["view"] < 0.002 and results["strength 0"]["camera"] > 0.02, "with strength 0 it is fixed in the view as it was (%.4f)" % results["strength 0"]["view"])
	_check(results["item scale 0"]["view"] < 0.002, "an item that takes on no bob is fixed in the view (%.4f)" % results["item scale 0"]["view"])
	_check(results["fully steady"]["world"] < 0.03 * results["fully steady"]["camera"], "a hand that follows none of the head and keeps up holds the item still in the world (%.4f of %.3f)" % [results["fully steady"]["world"], results["fully steady"]["camera"]])

	# Standing still again, it is back where it belongs.
	motion.strength = 1.0
	motion.response = 25.0
	holder.equipped_actor.bob_scale = 1.0
	await _frames(120)
	_check(pivot.transform.origin.length() < 0.001 and mount.position.is_equal_approx(rest), "when the player stops the item settles back")
	motion.enabled = false
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	_check(pivot.transform.is_equal_approx(Transform3D.IDENTITY), "switched off, it does not move at all")
	world.free()


## Ladders and seats put items out of reach, seats can let the occupant look within limits, and the
## flashlight on the ground can be switched with its own "toggle" option.
func _test_ladder_and_seats() -> void:
	var player := _new_player()
	add_child(player)
	await _frames(3)
	var holder := player.get_node("ItemHolder") as ItemHolder
	var ladder := player.get_node("LadderController") as LadderController
	var seats := player.get_node("VehicleController") as VehicleController
	var rotator := player.get_node("Rotator") as Rotator
	# The tests run faster than the clock the Rotator's turn speed limit is measured on.
	rotator.server_max_turn_speed_degrees = 100000.0
	var inventory := player.get_node("Inventory") as Inventory
	var worn := (inventory.get_container(&"lamp") as InventorySlotContainer).get_instance(0) as FlashlightInstance
	var spare := (inventory.get_container(&"hotbar") as InventorySlotContainer).get_instance(0) as FlashlightInstance
	_check(holder.ladder_controller == ladder, "the player's holder knows its ladder controller")
	await _press(&"inventory_slot_1")
	var in_hand := holder.equipped_actor as FlashlightActor
	await _press(&"primary_action")
	_check(spare.is_on and in_hand.visible and holder.is_input_allowed() and not holder.are_items_hidden(), "on foot the item in hand is seen and used")

	# On a ladder.
	ladder.state = LadderController.State.CLIMBING
	await _frames(2)
	_check(holder.are_items_hidden() and not in_hand.visible, "on a ladder the item in hand is hidden")
	_check(not holder.is_input_allowed() and not in_hand.can_use_input(), "and cannot be used")
	await _press(&"primary_action")
	await _press(&"toggle_flashlight")
	await _press(&"inventory_slot_2")
	await _press(&"drop_item")
	_check(spare.is_on and not worn.is_on and holder.equipped_instance == spare, "no click, no key, no slot and no drop reach it")
	ladder.state = LadderController.State.IDLE
	await _frames(2)
	_check(in_hand.visible and in_hand.can_use_input(), "and it is back when they let go")
	await _press(&"primary_action")
	_check(not spare.is_on, "and works again")

	# A seat that does not allow items.
	var seat := Seat3D.new()
	var mount := Marker3D.new()
	mount.name = "SeatMount"
	seat.add_child(mount)
	add_child(seat)
	seat.global_position = Vector3(0, 5, 0)
	await get_tree().process_frame
	_check(not seat.are_items_allowed() and not seat.can_occupant_look(), "a seat by default takes items away and freezes the view")
	_check(seats.enter_seat(seat), "the player sits down")
	await _frames(20)
	_check(holder.are_items_hidden() and not in_hand.visible and not holder.is_input_allowed(), "sitting, the item in hand is hidden and out of reach")
	_check(rotator.process_mode == Node.PROCESS_MODE_DISABLED, "and the view is frozen")
	seats.exit_seat()
	await _frames(20)
	_check(in_hand.visible and holder.is_input_allowed(), "standing up gives it back")

	# One that allows them, and lets the occupant look through a limited arc.
	seat.allow_items = true
	seat.occupant_can_look = true
	seat.look_yaw_arc = 180.0
	seat.look_minimum_pitch = -30.0
	seat.look_maximum_pitch = 90.0
	var before := [rotator.maximum_yaw, rotator.minimum_pitch, rotator.maximum_pitch]
	rotator.add_look_input(1.0, -0.3)
	_check(seats.enter_seat(seat), "sitting in a seat that lets them look")
	await _frames(20)
	_check(not holder.are_items_hidden() and in_hand.visible and holder.is_input_allowed(), "items are theirs to use")
	_check(rotator.process_mode != Node.PROCESS_MODE_DISABLED, "and the view is free")
	_check(rotator.get_predicted_look().length() < 0.0001, "starting straight ahead of the seat, whatever way they looked before: %s" % rotator.get_predicted_look())
	rotator.add_look_input(5.0, 0.0)
	_check(is_equal_approx(rotator.get_predicted_look().x, PI / 2.0), "they cannot look more than 90 degrees to the left: %.2f" % rotator.get_predicted_look().x)
	rotator.add_look_input(-10.0, 0.0)
	_check(is_equal_approx(rotator.get_predicted_look().x, -PI / 2.0), "or to the right: %.2f" % rotator.get_predicted_look().x)
	rotator.add_look_input(0.0, 5.0)
	_check(is_equal_approx(rotator.get_predicted_look().y, deg_to_rad(90.0)), "straight up is the most they look up: %.2f" % rotator.get_predicted_look().y)
	rotator.add_look_input(0.0, -5.0)
	_check(is_equal_approx(rotator.get_predicted_look().y, deg_to_rad(-30.0)), "and 30 degrees down the most they look down: %.2f" % rotator.get_predicted_look().y)
	await _press(&"primary_action")
	_check(spare.is_on, "an item in hand works from the seat")
	seats.exit_seat()
	await _frames(20)
	_check([rotator.maximum_yaw, rotator.minimum_pitch, rotator.maximum_pitch] == before, "standing up gives back the usual limits")
	seat.free()

	# A vehicle seat is never allowed items or free looking: the occupant flies the vehicle.
	var driver_seat := VehicleSeat3D.new()
	driver_seat.allow_items = true
	driver_seat.occupant_can_look = true
	_check(not driver_seat.are_items_allowed() and not driver_seat.can_occupant_look(), "a vehicle seat overrides both")
	driver_seat.free()
	player.free()


func _test_world_toggle() -> void:
	var rig := _make_rig(1)
	var body: Node3D = rig["body"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var instance := FLASHLIGHT.create_instance() as FlashlightInstance
	var world := FLASHLIGHT.spawn_in_world(instance, self, Transform3D(Basis.IDENTITY, Vector3(0, 0, -3))) as FlashlightActor
	var pickup := world.get_node("InteractableObject3D") as ItemPickup
	_check(pickup.get_interaction_option_count() == 2 and pickup.find_interaction_option_index(&"pickup") == 0 and pickup.find_interaction_option_index(&"toggle") == 1, "the flashlight on the ground offers pick up and toggle")
	_check(pickup.can_interact(body, 1), "toggle can be used")
	_check(pickup.interact(body, 1) and instance.is_on and world.light.visible, "using it switches the flashlight on")
	_check(pickup.interact(body, 1) and not instance.is_on, "and off again")
	_check(is_instance_valid(world) and not hotbar.has_instance(instance), "without picking it up")

	# With no room to pick it up, it can still be switched.
	hotbar.add(FLASHLIGHT.create_instance())
	_check(not pickup.can_interact(body, 0) and pickup.can_interact(body, 1), "a full inventory hides pick up and not toggle")
	_check(pickup.interact(body, 1) and instance.is_on, "which still works")
	_check(pickup.interact(body, 1) and not instance.is_on, "(and goes off again)")
	var drained := FLASHLIGHT.create_instance() as FlashlightInstance
	drained.power_level = 0.0
	var dead := FLASHLIGHT.spawn_in_world(drained, self, Transform3D(Basis.IDENTITY, Vector3(0, 0, -3))) as FlashlightActor
	(dead.get_node("InteractableObject3D") as ItemPickup).interact(body, 1)
	_check(not drained.is_on, "one with no battery stays off")
	dead.free()
	world.free()
	_end_rig(rig)


## Sitting turns the player to face the way the seat faces, and eases them to it, camera and all. Standing
## eases them out, keeping the view where it was. A vehicle seat is instant.
func _test_seat_motion() -> void:
	var player := _new_player()
	add_child(player)
	await _frames(3)
	var seats := player.get_node("VehicleController") as VehicleController
	var rotator := player.get_node("Rotator") as Rotator
	# The tests run faster than the clock the Rotator's turn speed limit is measured on.
	rotator.server_max_turn_speed_degrees = 100000.0
	var camera := player.get_node("Head/YawPivot/PitchPivot/Camera3D") as Camera3D
	var movement := player.get_node("PlayerCharacterController") as CharacterController

	var seat := Seat3D.new()
	var mount := Marker3D.new()
	mount.name = "SeatMount"
	seat.add_child(mount)
	var dismount := Marker3D.new()
	dismount.name = "DismountPoint"
	dismount.position = Vector3(1.5, 0.0, 0.0)
	# A quarter turn from the seat, so standing up has to turn the body but not the view.
	dismount.rotation.y = PI / 2.0
	seat.add_child(dismount)
	add_child(seat)
	# Turned a quarter turn, so "forward" is not the way the player already faces (-Z).
	seat.global_transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(3, 0, 0))
	await get_tree().process_frame
	var seat_forward := seat.global_basis * Vector3.FORWARD
	_check(is_equal_approx(seat.transition_time, 0.15) and seat.transition_time < 0.25, "a seat eases in faster than a ladder (%.2f s)" % seat.transition_time)

	rotator.add_look_input(0.7, -0.3)
	var start := player.global_position
	var start_forward := camera.global_basis * Vector3.FORWARD
	_check(seats.enter_seat(seat), "the player sits down")
	_check(seats.is_moving_to_seat() and player.global_position.distance_to(start) < 0.01, "easing in, they have not moved yet")
	_check(player.collision_layer == 0 and not movement.movement_blocker.is_permitted(), "but are already out of the way and cannot walk off")
	await _frames(4)
	var middle := player.global_position
	var middle_forward := camera.global_basis * Vector3.FORWARD
	_check(middle.distance_to(start) > 0.3 and middle.distance_to(seat.global_position) > 0.3, "partway they are between where they were and the seat (%s)" % middle)
	_check(middle_forward.dot(start_forward) < 0.999 and middle_forward.dot(seat_forward) > start_forward.dot(seat_forward), "and the camera is turning toward the seat's forward")
	await _frames(3)
	_check((camera.global_basis * Vector3.FORWARD).dot(seat_forward) > 0.95, "nearly facing the seat's forward just before the end, so it was turning all along: %.2f" % (camera.global_basis * Vector3.FORWARD).dot(seat_forward))
	await _frames(20)
	_check(not seats.is_moving_to_seat() and player.global_position.distance_to(seat.global_position) < 0.001, "then they are in the seat")
	var sitting_forward := camera.global_basis * Vector3.FORWARD
	_check(sitting_forward.dot(seat_forward) > 0.9999, "facing the way the seat faces: %s vs %s" % [sitting_forward, seat_forward])
	_check(rotator.get_predicted_look().length() < 0.0001, "and level")

	# Standing up: eased to the dismount point, the view pointing where it was.
	var sitting_view := camera.global_basis * Vector3.FORWARD
	_check(seats.exit_seat(), "the player gets up")
	var out_frames := 0
	_check(seats.is_moving_to_seat() and not is_instance_valid(seats.current_seat), "easing out")
	_check(player.collision_layer == 0 and not movement.movement_blocker.is_permitted(), "still out of the way until they are out")
	await _frames(4)
	var out_middle := player.global_position
	_check(out_middle.distance_to(seat.global_position) > 0.2 and out_middle.distance_to(dismount.global_position) > 0.2, "partway they are between the seat and the dismount point (%s)" % out_middle)
	_check((camera.global_basis * Vector3.FORWARD).dot(sitting_view) > 0.999, "and the view has not turned")
	while seats.is_moving_to_seat() and out_frames < 60:
		await _frames(1)
		out_frames += 1
	_check(not seats.is_moving_to_seat() and player.global_position.distance_to(dismount.global_position) < 0.001, "then they are at the dismount point")
	_check((camera.global_basis * Vector3.FORWARD).dot(sitting_view) > 0.999, "looking where they were looking: %s vs %s" % [camera.global_basis * Vector3.FORWARD, sitting_view])
	_check(player.collision_layer != 0 and movement.movement_blocker.is_permitted(), "free to walk again")

	# Instant, when the seat says so.
	seat.transition_time = 0.0
	_check(seats.enter_seat(seat) and not seats.is_moving_to_seat() and player.global_position.distance_to(seat.global_position) < 0.001, "with no transition time they are in the seat at once")
	_check((camera.global_basis * Vector3.FORWARD).dot(seat_forward) > 0.9999, "facing forward")
	_check(seats.exit_seat() and not seats.is_moving_to_seat() and player.global_position.distance_to(dismount.global_position) < 0.001, "and out of it at once")
	var driver_seat := VehicleSeat3D.new()
	_check(is_zero_approx(driver_seat.transition_time), "a vehicle seat starts with no transition")
	driver_seat.free()
	seat.free()
	player.free()


## Dropping the item in hand takes the next hotbar item in hand, going round to the start.
func _test_drop_next() -> void:
	var rig := _make_rig(5)
	var holder: ItemHolder = rig["holder"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	holder.drop_parent = self
	var items: Array[ItemInstance] = []
	for slot in [0, 2, 3]:
		var instance := FLASHLIGHT.create_instance()
		hotbar.add(instance, Vector2i(slot, 0))
		items.append(instance)
	var dropped: Array[ItemActor] = []
	holder.equip_item(items[1])
	dropped.append(holder.drop_equipped_item())
	_check(holder.equipped_instance == items[2], "dropping slot 2 takes slot 3 in hand (slot 1 is empty)")
	dropped.append(holder.drop_equipped_item())
	_check(holder.equipped_instance == items[0], "dropping the last slot goes round to the first")
	dropped.append(holder.drop_equipped_item())
	_check(not holder.has_equipped_item(), "with nothing left the hand is empty")
	holder.equip_item(items[0]) if hotbar.has_instance(items[0]) else null
	var again := FLASHLIGHT.create_instance()
	var other := FLASHLIGHT.create_instance()
	hotbar.add(again, Vector2i(1, 0))
	hotbar.add(other, Vector2i(4, 0))
	holder.equip_item(again)
	holder.equip_next_on_drop = false
	holder.drop_equipped_item()
	_check(not holder.has_equipped_item(), "with the setting off the hand stays empty")
	for actor in dropped:
		actor.free()
	_end_rig(rig)


## What the player holds is seen from their eyes and shadowed from their character's hand.
func _test_held_shadow() -> void:
	var player := _new_player()
	add_child(player)
	await _frames(3)
	var holder := player.get_node("ItemHolder") as ItemHolder
	var shadow_only := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

	# The item in hand.
	await _frames(40)
	await _press(&"inventory_slot_1")
	var in_hand := holder.equipped_actor as FlashlightActor
	var copy := holder.get_shadow_actor() as FlashlightActor
	_check(in_hand != null and copy != null and copy != in_hand, "holding an item, the player's character also holds a copy")
	_check(copy.is_third_person() and copy.is_shadow_only() and copy.get_parent() == holder.third_person_parent, "on the character's mount, as a shadow")
	var lights := 0
	var copy_meshes: Array[GeometryInstance3D] = []
	_collect_meshes(copy, copy_meshes)
	for child in copy.find_children("*", "Light3D", true, false):
		lights += 1
	_check(lights == 0 and not copy_meshes.is_empty() and copy_meshes.all(func(m: GeometryInstance3D) -> bool: return m.cast_shadow == shadow_only), "which has no lights and only casts shadows")
	var hand_meshes: Array[GeometryInstance3D] = []
	_collect_meshes(in_hand, hand_meshes)
	_check(hand_meshes.all(func(m: GeometryInstance3D) -> bool: return m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "while the one they see casts none, so the shadow is only made once")
	_check(not (in_hand.light.light_cull_mask & Player.OWN_BODY_LAYER), "and its light leaves the player's own body out")
	var instance := in_hand.flashlight_instance
	instance.is_on = true
	in_hand.power_drain_per_second = 60.0
	copy.power_drain_per_second = 60.0
	var before := instance.power_level
	await _frames(6)
	_check(absf((before - instance.power_level) - 6.0) < 1.5, "a lit flashlight drains once and not twice for the copy: %.1f" % (before - instance.power_level))
	in_hand.power_drain_per_second = 1.0

	await _press(&"inventory_slot_1")
	_check(holder.get_shadow_actor() == null, "putting it away takes the copy away")
	var worn := (player.get_node("Inventory") as Inventory).get_container(&"lamp") as InventorySlotContainer
	var carried := holder.get_carried_actor(worn.get_instance(0)) as FlashlightActor
	_check(carried != null and not (carried.light.light_cull_mask & Player.OWN_BODY_LAYER), "a light the player carries leaves their own body out too")
	await _press(&"inventory_slot_1")
	await _press(&"drop_item")
	_check(holder.get_shadow_actor() == null or holder.get_shadow_actor().item_instance != instance, "dropping it does too (the next item in the hotbar gets one of its own)")
	player.free()


func _collect_meshes(node: Node, into: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D:
		into.append(node as GeometryInstance3D)
	for child in node.get_children():
		_collect_meshes(child, into)


# --- Helpers -----------------------------------------------------------------

## A Player, with its item holder looking after the player at this machine (the scene may be saved with the
## holder previewing another player's view).
func _new_player() -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	(player.get_node("ItemHolder") as ItemHolder).view = ItemHolder.View.AUTO
	return player


## A body with an eye, a mount on the eye, an inventory with a hotbar, and a holder reading them. With
## [param carry] it also has a head mount to carry things on, a lamp slot that listens (taking lamps, and
## [param lamp_start] if given), a hotbar that carries and a bag that packs things away.
func _make_rig(hotbar_size: int, carry := false, lamp_start: ItemInstance = null) -> Dictionary:
	# A character body, because what a dropped item inherits depends on how the holder is moving, and
	# whether gravity pulls on it.
	var body := CharacterBody3D.new()
	body.collision_layer = PhysicsLayers.PLAYERS
	body.collision_mask = 0
	# Fields only find bodies that have a shape.
	var body_shape := CollisionShape3D.new()
	body_shape.shape = SphereShape3D.new()
	body.add_child(body_shape)
	add_child(body)
	var eye := Node3D.new()
	body.add_child(eye)
	var mount := Marker3D.new()
	mount.position = Vector3(0.3, -0.25, -0.55)
	eye.add_child(mount)
	var hotbar := InventorySlotContainer.new()
	hotbar.id = &"hotbar"
	hotbar.size = hotbar_size
	var inventory := Inventory.new()
	var carry_mount: Marker3D
	var lamp: InventorySlotContainer
	var bag: InventorySlotContainer
	if carry:
		carry_mount = Marker3D.new()
		carry_mount.position = Vector3(0.2, -0.15, 0.0)
		eye.add_child(carry_mount)
		lamp = InventorySlotContainer.new()
		lamp.id = &"lamp"
		lamp.size = 1
		lamp.accepted_tags = [&"lamp"]
		lamp.carrying = InventoryContainer.Carrying.READY
		if lamp_start != null:
			lamp.starting_items = [lamp_start]
		hotbar.carrying = InventoryContainer.Carrying.CARRIED
		bag = InventorySlotContainer.new()
		bag.id = &"bag"
		bag.size = 3
		bag.carrying = InventoryContainer.Carrying.PACKED_AWAY
		inventory.containers.append(lamp)
	inventory.containers.append(hotbar)
	if carry:
		inventory.containers.append(bag)
	body.add_child(inventory)
	var holder := ItemHolder.new()
	holder.inventory = inventory
	holder.actor_parent = mount
	holder.third_person_parent = mount
	holder.carried_parent = carry_mount
	body.add_child(holder)
	return {
		"body": body,
		"eye": eye,
		"mount": mount,
		"carry_mount": carry_mount,
		"inventory": inventory,
		"holder": holder,
		# The inventory works on its own copy, so use that one.
		"hotbar": inventory.get_container(&"hotbar"),
		"lamp": inventory.get_container(&"lamp"),
		"bag": inventory.get_container(&"bag"),
	}


## An item whose scene is a ProbeActor with a part for carrying, to count the input it is given. A lamp,
## so it fits the lamp slot, unless told it is not.
func _probe_item(lamp_tag := true) -> Item:
	var root := ProbeActor.new()
	root.name = "Probe"
	var beam := Node3D.new()
	beam.name = "Beam"
	beam.add_to_group(ItemActor.GROUP_ALWAYS, true)
	root.add_child(beam)
	beam.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	var item := Item.new()
	item.id = &"probe"
	item.display_name = "Probe"
	if lamp_tag:
		item.tags = [&"lamp"]
	item.actor_scene = scene
	return item


## A scene that is inherited from one with a part for carrying, and has none of its own. (Written out by
## hand, as the editor writes an inherited scene: packing an instance would copy the base's parts into it.)
func _inherited_scene_with_carried_base() -> PackedScene:
	var base_root := Node3D.new()
	var beam := Node3D.new()
	beam.name = "Beam"
	beam.add_to_group(ItemActor.GROUP_ALWAYS, true)
	base_root.add_child(beam)
	beam.owner = base_root
	var base := PackedScene.new()
	base.pack(base_root)
	base_root.free()
	ResourceSaver.save(base, "user://item_actor_test_base.tscn")
	var file := FileAccess.open("user://item_actor_test_derived.tscn", FileAccess.WRITE)
	file.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="user://item_actor_test_base.tscn" id="1"]\n\n[node name="Derived" instance=ExtResource("1")]\n')
	file.close()
	var derived := ResourceLoader.load("user://item_actor_test_derived.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return derived


## The distance between the lowest and highest of the values.
func _range(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	return values.max() - values.min()


func _end_rig(rig: Dictionary) -> void:
	(rig["body"] as Node).free()


## Presses an input action the way the engine would deliver it, then lets it be handled.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


## For the body, the head and the lens of a flashlight: is each drawn with the z clip scale?
func _clipped(actor: ItemActor) -> Array[bool]:
	var flags: Array[bool] = []
	for part in ["Body", "Head", "Lightmesh"]:
		var material := (actor.get_node(part) as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		flags.append(material.use_z_clip_scale)
	return flags


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("ITEM ACTOR TEST FAILED: " + message)
	print("FAIL: ", message)
