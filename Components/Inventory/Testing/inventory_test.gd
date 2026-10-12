extends Node
## Headless checks for Inventory and its slot and grid containers.
##
## godot --headless --path . res://Components/Inventory/Testing/InventoryTest.tscn

var _failures := 0

var _flashlight: Item ## 2 x 1, a tool
var _rifle: Item ## 6 x 2
var _bullets: Item ## 1 x 1, stacks to 100
var _plank: Item ## 1 x 3
var _fuse: Item ## 1 x 1
var _pebble: Item ## 1 x 1, does not stack


func _ready() -> void:
	_flashlight = _make_item(&"flashlight", Vector2i(2, 1), 1, [&"tool"])
	_rifle = _make_item(&"rifle", Vector2i(6, 2), 1, [&"weapon"])
	_bullets = _make_item(&"bullets", Vector2i(1, 1), 100, [&"ammo"])
	_plank = _make_item(&"plank", Vector2i(1, 3), 1, [])
	_fuse = _make_item(&"fuse", Vector2i(1, 1), 1, [])
	_pebble = _make_item(&"pebble", Vector2i(1, 1), 1, [])
	var only := OS.get_environment("ONLY")
	for test_name in [
		"filters", "slot", "hotbar", "slot_numbers", "tool_belt", "slot_stacking", "slot_count", "grid",
		"rotation", "moving_in_grid", "stacking", "layout", "scene_copies", "starting_items", "fuse_box",
		"moves", "signals", "containers", "fuzz",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			call("_test_" + test_name)
	if _failures == 0:
		print("Inventory tests passed.")
	else:
		print("Inventory tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_filters() -> void:
	var slot := InventorySlotContainer.new()
	_check(slot.accepts(_make(_rifle)), "a container with no filter accepts anything")
	_check(not slot.accepts(null), "but not nothing")
	_check(not slot.accepts(Item.new().create_instance()), "or an item that was never set up")
	slot.accepted_tags = [&"tool"]
	_check(slot.accepts(_make(_flashlight)), "a tag filter takes items with the tag")
	_check(not slot.accepts(_make(_rifle)), "and refuses the rest")
	slot.accepted_tags = []
	slot.accepted_items = [_fuse]
	_check(slot.accepts(_make(_fuse)), "an item filter takes that item")
	_check(not slot.accepts(_make(_pebble)) and not slot.accepts(_make(_flashlight)), "and nothing else")
	slot.accepted_tags = [&"tool"]
	_check(
		slot.accepts(_make(_fuse)) and slot.accepts(_make(_flashlight)) and not slot.accepts(_make(_rifle)),
		"tags and items together take either"
	)
	var grid := InventoryGridContainer.new()
	grid.accepted_tags = [&"ammo"]
	_check(grid.add(_make(_bullets, 5)) and not grid.add(_make(_pebble)), "a grid can be filtered too")


func _test_slot() -> void:
	var slot := InventorySlotContainer.new()
	var light := _make(_flashlight)
	_check(slot.is_empty() and slot.get_instance() == null, "a new slot is empty")
	_check(slot.add(light), "a slot takes an item")
	_check(slot.get_instance() == light and slot.has_instance(light) and not slot.is_empty(), "and holds it")
	var pebble := _make(_pebble)
	_check(not slot.can_add(pebble) and not slot.add(pebble), "a full slot refuses another kind of item")
	_check(slot.get_instance() == light, "and keeps what it had")
	_check(slot.remove(light) and slot.is_empty() and slot.get_instance() == null, "an item can be taken out")
	_check(not slot.remove(light), "but only once")
	var rifle := _make(_rifle)
	_check(slot.add(rifle) and slot.get_instance() == rifle, "a slot ignores the size of what it holds")
	slot.clear()
	_check(slot.is_empty(), "clear empties it")

	var first := _make(_bullets, 30)
	slot.add(first)
	var more := _make(_bullets, 40)
	_check(slot.add(more), "more of the same stacks")
	_check(slot.get_instance() == first and first.quantity == 70 and not slot.has_instance(more), "into the stack that was there")
	var too_many := _make(_bullets, 40)
	_check(not slot.can_add(too_many) and not slot.add(too_many), "a stack that would overflow is refused whole")
	_check(first.quantity == 70 and too_many.quantity == 40, "and nothing moves")
	_check(slot.add(_make(_bullets, 30)) and first.quantity == 100, "up to a full stack")
	_check(slot.get_count(_bullets) == 100, "get_count adds up the units")
	_check(slot.remove_quantity(first, 40) and first.quantity == 60, "units can be taken off a stack")
	_check(not slot.remove_quantity(first, 61) and first.quantity == 60, "but not more than there are")
	_check(slot.remove_quantity(first, 60) and slot.is_empty(), "taking the last ones empties the slot")


## One container with many slots, so a whole hotbar is a single entry in the list.
func _test_hotbar() -> void:
	var hotbar := InventorySlotContainer.new()
	hotbar.size = 9
	_check(hotbar.size == 9 and hotbar.is_empty(), "a slot container can have many slots")
	var held: Array[ItemInstance] = []
	for number in 9:
		var instance := _make(_pebble if number % 2 == 0 else _fuse)
		held.append(instance)
		_check(hotbar.add(instance) and hotbar.get_slot_of(instance) == number, "item %d goes in slot %d" % [number, number])
	_check(hotbar.get_instances() == held, "and they are listed in slot order")
	var tenth := _make(_pebble)
	_check(not hotbar.can_add(tenth) and not hotbar.add(tenth), "a full hotbar refuses more")
	_check(hotbar.get_instance(4) == held[4], "a slot is read by number")
	_check(hotbar.get_instance(9) == null and hotbar.get_instance(-1) == null, "and a slot that does not exist is empty")
	_check(hotbar.remove(held[3]) and hotbar.get_instance(3) == null and hotbar.get_slot_of(held[3]) == -1, "taking one out leaves a gap")
	var filler := _make(_pebble)
	_check(hotbar.add(filler) and hotbar.get_slot_of(filler) == 3, "which the next item fills")
	hotbar.clear()
	var rifle := _make(_rifle)
	var plank := _make(_plank)
	_check(hotbar.add(rifle) and hotbar.add(plank), "every slot ignores item size")
	_check(hotbar.get_slot_of(rifle) == 0 and hotbar.get_slot_of(plank) == 1, "a rifle and a plank take a slot each")


func _test_slot_numbers() -> void:
	var hotbar := InventorySlotContainer.new()
	hotbar.size = 5
	var first := _make(_pebble)
	_check(hotbar.add(first, Vector2i(3, 0)) and hotbar.get_slot_of(first) == 3, "an item goes in the slot it is told")
	var second := _make(_pebble)
	_check(not hotbar.can_add(second, Vector2i(3, 0)) and not hotbar.add(second, Vector2i(3, 0)), "but not into a taken one")
	_check(not hotbar.add(second, Vector2i(5, 0)) and not hotbar.add(second, Vector2i(-2, 0)), "or one that does not exist")
	_check(not hotbar.add(second, Vector2i(1, 1)), "a slot container has one row")
	_check(hotbar.add(second) and hotbar.get_slot_of(second) == 0, "without a slot, the first free one is used")
	var heard := _watch(hotbar)
	_check(hotbar.add(first, Vector2i(4, 0)) and hotbar.get_slot_of(first) == 4, "an item can move to another slot")
	_check(hotbar.get_instance(3) == null, "leaving its old one empty")
	_check(heard["changed"] == [first] and heard["added"].is_empty() and heard["removed"].is_empty(), "which is a change, not a new item")
	_check(not hotbar.add(first, Vector2i(0, 0)) and hotbar.get_slot_of(first) == 4, "but not onto another item")
	_check(hotbar.add(first, Vector2i(4, 0)), "and moving to the slot it is already in is fine")
	var other := InventorySlotContainer.new()
	other.size = 3
	_check(hotbar.move_to(first, other, Vector2i(2, 0)) and other.get_slot_of(first) == 2, "an item moves to a chosen slot of another container")
	_check(not hotbar.move_to(second, other, Vector2i(2, 0)) and hotbar.get_slot_of(second) == 0, "and a taken slot refuses, leaving the item where it was")
	_check(hotbar.move_to(second, hotbar, Vector2i(2, 0)) and hotbar.get_slot_of(second) == 2, "moving within one container works the same")


## A belt that takes tools: every slot follows the container's filter, whatever the tool's size.
func _test_tool_belt() -> void:
	var belt := InventorySlotContainer.new()
	belt.size = 4
	belt.accepted_tags = [&"tool"]
	var drill := _make_item(&"drill", Vector2i(4, 4), 1, [&"tool"])
	for number in 3:
		var light := _make(_flashlight)
		_check(belt.add(light) and belt.get_slot_of(light) == number, "tool %d goes in slot %d" % [number, number])
	var big := _make(drill)
	_check(belt.add(big) and belt.get_slot_of(big) == 3, "a 4 x 4 tool fits a slot as easily as a small one")
	_check(not belt.add(_make(_flashlight)), "a full belt refuses more")
	belt.clear()
	_check(not belt.add(_make(_pebble)) and not belt.add(_make(_rifle)), "no slot takes what is not a tool")
	_check(not belt.add(_make(_pebble), Vector2i(2, 0)), "even when asked for by number")
	var light := _make(_flashlight)
	_check(belt.add(light, Vector2i(2, 0)) and belt.get_slot_of(light) == 2, "but a tool can be put in any slot")


func _test_slot_stacking() -> void:
	var hotbar := InventorySlotContainer.new()
	hotbar.size = 3
	var first := _make(_bullets, 60)
	hotbar.add(first)
	var second := _make(_bullets, 60)
	_check(hotbar.add(second), "a second stack goes in")
	_check(first.quantity == 100 and hotbar.get_slot_of(second) == 1 and second.quantity == 20, "after topping up the first, keeping the rest in the next slot")
	var third := _make(_bullets, 30)
	_check(hotbar.add(third) and second.quantity == 50 and not hotbar.has_instance(third), "the next tops up the stack with room, and disappears into it")
	_check(hotbar.get_count(_bullets) == 150 and hotbar.get_instances().size() == 2, "no units are lost")
	_check(not hotbar.add(_make(_bullets, 10), Vector2i(0, 0)), "naming a taken slot never merges")
	var tight := InventorySlotContainer.new()
	var some := _make(_bullets, 90)
	tight.add(some)
	var twenty := _make(_bullets, 20)
	_check(not tight.can_add(twenty) and not tight.add(twenty), "when it would overflow and there is no free slot, it is refused")
	_check(some.quantity == 90 and twenty.quantity == 20, "whole, with nothing moved")
	_check(tight.add(_make(_bullets, 10)) and some.quantity == 100, "what fits is taken")


func _test_slot_count() -> void:
	var hotbar := InventorySlotContainer.new()
	_check(hotbar.size == 1, "a slot container has one slot unless told otherwise")
	hotbar.size = 0
	_check(hotbar.size == 1, "and never fewer")
	hotbar.size = 6
	var item := _make(_pebble)
	hotbar.add(item, Vector2i(4, 0))
	hotbar.size = 2
	_check(hotbar.size == 5, "it shrinks only as far as the items inside allow")
	hotbar.remove(item)
	hotbar.size = 2
	_check(hotbar.size == 2, "and further once they are out")
	_check(not hotbar.add(_make(_pebble), Vector2i(3, 0)), "the slots that are gone are gone")
	hotbar.size = 4
	var later := _make(_pebble)
	_check(hotbar.add(later, Vector2i(3, 0)), "and it can grow")


func _test_grid() -> void:
	var grid := InventoryGridContainer.new()
	grid.size = Vector2i(4, 3)
	var first := _make(_flashlight)
	_check(grid.is_empty(), "a new grid is empty")
	_check(grid.add(first) and grid.get_rect(first) == Rect2i(0, 0, 2, 1), "the first item goes in the corner")
	var second := _make(_flashlight)
	grid.add(second)
	_check(grid.get_rect(second) == Rect2i(2, 0, 2, 1), "the next goes beside it")
	var third := _make(_flashlight)
	grid.add(third)
	_check(grid.get_rect(third) == Rect2i(0, 1, 2, 1), "and the next row starts when the row is full")
	_check(grid.get_instance_at(Vector2i(1, 0)) == first and grid.get_instance_at(Vector2i(3, 0)) == second, "get_instance_at finds what covers a cell")
	_check(grid.get_instance_at(Vector2i(3, 2)) == null and grid.get_instance_at(Vector2i(9, 9)) == null, "and null for an empty or missing one")
	_check(grid.get_instances().size() == 3 and grid.has_instance(second), "the grid knows what it holds")

	var fourth := _make(_flashlight)
	_check(not grid.can_add(fourth, Vector2i(1, 0)) and not grid.add(fourth, Vector2i(1, 0)), "placing on top of an item is refused")
	_check(not grid.add(fourth, Vector2i(3, 2)), "so is hanging off the right edge")
	_check(not grid.add(fourth, Vector2i(0, 3)), "and off the bottom")
	_check(not grid.add(fourth, Vector2i(-1, 2)), "and off the left")
	_check(grid.get_instances().size() == 3, "a refused item leaves no trace")
	_check(grid.add(fourth, Vector2i(2, 1)) and grid.get_rect(fourth) == Rect2i(2, 1, 2, 1), "an item goes exactly where it is told")
	var fifth := _make(_flashlight)
	_check(grid.add(fifth) and grid.get_rect(fifth) == Rect2i(0, 2, 2, 1), "auto-placement finds the gap left over")
	var sixth := _make(_flashlight)
	_check(grid.add(sixth) and grid.get_rect(sixth) == Rect2i(2, 2, 2, 1), "and the next")
	var seventh := _make(_pebble)
	_check(not grid.can_add(seventh) and not grid.add(seventh), "a full grid refuses more")
	_check(grid.remove(third), "an item can be taken out")
	_check(grid.get_rect(third) == Rect2i() and grid.get_instance_at(Vector2i(0, 1)) == null, "which frees its cells")
	_check(grid.add(seventh) and grid.get_rect(seventh) == Rect2i(0, 1, 1, 1), "for the next one")

	var huge := InventoryGridContainer.new()
	huge.size = Vector2i(3, 3)
	_check(not huge.can_add(_make(_rifle)), "an item bigger than the grid never fits")

	var grown := InventoryGridContainer.new()
	grown.size = Vector2i(2, 2)
	var plank := _make(_plank)
	_check(not grown.can_add(plank), "a plank does not fit a 2 x 2 grid")
	grown.size = Vector2i(4, 4)
	_check(grown.add(plank), "but fits once the grid grows")
	grown.size = Vector2i(1, 1)
	_check(grown.size == Vector2i(1, 3), "a grid shrinks only as far as what is inside allows")
	_check(grown.get_rect(plank) == Rect2i(0, 0, 1, 3), "and leaves the item alone")
	_check(InventoryGridContainer.new().get_rect(plank) == Rect2i(), "an item that is not here has an empty rect")


func _test_rotation() -> void:
	var tall := InventoryGridContainer.new()
	tall.size = Vector2i(4, 6)
	var rifle := _make(_rifle)
	_check(tall.add(rifle), "a rifle goes in a grid that is tall but not wide")
	_check(tall.is_rotated(rifle) and tall.get_rect(rifle) == Rect2i(0, 0, 2, 6), "turned on its side")
	var wide := InventoryGridContainer.new()
	var upright := _make(_rifle)
	_check(wide.add(upright) and not wide.is_rotated(upright) and wide.get_rect(upright) == Rect2i(0, 0, 6, 2), "and stays upright when it fits")
	var small := InventoryGridContainer.new()
	small.size = Vector2i(4, 3)
	_check(not small.can_add(_make(_rifle)), "it is refused when it fits neither way")
	var room := InventoryGridContainer.new()
	room.size = Vector2i(6, 6)
	var chosen := _make(_rifle)
	_check(room.add(chosen, Vector2i(4, 0), true), "an item can be placed turned")
	_check(room.get_rect(chosen) == Rect2i(4, 0, 2, 6) and room.is_rotated(chosen), "covering its turned cells")
	_check(not room.add(_make(_pebble), Vector2i(5, 3)), "which are really taken")
	_check(not room.add(_make(_rifle), Vector2i(0, 0), false), "an upright rifle cannot cross it")
	_check(not room.add(_make(_rifle), Vector2i(3, 0), true), "nor can another turned one overlap it")
	var beside := _make(_rifle)
	_check(room.add(beside, Vector2i(2, 0), true) and room.get_rect(beside) == Rect2i(2, 0, 2, 6), "but one fits right beside it")
	var square := InventoryGridContainer.new()
	square.size = Vector2i(2, 2)
	square.add(_make(_pebble))
	var block := _make(_pebble)
	_check(square.add(block) and not square.is_rotated(block), "something square is never turned for no reason")


func _test_moving_in_grid() -> void:
	var grid := InventoryGridContainer.new()
	grid.size = Vector2i(4, 4)
	var plank := _make(_plank)
	var heard := _watch(grid)
	grid.add(plank)
	_check(grid.get_rect(plank) == Rect2i(0, 0, 1, 3), "a plank stands up in the corner")
	_check(grid.add(plank, Vector2i(0, 0), true), "it can be turned where it stands")
	_check(grid.get_rect(plank) == Rect2i(0, 0, 3, 1) and grid.is_rotated(plank), "using its own cells")
	_check(grid.add(plank, Vector2i(1, 2), true) and grid.get_rect(plank) == Rect2i(1, 2, 3, 1), "and moved")
	_check(grid.get_instances().size() == 1, "still one plank")
	_check(heard["added"].size() == 1 and heard["changed"].size() == 2 and heard["removed"].is_empty(), "moving reports a change, not a new item")
	grid.add(plank, Vector2i(0, 0), true)
	grid.add(_make(_pebble), Vector2i(0, 2))
	_check(not grid.can_add(plank, Vector2i(0, 0), false) and not grid.add(plank, Vector2i(0, 0), false), "standing it back up is refused when it would hit something")
	_check(grid.get_rect(plank) == Rect2i(0, 0, 3, 1) and grid.is_rotated(plank), "and the plank stays as it was")
	_check(grid.add(plank, Vector2i(1, 0), false) and grid.get_rect(plank) == Rect2i(1, 0, 1, 3), "but is fine where there is room")
	var steady := grid.get_rect(plank)
	_check(grid.add(plank) and grid.get_rect(plank) == steady, "adding what is already inside with no cell changes nothing")


func _test_stacking() -> void:
	var grid := InventoryGridContainer.new()
	grid.size = Vector2i(4, 1)
	var first := _make(_bullets, 60)
	grid.add(first)
	var second := _make(_bullets, 60)
	_check(grid.add(second), "a second stack goes in")
	_check(first.quantity == 100, "after topping up the first")
	_check(grid.has_instance(second) and second.quantity == 20, "and keeps the rest as its own")
	_check(grid.get_instances().size() == 2 and grid.get_count(_bullets) == 120, "no units are lost")
	var third := _make(_bullets, 30)
	_check(grid.add(third) and second.quantity == 50 and not grid.has_instance(third), "the next tops up the stack with room, and disappears into it")
	_check(grid.get_instances().size() == 2, "without taking a cell")
	_check(grid.get_instance_at(Vector2i(0, 0)) == first and grid.get_instance_at(Vector2i(1, 0)) == second, "stacks take one cell each")

	var tight := InventoryGridContainer.new()
	tight.size = Vector2i(1, 1)
	var some := _make(_bullets, 90)
	tight.add(some)
	var twenty := _make(_bullets, 20)
	_check(not tight.can_add(twenty) and not tight.add(twenty), "when the stack would overflow and there is no room, it is refused")
	_check(some.quantity == 90 and twenty.quantity == 20, "whole, with nothing moved")
	var ten := _make(_bullets, 10)
	_check(tight.add(ten) and some.quantity == 100, "what fits is taken")
	_check(not tight.add(_make(_bullets, 1)), "a full stack takes no more")

	var singles := InventoryGridContainer.new()
	singles.size = Vector2i(4, 1)
	var first_pebble := _make(_pebble)
	var second_pebble := _make(_pebble)
	singles.add(first_pebble)
	singles.add(second_pebble)
	_check(singles.get_instances().size() == 2, "items that do not stack take a cell each")
	var mixed := InventoryGridContainer.new()
	mixed.size = Vector2i(4, 1)
	var lead := _make(_bullets, 10)
	mixed.add(lead)
	mixed.add(_make(_fuse))
	mixed.add(_make(_bullets, 5))
	_check(lead.quantity == 15 and mixed.get_instances().size() == 2, "and different items never merge")
	_check(mixed.remove_quantity(lead, 5) and lead.quantity == 10, "units come off a stack in a grid")
	_check(mixed.remove_quantity(lead, 10) and not mixed.has_instance(lead), "removing them all removes the stack")


## The player layout from the design: a hotbar, a belt that only takes tools, a backpack.
func _test_layout() -> void:
	var player := _make_player()
	var hotbar := player.get_container(&"hotbar") as InventorySlotContainer
	var belt := player.get_container(&"belt") as InventorySlotContainer
	var backpack := player.get_container(&"backpack") as InventoryGridContainer
	_check(hotbar != null and belt != null and backpack != null, "containers are found by id")
	_check(player.get_container(&"nothing") == null, "and a missing id is null")
	_check(player.get_containers().size() == 3, "the list is in order")
	var light_a := _make(_flashlight)
	var light_b := _make(_flashlight)
	var light_c := _make(_flashlight)
	var light_d := _make(_flashlight)
	_check(player.add(light_a) and hotbar.get_instance(0) == light_a, "an item goes to the first container that takes it")
	_check(player.add(light_b) and hotbar.get_instance(1) == light_b, "then the next slot")
	_check(player.add(light_c) and belt.get_instance() == light_c, "a tool goes on the belt when the hotbar is full")
	_check(player.add(light_d) and backpack.has_instance(light_d), "and in the backpack when the belt is too")
	var rifle := _make(_rifle)
	_check(not player.add(rifle), "a rifle fits nowhere here: the hotbar is full, the belt wants tools, the backpack is too small")
	var big_pack := InventoryGridContainer.new()
	big_pack.id = &"big_pack"
	player.add_container(big_pack)
	_check(player.add(rifle) and big_pack.has_instance(rifle), "until a bigger container is put on")
	_check(player.find_container_of(rifle) == big_pack and player.has_instance(rifle), "find_container_of says where it is")
	_check(player.find_container_of(_make(_pebble)) == null, "and null for a stranger")
	_check(not player.add(light_a) and hotbar.get_instance(0) == light_a and player.get_count(_flashlight) == 4, "adding what is already inside does nothing")
	_check(player.find_instances(_flashlight).size() == 4, "find_instances lists them")
	_check(player.remove(light_a) and hotbar.get_instance(0) == null and not player.has_instance(light_a), "an item can be removed from wherever it is")
	_check(not player.remove(light_a), "but only once")
	var bullets := _make(_bullets, 50)
	_check(player.add(bullets) and hotbar.get_instance(0) == bullets, "ammo takes the free hotbar slot")
	_check(player.remove_quantity(bullets, 20) and bullets.quantity == 30, "units come off a stack")
	_check(not player.remove_quantity(bullets, 31), "but not too many")
	_check(player.get_count(_bullets) == 30, "get_count adds across containers")
	player.free()


## A chest scene copied twice must not share its contents.
func _test_scene_copies() -> void:
	var chest := Node.new()
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	var cargo := InventoryGridContainer.new()
	cargo.id = &"cargo"
	cargo.starting_items = [_make(_bullets, 40)]
	inventory.containers.append(cargo)
	chest.add_child(inventory)
	inventory.owner = chest
	var packed := PackedScene.new()
	_check(packed.pack(chest) == OK, "a chest scene packs")
	chest.free()
	var first_chest := packed.instantiate()
	var second_chest := packed.instantiate()
	add_child(first_chest)
	add_child(second_chest)
	var first := first_chest.get_node("Inventory") as Inventory
	var second := second_chest.get_node("Inventory") as Inventory
	var first_cargo := first.get_container(&"cargo")
	var second_cargo := second.get_container(&"cargo")
	_check(first_cargo != second_cargo, "each chest gets its own container")
	_check(first.get_count(_bullets) == 40 and second.get_count(_bullets) == 40, "with its own starting items")
	first.add(_make(_flashlight))
	_check(first.get_count(_flashlight) == 1 and second.get_count(_flashlight) == 0, "so an item put in one is not in the other")
	_check(cargo.is_empty(), "and the layout itself stays empty")
	first.remove_quantity(first.find_instances(_bullets)[0], 10)
	_check(first.get_count(_bullets) == 30 and second.get_count(_bullets) == 40, "units spent from one are not spent from the other")
	_check(cargo.starting_items[0].quantity == 40, "or from the layout")
	first_chest.free()
	second_chest.free()


func _test_starting_items() -> void:
	var inventory := Inventory.new()
	var hand := InventorySlotContainer.new()
	hand.id = &"hand"
	hand.starting_items = [_make(_flashlight)]
	var bag := InventoryGridContainer.new()
	bag.id = &"bag"
	bag.starting_items = [_make(_bullets, 70), _make(_bullets, 70), _make(_rifle)]
	inventory.containers.append(hand)
	inventory.containers.append(bag)
	_check(inventory.get_container(&"hand") != null, "containers exist before the node is in a tree")
	add_child(inventory)
	_check(inventory.get_container(&"hand").get_instances().size() == 1, "a container starts with its starting items")
	_check(inventory.get_container(&"bag").get_count(_bullets) == 140, "stackable ones stack")
	_check(inventory.get_count(_rifle) == 1, "and every one is placed")
	_check(inventory.get_container(&"hand").starting_items.is_empty(), "they are not kept around as a second copy")
	inventory.free()


func _test_fuse_box() -> void:
	var fuse_box := Inventory.new()
	var socket := InventorySlotContainer.new()
	socket.id = &"fuse"
	socket.accepted_items = [_fuse]
	fuse_box.containers.append(socket)
	add_child(fuse_box)
	var fuse := _make(_fuse)
	_check(not fuse_box.add(_make(_flashlight)) and not fuse_box.add(_make(_pebble)), "a fuse box refuses everything but a fuse")
	_check(fuse_box.can_add(fuse) and fuse_box.add(fuse), "and takes a fuse")
	_check(fuse_box.get_container(&"fuse").get_instances() == [fuse], "which sits in the socket")
	_check(not fuse_box.add(_make(_fuse)), "only one")
	var player := _make_player()
	_check(fuse_box.transfer(fuse, player), "the fuse can be taken by a player")
	_check(fuse_box.get_count(_fuse) == 0 and player.get_count(_fuse) == 1, "out of the box and into the player")
	_check(player.transfer(fuse, fuse_box), "and put back")
	_check(fuse_box.find_instances(_fuse) == [fuse], "the same instance")
	fuse_box.free()
	player.free()


func _test_moves() -> void:
	var player := _make_player()
	var belt := player.get_container(&"belt") as InventorySlotContainer
	var backpack := player.get_container(&"backpack") as InventoryGridContainer
	var hotbar := player.get_container(&"hotbar") as InventorySlotContainer
	hotbar.add(_make(_pebble))
	hotbar.add(_make(_pebble))
	var light := _make(_flashlight)
	backpack.add(light, Vector2i(1, 1))
	_check(backpack.move_to(light, belt), "a tool moves from the backpack to the belt")
	_check(belt.get_instance() == light and not backpack.has_instance(light), "it left one and arrived in the other")
	_check(belt.move_to(light, backpack, Vector2i(2, 2)) and backpack.get_rect(light) == Rect2i(2, 2, 2, 1), "and back, to the cell asked for")
	var plank := _make(_plank)
	backpack.add(plank, Vector2i(0, 0))
	_check(not backpack.move_to(plank, belt), "the belt refuses what is not a tool")
	_check(backpack.get_rect(plank) == Rect2i(0, 0, 1, 3) and belt.is_empty(), "and the plank stays where it was")
	belt.add(_make(_flashlight))
	_check(not backpack.move_to(light, belt), "a full destination refuses")
	_check(backpack.get_rect(light) == Rect2i(2, 2, 2, 1), "and the item stays where it was")
	_check(not backpack.move_to(light, backpack, Vector2i(0, 0)), "moving within a grid onto something is refused")
	_check(backpack.get_rect(light) == Rect2i(2, 2, 2, 1), "and changes nothing")
	_check(backpack.move_to(light, backpack, Vector2i(2, 0)) and backpack.get_rect(light) == Rect2i(2, 0, 2, 1), "but a free place is fine")
	_check(not belt.move_to(light, belt), "an item that is not in a container cannot be moved from it")
	_check(not player.move(light, hotbar) and backpack.has_instance(light), "the node's move works the same (and fails the same)")
	hotbar.clear()
	_check(player.move(light, hotbar, Vector2i(1, 0)), "and finds where the item was")
	_check(hotbar.get_slot_of(light) == 1 and not backpack.has_instance(light), "putting it in the slot asked for")

	var bullets := _make(_bullets, 60)
	backpack.add(bullets)
	var more := _make(_bullets, 60)
	hotbar.clear()
	hotbar.add(more)
	_check(hotbar.move_to(more, backpack), "a stack moves into a grid")
	_check(bullets.quantity == 100 and backpack.get_count(_bullets) == 120 and hotbar.is_empty(), "topping up what was there")

	var chest := Inventory.new()
	var chest_grid := InventoryGridContainer.new()
	chest_grid.id = &"chest"
	chest_grid.size = Vector2i(2, 1)
	chest.containers.append(chest_grid)
	add_child(chest)
	var loot := _make(_bullets, 10)
	chest.get_container(&"chest").add(loot)
	_check(chest.transfer(loot, player) and player.get_count(_bullets) == 130, "taking ammo from a chest")
	_check(not chest.has_instance(loot) and player.has_instance(loot), "moves it into the first container of the player that takes it")
	var keepsake := _make(_pebble)
	chest.add(keepsake)
	var full_player := _make_player()
	for container in full_player.get_containers():
		container.accepted_items = [_fuse]
	_check(not chest.transfer(keepsake, full_player), "a player who cannot take it leaves the chest as it was")
	_check(chest.has_instance(keepsake), "with the item still in it")
	_check(not chest.transfer(keepsake, chest), "a chest with one container has nowhere else to move it")
	chest.free()
	full_player.free()
	player.free()


func _test_signals() -> void:
	var player := _make_player()
	var seen: Array[String] = []
	player.item_added.connect(func(container: InventoryContainer, _instance: ItemInstance) -> void: seen.append("added:" + container.id))
	player.item_removed.connect(func(container: InventoryContainer, _instance: ItemInstance) -> void: seen.append("removed:" + container.id))
	player.item_changed.connect(func(container: InventoryContainer, _instance: ItemInstance) -> void: seen.append("changed:" + container.id))
	var any := [0]
	player.changed.connect(func() -> void: any[0] += 1)
	var light := _make(_flashlight)
	player.add(light)
	_check(seen == ["added:hotbar"], "adding tells the inventory which container got it")
	player.move(light, player.get_container(&"backpack"))
	_check(seen == ["added:hotbar", "removed:hotbar", "added:backpack"], "a move is a removal, then an addition")
	_check(any[0] == 3, "and every change says the inventory changed")
	seen.clear()
	var bullets := _make(_bullets, 10)
	player.add(bullets)
	player.add(_make(_bullets, 10))
	player.get_container(&"hotbar").remove_quantity(bullets, 5)
	_check(seen == ["added:hotbar", "changed:hotbar", "changed:hotbar"], "stacking and spending are changes")
	seen.clear()
	player.add(_make(_pebble))
	player.get_container(&"hotbar").clear()
	_check(seen == ["added:hotbar", "removed:hotbar", "removed:hotbar"], "acting on a container directly is heard too")
	seen.clear()
	var slot_item := _make(_fuse)
	player.get_container(&"hotbar").add(slot_item, Vector2i(1, 0))
	player.get_container(&"hotbar").add(slot_item, Vector2i(0, 0))
	_check(seen == ["added:hotbar", "changed:hotbar"], "moving between slots is a change, not a new item")
	player.free()


func _test_containers() -> void:
	var inventory := Inventory.new()
	add_child(inventory)
	_check(inventory.get_containers().is_empty() and not inventory.add(_make(_pebble)), "an inventory with no containers holds nothing")
	var seen := [0]
	inventory.item_added.connect(func(_container: InventoryContainer, _instance: ItemInstance) -> void: seen[0] += 1)
	var pocket := InventorySlotContainer.new()
	pocket.id = &"pocket"
	inventory.add_container(pocket)
	_check(inventory.get_container(&"pocket") == pocket, "a container made in code is used as it is")
	_check(inventory.add(_make(_pebble)) and seen[0] == 1 and not pocket.is_empty(), "and holds items")
	_check(inventory.remove_container(pocket) and inventory.get_containers().is_empty(), "it can be taken out")
	_check(not pocket.is_empty(), "keeping its contents")
	pocket.clear()
	pocket.add(_make(_pebble))
	_check(seen[0] == 1, "and the inventory stops hearing from it")
	_check(not inventory.remove_container(pocket), "a container can only be taken out once")
	inventory.free()


func _test_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260511
	var all_items: Array[Item] = [_flashlight, _rifle, _bullets, _plank, _fuse, _pebble]
	var inventories: Array[Inventory] = []
	for number in 2:
		var inventory := Inventory.new()
		var hand := InventorySlotContainer.new()
		hand.id = &"hand"
		hand.size = 3
		var belt := InventorySlotContainer.new()
		belt.id = &"belt"
		belt.size = 2
		belt.accepted_tags = [&"tool"]
		var bag := InventoryGridContainer.new()
		bag.id = &"bag"
		bag.size = Vector2i(5, 4)
		var pouch := InventoryGridContainer.new()
		pouch.id = &"pouch"
		pouch.size = Vector2i(3, 3)
		pouch.accepted_items = [_bullets, _pebble]
		inventory.containers.append(hand)
		inventory.containers.append(belt)
		inventory.containers.append(bag)
		inventory.containers.append(pouch)
		add_child(inventory)
		inventories.append(inventory)
	var expected: Dictionary[Item, int] = {}
	for item in all_items:
		expected[item] = 0
	var accepted_adds := 0
	var accepted_moves := 0
	var refused := 0
	for step in 2500:
		var operation := rng.randi_range(0, 9)
		var inventory := inventories[rng.randi_range(0, 1)]
		var held := _list_held(inventories)
		var before := _snapshot(inventories)
		var problem := ""
		if operation <= 3 or held.is_empty():
			var item := all_items[rng.randi_range(0, all_items.size() - 1)]
			var quantity := rng.randi_range(1, item.max_stack_size)
			var instance := _make(item, quantity)
			var predicted := inventory.can_add(instance)
			var added := inventory.add(instance)
			if added != predicted:
				problem = "can_add said %s but add said %s" % [predicted, added]
			elif added:
				expected[item] += quantity
				accepted_adds += 1
			else:
				refused += 1
				if instance.quantity != quantity or before != _snapshot(inventories):
					problem = "a refused add changed something"
		elif operation <= 6:
			var entry: Dictionary = held[rng.randi_range(0, held.size() - 1)]
			var source: InventoryContainer = entry["container"]
			var instance: ItemInstance = entry["instance"]
			var target_inventory := inventories[rng.randi_range(0, 1)]
			var targets := target_inventory.get_containers()
			var destination := targets[rng.randi_range(0, targets.size() - 1)]
			var cell := InventoryContainer.AUTO_CELL
			if rng.randi_range(0, 1) == 1:
				var row := 0 if rng.randi_range(0, 1) == 0 else rng.randi_range(-1, 5)
				cell = Vector2i(rng.randi_range(-1, 6), row)
			var rotated := rng.randi_range(0, 1) == 1
			var predicted := destination.can_add(instance, cell, rotated)
			var moved := source.move_to(instance, destination, cell, rotated)
			if moved != predicted:
				problem = "can_add said %s but move_to said %s" % [predicted, moved]
			elif moved:
				accepted_moves += 1
			else:
				refused += 1
				if before != _snapshot(inventories):
					problem = "a refused move changed something"
		elif operation == 7:
			var entry: Dictionary = held[rng.randi_range(0, held.size() - 1)]
			var instance: ItemInstance = entry["instance"]
			var quantity := instance.quantity
			var item := instance.item
			var owner_inventory := _inventory_of(inventories, instance)
			if not owner_inventory.remove(instance):
				problem = "remove failed for something that was inside"
			else:
				expected[item] -= quantity
		elif operation == 8:
			var entry: Dictionary = held[rng.randi_range(0, held.size() - 1)]
			var instance: ItemInstance = entry["instance"]
			var amount := rng.randi_range(1, instance.quantity + 1)
			var predicted := amount <= instance.quantity
			var item := instance.item
			var ok := _inventory_of(inventories, instance).remove_quantity(instance, amount)
			if ok != predicted:
				problem = "remove_quantity of %d from %d said %s" % [amount, instance.quantity, ok]
			elif ok:
				expected[item] -= amount
		else:
			var entry: Dictionary = held[rng.randi_range(0, held.size() - 1)]
			var instance: ItemInstance = entry["instance"]
			var source_inventory := _inventory_of(inventories, instance)
			var other := inventories[rng.randi_range(0, 1)]
			var source: InventoryContainer = entry["container"]
			var predicted := false
			for destination in other.get_containers():
				if destination != source and destination.can_add(instance):
					predicted = true
					break
			var moved := source_inventory.transfer(instance, other)
			if moved != predicted:
				problem = "transfer predicted %s but said %s" % [predicted, moved]
			elif not moved and before != _snapshot(inventories):
				problem = "a refused transfer changed something"
		if problem.is_empty():
			problem = _find_broken_rule(inventories, expected)
		if not problem.is_empty():
			_check(false, "fuzz step %d (operation %d): %s" % [step, operation, problem])
			break
	_check(accepted_adds > 100 and accepted_moves > 50 and refused > 50, "the fuzz run did real work (%d adds, %d moves, %d refusals)" % [accepted_adds, accepted_moves, refused])
	for inventory in inventories:
		inventory.free()


# --- Helpers -----------------------------------------------------------------

func _make_item(id: StringName, grid_size: Vector2i, max_stack: int, tags: Array[StringName]) -> Item:
	var item := Item.new()
	item.id = id
	item.display_name = String(id).capitalize()
	item.grid_size = grid_size
	item.max_stack_size = max_stack
	item.tags = tags
	return item


func _make(item: Item, quantity: int = 1) -> ItemInstance:
	return item.create_instance(quantity)


## A hotbar of two slots, a belt slot that takes tools, and a small backpack.
func _make_player() -> Inventory:
	var inventory := Inventory.new()
	var hotbar := InventorySlotContainer.new()
	hotbar.id = &"hotbar"
	hotbar.size = 2
	inventory.containers.append(hotbar)
	var belt := InventorySlotContainer.new()
	belt.id = &"belt"
	belt.accepted_tags = [&"tool"]
	inventory.containers.append(belt)
	var backpack := InventoryGridContainer.new()
	backpack.id = &"backpack"
	backpack.size = Vector2i(4, 3)
	inventory.containers.append(backpack)
	add_child(inventory)
	return inventory


## Counts what a container announces.
func _watch(container: InventoryContainer) -> Dictionary:
	var heard := {"added": [], "removed": [], "changed": []}
	container.item_added.connect(func(instance: ItemInstance) -> void: heard["added"].append(instance))
	container.item_removed.connect(func(instance: ItemInstance) -> void: heard["removed"].append(instance))
	container.item_changed.connect(func(instance: ItemInstance) -> void: heard["changed"].append(instance))
	return heard


func _list_held(inventories: Array[Inventory]) -> Array[Dictionary]:
	var held: Array[Dictionary] = []
	for inventory in inventories:
		for container in inventory.get_containers():
			for instance in container.get_instances():
				held.append({"container": container, "instance": instance})
	return held


func _inventory_of(inventories: Array[Inventory], instance: ItemInstance) -> Inventory:
	for inventory in inventories:
		if inventory.has_instance(instance):
			return inventory
	return null


## Everything about where every item is, as text, so two moments can be compared.
func _snapshot(inventories: Array[Inventory]) -> String:
	var lines: Array[String] = []
	for inventory in inventories:
		for container in inventory.get_containers():
			var parts: Array[String] = []
			for instance in container.get_instances():
				var where := ""
				if container is InventoryGridContainer:
					var grid := container as InventoryGridContainer
					where = "%s %s" % [grid.get_rect(instance), grid.is_rotated(instance)]
				elif container is InventorySlotContainer:
					where = "slot %d" % (container as InventorySlotContainer).get_slot_of(instance)
				parts.append("%d x%d %s" % [instance.get_instance_id(), instance.quantity, where])
			parts.sort()
			lines.append("%d [%s]" % [container.get_instance_id(), ", ".join(parts)])
	return "\n".join(lines)


## The rules that must hold after every operation. Returns what is wrong, or "".
func _find_broken_rule(inventories: Array[Inventory], expected: Dictionary[Item, int]) -> String:
	var seen: Dictionary[ItemInstance, bool] = {}
	for inventory in inventories:
		for container in inventory.get_containers():
			var taken: Dictionary[Vector2i, bool] = {}
			for instance in container.get_instances():
				if seen.has(instance):
					return "an item is in two places"
				seen[instance] = true
				if instance.quantity < 1 or instance.quantity > instance.item.max_stack_size:
					return "a stack has %d units of at most %d" % [instance.quantity, instance.item.max_stack_size]
				if not container.accepts(instance):
					return "a container holds something its filter refuses"
				if container is InventorySlotContainer:
					var slots := container as InventorySlotContainer
					var slot := slots.get_slot_of(instance)
					if slot < 0 or slot >= slots.size or slots.get_instance(slot) != instance:
						return "an item is not really in slot %d of %d" % [slot, slots.size]
				if container is InventoryGridContainer:
					var grid := container as InventoryGridContainer
					var rect := grid.get_rect(instance)
					if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > grid.size.x or rect.end.y > grid.size.y:
						return "an item hangs off the grid: %s" % rect
					for y in range(rect.position.y, rect.end.y):
						for x in range(rect.position.x, rect.end.x):
							if taken.has(Vector2i(x, y)):
								return "two items share cell %s" % Vector2i(x, y)
							taken[Vector2i(x, y)] = true
	for item: Item in expected:
		var total := 0
		for inventory in inventories:
			total += inventory.get_count(item)
		if total != expected[item]:
			return "%s: %d units exist but %d were expected" % [item.id, total, expected[item]]
	return ""


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("INVENTORY TEST FAILED: " + message)
	print("FAIL: ", message)
