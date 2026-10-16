extends Node
## Headless checks for ItemSlot: an interactable that holds one item, fixed in place like a world item
## with no physics, that a player fills from their hand and empties through the item's own pickup.
##
## godot --headless --fixed-fps 60 --path . res://Components/Inventory/Testing/ItemSlotTest.tscn
## ONLY=<name> runs one test, such as ONLY=interaction.

const FLASHLIGHT: Item = preload("res://Game/Registry/Items/Flashlight/flashlight_item.tres")
const BATTERY: Item = preload("res://Game/Registry/Items/Battery/battery_item.tres")

var _failures := 0


## A slot with a rule of its own on top of the lists.
class PickySlot extends ItemSlot:
	var picky_allows := false
	var placed_log: Array = []
	var removed_log: Array = []

	func _accepts(_instance_to_check: ItemInstance) -> bool:
		return picky_allows

	func _on_placed(placed: ItemInstance, _placed_actor: ItemActor) -> void:
		placed_log.append(placed)

	func _on_removed(removed: ItemInstance) -> void:
		removed_log.append(removed)


func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in ["place", "filters", "interaction", "pickup", "mount", "starting", "rule"]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Item slot tests passed.")
	else:
		print("Item slot tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_place() -> void:
	var slot := _make_slot(Vector3(0.0, 5.0, 0.0))
	var placed := []
	var removed := []
	slot.item_placed.connect(func(instance: ItemInstance, _actor: ItemActor) -> void: placed.append(instance))
	slot.item_removed.connect(func(instance: ItemInstance) -> void: removed.append(instance))
	var full_layer := slot.collision_layer
	_check(full_layer == PhysicsLayers.INTERACTABLES and slot.is_empty() and slot.get_instance() == null and slot.get_actor() == null, "a new slot is empty and looked at on the interactables layer")
	_check(slot.get_interaction_option(0) != null and StringName(slot.get_interaction_option(0).option_id) == ItemSlot.PLACE_ID, "it has a place option")

	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	light.power_level = 37.0
	light.is_on = true
	_check(slot.can_place(light), "it takes an item")
	_check(not slot.can_place(null), "but not nothing")
	_check(slot.place(light), "placing it")
	var actor := slot.get_actor()
	_check(not slot.is_empty() and slot.get_instance() == light and actor != null, "fills the slot")
	_check(placed == [light], "and says so")
	_check(actor.get_parent() == slot and actor.is_inside_tree() and actor.is_in_world(), "the item is a world item, a child of the slot")
	_check(actor.freeze and actor.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC and actor.collision_layer == 0, "with its physics switched off")
	_check(actor.item_instance == light and (actor as FlashlightActor).light.visible, "and the light that is on still shines")
	_check(light.power_level == 37.0 and light.is_on, "with its state")
	_check(actor.get_node("InteractableObject3D") is ItemPickup, "it keeps its own pickup prompt")
	_check(slot.collision_layer == 0, "a full slot is not looked at, so the item's prompt can be reached")
	_check(not slot.can_place(FLASHLIGHT.create_instance()) and not slot.place(FLASHLIGHT.create_instance()), "a full slot takes nothing more")

	var start := actor.global_position
	await _frames(60)
	_check(actor.global_position.is_equal_approx(start) and is_instance_valid(actor), "it does not fall (%s)" % str(actor.global_position - start))

	_check(slot.remove() == light, "removing it gives the item back")
	_check(slot.is_empty() and slot.remove() == null, "the slot is empty")
	_check(removed == [light], "and says so once")
	_check(slot.collision_layer == full_layer, "and is looked at again")
	await get_tree().process_frame
	_check(not is_instance_valid(actor), "the actor is gone")
	_check(light.is_on and light.power_level > 30.0 and light.power_level <= 37.0, "the item kept its state (the lit flashlight kept draining its battery while it sat there: %.2f)" % light.power_level)
	_check(slot.place(light), "it can go back in")
	slot.get_parent().free()


func _test_filters() -> void:
	var lamp_slot := _make_slot(Vector3.ZERO)
	lamp_slot.accepted_tags = [&"lamp"]
	_check(lamp_slot.can_place(FLASHLIGHT.create_instance()), "a slot for lamps takes a flashlight")
	_check(not lamp_slot.can_place(BATTERY.create_instance()), "but not a battery")
	_check(not lamp_slot.place(BATTERY.create_instance()) and lamp_slot.is_empty(), "and placing one changes nothing")

	var battery_slot := _make_slot(Vector3.ZERO)
	battery_slot.accepted_items = [BATTERY]
	_check(battery_slot.can_place(BATTERY.create_instance()) and not battery_slot.can_place(FLASHLIGHT.create_instance()), "a slot can name the items it takes")

	var open_slot := _make_slot(Vector3.ZERO)
	_check(open_slot.can_place(BATTERY.create_instance()) and open_slot.can_place(FLASHLIGHT.create_instance()), "a slot with no lists takes anything")
	for slot in [lamp_slot, battery_slot, open_slot]:
		slot.get_parent().free()


func _test_interaction() -> void:
	var slot := _make_slot(Vector3(0.0, 0.0, -2.0))
	var rig := _make_rig()
	var body: Node3D = rig["body"]
	var holder: ItemHolder = rig["holder"]
	var inventory: Inventory = rig["inventory"]
	var hotbar: InventorySlotContainer = rig["hotbar"]
	var hand_events := []
	holder.item_unequipped.connect(func(instance: ItemInstance) -> void: hand_events.append(instance))

	_check(not slot.can_interact(body, 0), "with nothing in hand the slot offers nothing")
	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	light.is_on = true
	hotbar.add(light, Vector2i(0, 0))
	holder.equip_item(light)
	_check(slot.get_available_interaction_indices(body) == [0], "holding an item the slot takes, it offers to place it")
	slot.accepted_tags = [&"battery_only"]
	_check(not slot.can_interact(body, 0), "holding one it does not take, it offers nothing")
	slot.accepted_tags = []

	_check(slot.interact(body, 0), "placing the item from the hand")
	_check(slot.get_instance() == light and not inventory.has_instance(light), "it is in the slot and out of the inventory")
	_check(not holder.has_equipped_item() and holder.equipped_instance == null, "the hand is empty")
	_check(hand_events == [light], "and the holder says it let go")
	_check(light.is_on and (slot.get_actor() as FlashlightActor).light.visible, "the flashlight is still on, shining from the slot")
	await get_tree().process_frame
	_check(rig["mount"].get_child_count() == 0, "the hand's actor is gone")
	_check(not slot.can_interact(body, 0), "a full slot offers nothing")

	# A second item goes to the next hotbar slot and, in hand, is not offered to a full slot.
	var other := FLASHLIGHT.create_instance()
	hotbar.add(other, Vector2i(1, 0))
	holder.equip_item(other)
	_check(not slot.can_interact(body, 0), "even with another item in hand")

	# The item is taken out of the hand of someone with nothing next in the hotbar: equip-next rule.
	slot.remove()
	await get_tree().process_frame
	_check(slot.interact(body, 0) and slot.get_instance() == other, "the item in hand goes in")
	_check(holder.equipped_instance == null or holder.equipped_instance != other, "and is not in hand any more")
	slot.get_parent().free()
	_end_rig(rig)


func _test_pickup() -> void:
	var slot := _make_slot(Vector3(0.0, 0.0, -2.0))
	var rig := _make_rig()
	var body: Node3D = rig["body"]
	var holder: ItemHolder = rig["holder"]
	var inventory: Inventory = rig["inventory"]
	var removed := []
	slot.item_removed.connect(func(instance: ItemInstance) -> void: removed.append(instance))

	var light := FLASHLIGHT.create_instance() as FlashlightInstance
	light.power_level = 61.0
	light.is_on = true
	slot.place(light)
	var actor := slot.get_actor()
	var pickup := actor.get_node("InteractableObject3D") as ItemPickup
	_check(pickup.can_interact(body, 0), "the item in the slot can be picked up like any other")
	_check(pickup.interact(body, 0), "doing it")
	_check(inventory.has_instance(light) and light.power_level == 61.0 and light.is_on, "the item is in the inventory with its state")
	_check(slot.is_empty(), "the slot notices at once")
	await _frames(3)
	_check(removed == [light] and not is_instance_valid(actor), "and says so once the item is gone")
	_check(slot.collision_layer == PhysicsLayers.INTERACTABLES, "the slot is looked at again")
	_check(holder.equipped_instance == light, "the hand was empty, so it is in hand")

	# Round trip.
	_check(slot.interact(body, 0) and slot.get_instance() == light, "and it can be put back")
	await _frames(2)
	_check((slot.get_actor() as FlashlightActor).light.visible, "still shining")

	# The item's own world options work from the slot.
	var flashlight := slot.get_actor() as FlashlightActor
	_check(flashlight.is_in_world() and flashlight._on_world_option(&"toggle", body) and not light.is_on, "a flashlight in a slot can still be switched with its own prompt")
	slot.get_parent().free()
	_end_rig(rig)


func _test_mount() -> void:
	var holder_node := Node3D.new()
	add_child(holder_node)
	var shelf := Node3D.new()
	holder_node.add_child(shelf)
	var spot := Marker3D.new()
	spot.position = Vector3(0.0, 0.5, 0.0)
	shelf.add_child(spot)
	var slot := _new_slot()
	slot.mount = spot
	slot.item_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.25))
	shelf.add_child(slot)
	await _frames(1)

	var light := FLASHLIGHT.create_instance()
	_check(slot.place(light), "an item goes in")
	var actor := slot.get_actor()
	_check(actor.get_parent() == spot, "it is attached to the mount")
	_check(actor.position.is_equal_approx(Vector3(0.0, 0.0, 0.25)), "at the offset from it")
	holder_node.position = Vector3(10.0, 0.0, 0.0)
	holder_node.rotate_y(PI * 0.5)
	await _frames(2)
	var expected := holder_node.global_transform * Vector3(0.0, 0.5, 0.0) + holder_node.global_basis * Vector3(0.0, 0.0, 0.25)
	_check(actor.global_position.distance_to(expected) < 0.001, "and it goes where the shelf goes (off by %.4f)" % actor.global_position.distance_to(expected))
	holder_node.free()


func _test_starting() -> void:
	var template := FLASHLIGHT.create_instance() as FlashlightInstance
	template.power_level = 12.0
	var holders := []
	var slots := []
	for index in 2:
		var holder_node := Node3D.new()
		add_child(holder_node)
		var slot := _new_slot()
		slot.starting_instance = template
		holder_node.add_child(slot)
		holders.append(holder_node)
		slots.append(slot)
	_check(slots[0].is_empty(), "a slot with a starting item is filled a moment after it is ready")
	await _frames(2)
	_check(not slots[0].is_empty() and not slots[1].is_empty(), "then it is")
	var first: FlashlightInstance = slots[0].get_instance()
	var second: FlashlightInstance = slots[1].get_instance()
	_check(first != template and second != template and first != second, "each copy of the scene gets an instance of its own")
	_check(first.power_level == 12.0 and slots[0].get_actor().is_in_world(), "with the state it was given")
	first.power_level = 1.0
	_check(second.power_level == 12.0 and template.power_level == 12.0, "which are separate")
	for holder_node in holders:
		holder_node.free()


func _test_rule() -> void:
	var holder_node := Node3D.new()
	add_child(holder_node)
	var slot := PickySlot.new()
	slot.collision_layer = 1
	_add_shape(slot)
	holder_node.add_child(slot)
	await _frames(1)
	var light := FLASHLIGHT.create_instance()
	_check(not slot.can_place(light) and not slot.place(light), "a subclass can refuse an item")
	slot.picky_allows = true
	_check(slot.place(light), "or take it")
	_check(slot.placed_log == [light], "and is told when one goes in")
	slot.remove()
	_check(slot.removed_log == [light], "and when it comes out")
	holder_node.free()


# --- Helpers -----------------------------------------------------------------

func _new_slot() -> ItemSlot:
	var slot := ItemSlot.new()
	_add_shape(slot)
	return slot


func _add_shape(slot: Area3D) -> void:
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	slot.add_child(shape)


## A slot inside a plain node, in the tree and ready.
func _make_slot(at: Vector3) -> ItemSlot:
	var holder_node := Node3D.new()
	holder_node.position = at
	add_child(holder_node)
	var slot := _new_slot()
	holder_node.add_child(slot)
	return slot


## A character body with an inventory (a two slot hotbar) and a holder.
func _make_rig() -> Dictionary:
	var body := CharacterBody3D.new()
	body.collision_layer = PhysicsLayers.PLAYERS
	body.collision_mask = 0
	var body_shape := CollisionShape3D.new()
	body_shape.shape = SphereShape3D.new()
	body.add_child(body_shape)
	add_child(body)
	var mount := Marker3D.new()
	mount.position = Vector3(0.3, -0.25, -0.55)
	body.add_child(mount)
	var hotbar := InventorySlotContainer.new()
	hotbar.id = &"hotbar"
	hotbar.size = 2
	var inventory := Inventory.new()
	inventory.containers.append(hotbar)
	body.add_child(inventory)
	var holder := ItemHolder.new()
	holder.inventory = inventory
	holder.actor_parent = mount
	holder.third_person_parent = mount
	holder.equip_on_pickup = true
	body.add_child(holder)
	return {
		"body": body,
		"mount": mount,
		"inventory": inventory,
		"holder": holder,
		# The inventory works on its own copy of its containers.
		"hotbar": inventory.get_container(&"hotbar"),
	}


func _end_rig(rig: Dictionary) -> void:
	(rig["body"] as Node).free()


func _check(value: bool, message: String) -> void:
	if value:
		print("  ok   ", message)
		return
	_failures += 1
	push_error("ITEM SLOT TEST FAILED: " + message)
	print("  FAIL ", message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
