class_name AttributeModifier
extends Resource
## Immutable configuration shared by resource-based and node-based attributes.

enum Operation {
	ADD_VALUE, ## Adds [member amount] directly.
	ADD_MULTIPLIED_BASE, ## Adds [member amount] percent of the base value.
	MULTIPLY_TOTAL, ## Multiplies the running total by 1 + [member amount] percent.
}

## Stable identifier used to prevent the same effect from being applied twice.
@export var id: StringName
@export var amount := 0.0:
	set(new_amount):
		if is_equal_approx(amount, new_amount):
			return
		amount = new_amount
		emit_changed()
@export var operation: Operation = Operation.ADD_VALUE:
	set(new_operation):
		if operation == new_operation:
			return
		operation = new_operation
		emit_changed()
## Duration in seconds. A negative value lasts until explicitly removed.
@export var duration := -1.0

func get_id() -> StringName:
	if not id.is_empty():
		return id
	return StringName(str(get_instance_id()))

func calculate_change(base_value: float, current_total: float) -> float:
	match operation:
		Operation.ADD_VALUE:
			return amount
		Operation.ADD_MULTIPLIED_BASE:
			return base_value * amount / 100.0
		Operation.MULTIPLY_TOTAL:
			return current_total * amount / 100.0
	return 0.0
