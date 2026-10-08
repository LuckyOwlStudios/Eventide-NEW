@icon("uid://btqplk7fct0cg")
class_name Inventory
extends Node
## Drop-in inventory component. Add this node as a child of anything that owns items.

## Emitted when a new item instance is added to this inventory.
signal item_added(instance: ItemInstance, index: int)
## Emitted when an item instance is removed from this inventory.
signal item_removed(instance: ItemInstance, index: int)
signal item_quantity_changed(instance: ItemInstance, index: int)
signal inventory_changed

## Maximum number of item stacks this inventory can hold. A value of 0 means unlimited.
@export_range(0, 1024, 1, "or_greater") var capacity: int = 0
## Instances placed here in the inspector become the inventory's starting contents.
@export var items: Array[ItemInstance] = []

func add_item(instance: ItemInstance) -> bool:
	if instance == null or not instance.is_valid_instance() or not can_add_item(instance):
		return false

	var remaining := instance.quantity
	for index in items.size():
		var existing := items[index]
		if existing == null:
			continue
		if not existing.can_stack_with(instance):
			continue
		var moved := mini(remaining, existing.get_remaining_stack_space())
		if moved == 0:
			continue
		existing.quantity += moved
		remaining -= moved
		item_quantity_changed.emit(existing, index)
		if remaining == 0:
			inventory_changed.emit()
			return true

	instance.quantity = remaining
	items.append(instance)
	item_added.emit(instance, items.size() - 1)
	inventory_changed.emit()
	return true

func can_add_item(instance: ItemInstance) -> bool:
	if instance == null or not instance.is_valid_instance():
		return false
	var available_space := 0
	for existing in items:
		if existing == null:
			continue
		if existing.can_stack_with(instance):
			available_space += existing.get_remaining_stack_space()
	if available_space >= instance.quantity:
		return true
	return not is_full()

func remove_item(instance: ItemInstance) -> bool:
	var index := items.find(instance)
	if index == -1:
		return false
	items.remove_at(index)
	item_removed.emit(instance, index)
	inventory_changed.emit()
	return true

func remove_quantity(instance: ItemInstance, amount: int = 1) -> bool:
	var index := items.find(instance)
	if index == -1 or amount <= 0:
		return false
	if amount >= instance.quantity:
		return remove_item(instance)
	instance.quantity -= amount
	item_quantity_changed.emit(instance, index)
	inventory_changed.emit()
	return true

func has_item(instance: ItemInstance) -> bool:
	return items.has(instance)

func get_item_count(item: Item) -> int:
	var total := 0
	for instance in items:
		if instance != null and instance.item == item:
			total += instance.quantity
	return total

func is_full() -> bool:
	return capacity > 0 and items.size() >= capacity

func clear() -> void:
	if items.is_empty():
		return
	for index in range(items.size() - 1, -1, -1):
		item_removed.emit(items[index], index)
	items.clear()
	inventory_changed.emit()
