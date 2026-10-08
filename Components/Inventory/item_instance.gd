## Mutable state for an item owned by an inventory or represented in the world.
class_name ItemInstance
extends Resource

signal quantity_changed(quantity: int)

@export var item: Item:
	set(value):
		item = value
		quantity = quantity
@export_range(1, 9999, 1, "or_greater") var quantity: int = 1:
	set(value):
		var maximum := item.max_stack_size if item != null else 9999
		var normalized := clampi(value, 1, maximum)
		if quantity == normalized:
			return
		quantity = normalized
		quantity_changed.emit(quantity)
		emit_changed()

func is_valid_instance() -> bool:
	return item != null and item.is_valid_definition() and quantity > 0

func can_stack_with(other: ItemInstance) -> bool:
	return (
		other != null
		and item != null
		and item == other.item
		and item.max_stack_size > 1
		and get_script() == other.get_script()
	)

func get_remaining_stack_space() -> int:
	if item == null:
		return 0
	return maxi(item.max_stack_size - quantity, 0)
