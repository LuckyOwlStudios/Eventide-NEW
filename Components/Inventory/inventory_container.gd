@abstract
class_name InventoryContainer
extends Resource
## One place in an inventory that holds items: a row of slots, or a grid of cells.
##
## Use [InventorySlotContainer] or [InventoryGridContainer]. An item lives in one container
## at a time, so use [method move_to] to relocate it instead of adding it to a second one.
##
## A container is a Resource so an inventory can be laid out in the inspector, but the
## [Inventory] works on its own copies, so two chests made from one scene never share contents.

## Pass as the cell to let the container pick the spot.
const AUTO_CELL := Vector2i(-1, -1)

signal item_added(instance: ItemInstance)
signal item_removed(instance: ItemInstance)
## An item already inside gained or lost units, or moved within the container.
signal item_changed(instance: ItemInstance)
## Resource.changed also fires after any of the three above, for views that just redraw.

## How this container is looked up, such as &"backpack" or &"hotbar".
@export var id: StringName
## What this container takes. An item is accepted when it is listed in [member accepted_items]
## or has one of [member accepted_tags]. With both empty, anything is accepted.
@export var accepted_tags: Array[StringName] = []
@export var accepted_items: Array[Item] = []
## Put in the container when the inventory is set up.
@export var starting_items: Array[ItemInstance] = []


## Whether the container takes this kind of item at all. Says nothing about whether there is room.
func accepts(instance: ItemInstance) -> bool:
	if instance == null or not instance.is_valid_instance():
		return false
	if accepted_tags.is_empty() and accepted_items.is_empty():
		return true
	return accepted_items.has(instance.item) or instance.item.has_any_tag(accepted_tags)


@abstract func get_instances() -> Array[ItemInstance]

@abstract func has_instance(instance: ItemInstance) -> bool

## Whether [method add] would succeed with the same arguments, without changing anything.
@abstract func can_add(instance: ItemInstance, cell: Vector2i = AUTO_CELL, rotated: bool = false) -> bool

## Puts the instance in all at once, or leaves everything as it was and returns false. A stackable
## instance tops up matching stacks first, so it can end up absorbed into one: do not keep using it
## after a successful add.
##
## [param cell] says where, or [constant AUTO_CELL] lets the container pick. A grid reads it as the
## top-left cell, and [param rotated] as whether the item lies on its side. A slot container reads
## [code]Vector2i(slot, 0)[/code] as the slot number and ignores [param rotated]. An instance
## already inside is moved to the new place.
@abstract func add(instance: ItemInstance, cell: Vector2i = AUTO_CELL, rotated: bool = false) -> bool

@abstract func remove(instance: ItemInstance) -> bool


func is_empty() -> bool:
	return get_instances().is_empty()


## Total units of an item, across all its stacks.
func get_count(item: Item) -> int:
	var total := 0
	for instance in get_instances():
		if instance.item == item:
			total += instance.quantity
	return total


func find_instances(item: Item) -> Array[ItemInstance]:
	var found: Array[ItemInstance] = []
	for instance in get_instances():
		if instance.item == item:
			found.append(instance)
	return found


## Takes units off a stack, removing the instance when none are left. False if there are fewer.
## Changing [member ItemInstance.quantity] directly also works, but this container is not told.
func remove_quantity(instance: ItemInstance, amount: int = 1) -> bool:
	if amount <= 0 or not has_instance(instance) or amount > instance.quantity:
		return false
	if amount == instance.quantity:
		return remove(instance)
	instance.quantity -= amount
	_notify_changed(instance)
	return true


func clear() -> void:
	for instance in get_instances():
		remove(instance)


## Moves an instance from this container to another, all or nothing: if the destination cannot
## take it, nothing changes. To the same container it moves the instance to the new cell.
func move_to(
	instance: ItemInstance,
	destination: InventoryContainer,
	cell: Vector2i = AUTO_CELL,
	rotated: bool = false
) -> bool:
	if destination == null or not has_instance(instance):
		return false
	if destination == self:
		return add(instance, cell, rotated)
	if not destination.can_add(instance, cell, rotated):
		return false
	remove(instance)
	if destination.add(instance, cell, rotated):
		return true
	push_error("[InventoryContainer] can_add said yes but add said no; putting the item back.")
	add(instance)
	return false


## How many more units the stacks here could take from this instance.
func _get_stack_space(instance: ItemInstance) -> int:
	var space := 0
	for stack in get_instances():
		if stack != instance and stack.can_stack_with(instance):
			space += stack.get_remaining_stack_space()
	return space


## Tops up matching stacks with the instance's units. Returns the units that did not fit.
func _fill_stacks(instance: ItemInstance) -> int:
	var left := instance.quantity
	var topped_up: Array[ItemInstance] = []
	for stack in get_instances():
		if left == 0:
			break
		if stack == instance or not stack.can_stack_with(instance):
			continue
		var moved := mini(left, stack.get_remaining_stack_space())
		if moved == 0:
			continue
		stack.quantity += moved
		left -= moved
		topped_up.append(stack)
	for stack in topped_up:
		_notify_changed(stack)
	return left


func _notify_added(instance: ItemInstance) -> void:
	item_added.emit(instance)
	emit_changed()


func _notify_removed(instance: ItemInstance) -> void:
	item_removed.emit(instance)
	emit_changed()


func _notify_changed(instance: ItemInstance) -> void:
	item_changed.emit(instance)
	emit_changed()
