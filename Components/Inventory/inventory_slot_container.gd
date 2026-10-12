class_name InventorySlotContainer
extends InventoryContainer
## A row of slots that each hold one item, of any size: a hotbar, a tool belt, a helmet, the
## socket of a fuse box. Every slot follows the container's filters, so a belt that takes tools
## takes them in all its slots. A stackable item can be a stack, so a slot can hold twenty medkits.
##
## To place an item in a particular slot, pass [code]Vector2i(slot, 0)[/code] as the cell.

## How many slots there are. Can grow with items inside, but never gets smaller than they need.
@export_range(1, 64, 1, "or_greater") var size := 1:
	set(value):
		size = maxi(value, 1)
		for slot: int in _slots:
			size = maxi(size, slot + 1)

## Slot number to what is in it. Empty slots have no entry.
var _slots: Dictionary[int, ItemInstance] = {}


## What is in a slot, or null if it is empty or does not exist.
func get_instance(slot: int = 0) -> ItemInstance:
	return _slots[slot] if _slots.has(slot) else null


## The slot an instance is in, or -1.
func get_slot_of(instance: ItemInstance) -> int:
	if instance == null:
		return -1
	for slot: int in _slots:
		if _slots[slot] == instance:
			return slot
	return -1


## Everything held, in slot order.
func get_instances() -> Array[ItemInstance]:
	var held: Array[ItemInstance] = []
	for slot in size:
		if _slots.has(slot):
			held.append(_slots[slot])
	return held


func has_instance(instance: ItemInstance) -> bool:
	return get_slot_of(instance) != -1


func can_add(instance: ItemInstance, cell: Vector2i = AUTO_CELL, _rotated: bool = false) -> bool:
	if not accepts(instance):
		return false
	if cell != AUTO_CELL:
		return _is_open(instance, cell)
	return has_instance(instance) or _get_stack_space(instance) >= instance.quantity or _find_empty_slot() != -1


func add(instance: ItemInstance, cell: Vector2i = AUTO_CELL, _rotated: bool = false) -> bool:
	if not can_add(instance, cell):
		return false
	if cell != AUTO_CELL:
		_store(instance, cell.x)
		return true
	if has_instance(instance):
		return true
	var left := _fill_stacks(instance)
	if left == 0:
		return true
	instance.quantity = left
	_store(instance, _find_empty_slot())
	return true


func remove(instance: ItemInstance) -> bool:
	var slot := get_slot_of(instance)
	if slot == -1:
		return false
	_slots.erase(slot)
	_notify_removed(instance)
	return true


func _store(instance: ItemInstance, slot: int) -> void:
	var was_inside := has_instance(instance)
	if was_inside:
		_slots.erase(get_slot_of(instance))
	_slots[slot] = instance
	if was_inside:
		_notify_changed(instance)
	else:
		_notify_added(instance)


## Whether the instance could sit in the slot the cell names: it exists, and is empty or already ours.
func _is_open(instance: ItemInstance, cell: Vector2i) -> bool:
	if cell.y != 0 or cell.x < 0 or cell.x >= size:
		return false
	return not _slots.has(cell.x) or _slots[cell.x] == instance


## The first empty slot, or -1.
func _find_empty_slot() -> int:
	for slot in size:
		if not _slots.has(slot):
			return slot
	return -1
