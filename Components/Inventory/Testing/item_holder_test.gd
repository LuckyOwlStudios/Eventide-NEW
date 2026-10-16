extends Node
## Headless checks for ItemHolder and the hotbar display, on their own and in the real Player scene.
##
## godot --headless --fixed-fps 60 --path . res://Components/Inventory/Testing/ItemHolderTest.tscn
## ONLY=<name> runs one test, such as ONLY=player_scene.

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const FLASHLIGHT: Item = preload("res://Game/Registry/Items/Flashlight/flashlight_item.tres")

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in ["holder", "keys", "display", "player_scene"]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Item holder tests passed.")
	else:
		print("Item holder tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_holder() -> void:
	var setup := _make_setup(6)
	var holder: ItemHolder = setup["holder"]
	var inventory: Inventory = setup["inventory"]
	var hotbar: InventorySlotContainer = setup["hotbar"]
	var mount: Node3D = setup["mount"]
	var backpack := inventory.get_container(&"backpack") as InventoryGridContainer
	var equipped := []
	var dropped := []
	holder.item_equipped.connect(func(instance: ItemInstance, _actor: ItemActor) -> void: equipped.append(instance))
	holder.item_unequipped.connect(func(instance: ItemInstance) -> void: dropped.append(instance))

	_check(holder.get_hotbar() == hotbar, "the holder finds its hotbar by id")
	_check(not holder.toggle_inventory_slot(0) and not holder.has_equipped_item(), "an empty slot equips nothing")
	var light := FLASHLIGHT.create_instance()
	hotbar.add(light, Vector2i(2, 0))
	_check(holder.toggle_inventory_slot(2) and holder.has_equipped_item(), "a slot with an item equips it")
	_check(holder.equipped_instance == light and holder.equipped_actor is FlashlightActor, "as its actor")
	_check(mount.get_child_count() == 1 and holder.equipped_actor.get_parent() == mount, "which sits on the mount")
	_check(equipped == [light], "and announces it")
	await _press(&"primary_action")
	_check((holder.equipped_actor as FlashlightActor).is_on, "the actor reads its own input")
	var actor := holder.equipped_actor
	_check(holder.toggle_inventory_slot(2) and not holder.has_equipped_item(), "the same slot again puts it away")
	_check(dropped == [light], "and announces that")
	await get_tree().process_frame
	_check(not is_instance_valid(actor) and mount.get_child_count() == 0, "the actor is gone")
	_check(holder.toggle_inventory_slot(2), "it can be taken out again")
	_check(not holder.toggle_inventory_slot(0) and not holder.has_equipped_item(), "an empty slot puts away what is in hand")
	holder.toggle_inventory_slot(2)
	_check(not holder.toggle_inventory_slot(6) and not holder.toggle_inventory_slot(-1) and holder.equipped_instance == light, "slots that do not exist do nothing")

	hotbar.add(light, Vector2i(4, 0))
	_check(holder.equipped_instance == light and holder.has_equipped_item(), "moving the item to another hotbar slot keeps it in hand")
	_check(holder.toggle_inventory_slot(4), "and that slot is now the one that puts it away")
	holder.toggle_inventory_slot(4)
	_check(inventory.move(light, backpack), "putting it in the backpack")
	_check(not holder.has_equipped_item() and holder.equipped_instance == null, "puts it away: you cannot hold what is in a bag")
	_check(not holder.toggle_inventory_slot(4), "and the slot is empty")
	_check(holder.equip_item(light) and holder.has_equipped_item(), "an item from anywhere in the inventory can still be equipped by code")
	_check(inventory.remove(light) and not holder.has_equipped_item(), "and dropping it puts it away")
	_check(not holder.equip_item(light), "an item the inventory does not have cannot be equipped")
	_check(not holder.equip_item(null), "nor nothing")

	holder.hotbar_id = &"nothing"
	_check(holder.get_hotbar() == null and not holder.toggle_inventory_slot(0), "a holder pointed at a missing container does nothing")
	_end_setup(setup)


## The number keys, through real input events.
func _test_keys() -> void:
	var setup := _make_setup(4)
	var holder: ItemHolder = setup["holder"]
	var hotbar: InventorySlotContainer = setup["hotbar"]
	var first := FLASHLIGHT.create_instance()
	var second := FLASHLIGHT.create_instance()
	hotbar.add(first)
	hotbar.add(second, Vector2i(2, 0))
	await _press(&"inventory_slot_1")
	_check(holder.equipped_instance == first, "key 1 equips slot 1")
	await _press(&"inventory_slot_3")
	_check(holder.equipped_instance == second, "key 3 switches to slot 3")
	await _press(&"inventory_slot_3")
	_check(not holder.has_equipped_item(), "pressing it again puts it away")
	await _press(&"inventory_slot_2")
	_check(not holder.has_equipped_item(), "an empty slot does nothing")
	await _press(&"inventory_slot_1")
	await _press(&"inventory_slot_2")
	_check(not holder.has_equipped_item(), "but an empty slot puts away what is in hand")
	await _press(&"inventory_slot_1")
	hotbar.size = 3
	await _press(&"inventory_slot_4")
	_check(holder.equipped_instance == first, "a key beyond the hotbar does nothing at all")
	_end_setup(setup)


func _test_display() -> void:
	var setup := _make_setup(5)
	var holder: ItemHolder = setup["holder"]
	var hotbar: InventorySlotContainer = setup["hotbar"]
	var display := InventoryHotbar.new()
	display.item_holder = holder
	add_child(display)
	_check(display.get_child_count() == 5, "the display has a panel for every slot of the hotbar")
	_check(_tooltip(display, 0) == "Empty" and _icon(display, 0).texture == null, "empty slots show nothing")
	var light := FLASHLIGHT.create_instance()
	hotbar.add(light, Vector2i(3, 0))
	_check(_icon(display, 3).texture == FLASHLIGHT.icon and _tooltip(display, 3) == "Flashlight", "an item appears as soon as it is added")
	_check(_quantity(display, 3) == "", "a single item shows no count")
	var bullets := Item.new()
	bullets.id = &"bullets"
	bullets.display_name = "Bullets"
	bullets.max_stack_size = 100
	hotbar.add(bullets.create_instance(40), Vector2i(1, 0))
	_check(_quantity(display, 1) == "40", "a stack shows how many")
	hotbar.add(bullets.create_instance(25), Vector2i(0, 0))
	_check(_quantity(display, 0) == "25" and _quantity(display, 1) == "40", "stacks are shown per slot")
	hotbar.add(bullets.create_instance(10))
	_check(_quantity(display, 0) == "35" and _quantity(display, 1) == "40", "and update when topped up")
	_check(_border(display, 3) == 2, "an item in hand is not highlighted before it is equipped")
	holder.toggle_inventory_slot(3)
	_check(_border(display, 3) == 3 and _border(display, 1) == 2, "the equipped slot is highlighted")
	holder.toggle_inventory_slot(3)
	_check(_border(display, 3) == 2, "and not any more once it is put away")
	hotbar.add(light, Vector2i(4, 0))
	_check(_icon(display, 3).texture == null and _icon(display, 4).texture == FLASHLIGHT.icon, "moving an item moves its picture")
	hotbar.remove(light)
	_check(_icon(display, 4).texture == null and _tooltip(display, 4) == "Empty", "and removing it clears the slot")
	display.free()
	_end_setup(setup)


## The real thing: the hand-wired Player scene.
func _test_player_scene() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	(player.get_node("ItemHolder") as ItemHolder).view = ItemHolder.View.AUTO
	var other := PLAYER_SCENE.instantiate() as CharacterBody3D
	var inventory := player.get_node("Inventory") as Inventory
	var holder := player.get_node("ItemHolder") as ItemHolder
	var display := player.get_node("CanvasLayer/InventoryHotbar") as InventoryHotbar
	_check(inventory != null and holder != null and display != null, "the player has an inventory, an item holder and a hotbar display")
	var hotbar := inventory.get_container(&"hotbar") as InventorySlotContainer
	_check(hotbar != null and hotbar.size == 4, "the player's inventory has a four-slot hotbar")
	_check(inventory.get_containers().size() == 3 and inventory.get_container(&"lamp") != null and inventory.get_container(&"back_slot") != null, "beside a back slot and a lamp slot, for lamps that are worn and not held")
	var light := hotbar.get_instance(0)
	_check(light is FlashlightInstance and light.item == FLASHLIGHT, "which starts with a flashlight in the first slot")
	_check(holder.inventory == inventory and holder.get_hotbar() == hotbar, "the holder reads that hotbar")

	var other_hotbar := (other.get_node("Inventory") as Inventory).get_container(&"hotbar") as InventorySlotContainer
	var other_light := other_hotbar.get_instance(0) as FlashlightInstance
	(light as FlashlightInstance).power_level = 40.0
	_check(other_light != null and other_light != light and other_light.power_level == 100.0, "another player has a flashlight of its own")
	other.free()

	add_child(player)
	await get_tree().process_frame
	_check(display.get_child_count() == 4, "the display shows four slots")
	_check(_tooltip(display, 0) == "Flashlight" and _icon(display, 0).texture == FLASHLIGHT.icon, "with the flashlight in the first")
	_check(_tooltip(display, 2) == "Empty", "and empty slots after the starting items")
	await _press(&"inventory_slot_1")
	_check(holder.equipped_instance == light, "key 1 equips the flashlight")
	var mount := holder.actor_parent
	_check(mount.get_child_count() == 1 and mount.get_child(0) is FlashlightActor, "on the player's item mount")
	_check((holder.equipped_actor as FlashlightActor).flashlight_instance == light, "using the player's own flashlight")
	_check(_border(display, 0) == 3, "and the display shows it in hand")
	await _press(&"inventory_slot_1")
	_check(not holder.has_equipped_item() and _border(display, 0) == 2, "pressing 1 again puts it away")
	player.free()


# --- Helpers -----------------------------------------------------------------

## An inventory with a hotbar of the given size and a backpack, a holder reading it, and a mount.
func _make_setup(hotbar_size: int) -> Dictionary:
	var mount := Node3D.new()
	add_child(mount)
	var hotbar := InventorySlotContainer.new()
	hotbar.id = &"hotbar"
	hotbar.size = hotbar_size
	var backpack := InventoryGridContainer.new()
	backpack.id = &"backpack"
	var inventory := Inventory.new()
	inventory.containers.append(hotbar)
	inventory.containers.append(backpack)
	add_child(inventory)
	var holder := ItemHolder.new()
	holder.inventory = inventory
	holder.actor_parent = mount
	add_child(holder)
	return {
		"mount": mount,
		"inventory": inventory,
		"holder": holder,
		# The inventory works on its own copy, so use that one.
		"hotbar": inventory.get_container(&"hotbar"),
	}


func _end_setup(setup: Dictionary) -> void:
	for key in ["holder", "inventory", "mount"]:
		(setup[key] as Node).free()


## Presses an input action the way the engine would deliver it, then lets it be handled.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func _slot(display: InventoryHotbar, index: int) -> PanelContainer:
	return display.get_child(index) as PanelContainer


func _icon(display: InventoryHotbar, index: int) -> TextureRect:
	return _slot(display, index).get_child(0) as TextureRect


func _quantity(display: InventoryHotbar, index: int) -> String:
	return (_slot(display, index).get_child(2) as Label).text


func _tooltip(display: InventoryHotbar, index: int) -> String:
	return _slot(display, index).tooltip_text


## The slot's border width: the equipped slot is drawn thicker.
func _border(display: InventoryHotbar, index: int) -> int:
	return (_slot(display, index).get_theme_stylebox(&"panel") as StyleBoxFlat).border_width_left


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("ITEM HOLDER TEST FAILED: " + message)
	print("FAIL: ", message)
