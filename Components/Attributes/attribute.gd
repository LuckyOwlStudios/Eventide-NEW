class_name Attribute
extends Resource

## Emitted when recalculation produces a different final value.
signal value_changed(previous_value: float, current_value: float, change_amount: float)
## Emitted after a modifier is stored under a new ID.
signal attribute_modifier_added(id: String, modifier: AttributeModifier)
## Emitted when adding an existing ID replaces its modifier.
signal attribute_modifier_replaced(
	id: String,
	previous_modifier: AttributeModifier,
	current_modifier: AttributeModifier,
)
## Emitted after a modifier is removed.
signal attribute_modifier_removed(id: String, modifier: AttributeModifier)
## Emitted after at least one modifier is cleared.
signal attribute_modifiers_cleared

## The value before any attribute modifiers are applied.
var base_value: float:
	get:
		return _base_value
	set(new_value):
		if is_equal_approx(_base_value, new_value):
			return
		_base_value = new_value
		calculate_final_value()

## The value after all modifiers have been applied.
var value: float:
	get:
		return _value

## Active modifiers indexed by caller-provided IDs.
var attribute_modifiers: Dictionary[String, AttributeModifier] = {}

var _base_value := 0.0
var _value := 0.0

func _init(initial_base_value := 0.0) -> void:
	_base_value = initial_base_value
	_value = initial_base_value

## Adds a modifier under [param id]. Existing IDs are replaced.
func add_attribute_modifier(id: String, modifier: AttributeModifier) -> bool:
	if id.is_empty():
		push_error("RAttribute modifier IDs cannot be empty.")
		return false
	if modifier == null:
		push_error("RAttribute cannot add a null modifier.")
		return false

	var previous_modifier: AttributeModifier = attribute_modifiers.get(id)
	if previous_modifier == modifier:
		return false

	if previous_modifier != null:
		_disconnect_modifier(previous_modifier)
	attribute_modifiers[id] = modifier
	_connect_modifier(modifier)
	calculate_final_value()

	if previous_modifier == null:
		attribute_modifier_added.emit(id, modifier)
	else:
		attribute_modifier_replaced.emit(id, previous_modifier, modifier)
	return true


## Removes the modifier stored under [param id].
func remove_attribute_modifier(id: String) -> bool:
	if not attribute_modifiers.has(id):
		return false

	var modifier: AttributeModifier = attribute_modifiers[id]
	attribute_modifiers.erase(id)
	_disconnect_modifier_if_unused(modifier)
	calculate_final_value()
	attribute_modifier_removed.emit(id, modifier)
	return true

func has_attribute_modifier(id: String) -> bool:
	return attribute_modifiers.has(id)

func get_attribute_modifier(id: String) -> AttributeModifier:
	return attribute_modifiers.get(id)

func clear_attribute_modifiers() -> void:
	if attribute_modifiers.is_empty():
		return

	var unique_modifiers: Array[AttributeModifier] = []
	for modifier in attribute_modifiers.values():
		if not unique_modifiers.has(modifier):
			unique_modifiers.append(modifier)
	attribute_modifiers.clear()
	for modifier in unique_modifiers:
		_disconnect_modifier(modifier)
	calculate_final_value()
	attribute_modifiers_cleared.emit()

## Recalculates every modifier in a stable operation order and returns the result.
func calculate_final_value() -> float:
	var previous_value := _value
	var final_value := _base_value

	# Flat additions are applied first.
	for modifier in attribute_modifiers.values():
		if modifier.operation == AttributeModifier.Operation.ADD_VALUE:
			final_value += modifier.calculate_change(_base_value, final_value)

	# Base percentages are independent of insertion order.
	for modifier in attribute_modifiers.values():
		if modifier.operation == AttributeModifier.Operation.ADD_MULTIPLIED_BASE:
			final_value += modifier.calculate_change(_base_value, final_value)

	# Total percentages compound after all flat and base additions.
	for modifier in attribute_modifiers.values():
		if modifier.operation == AttributeModifier.Operation.MULTIPLY_TOTAL:
			final_value += modifier.calculate_change(_base_value, final_value)

	_value = final_value
	if not is_equal_approx(previous_value, _value):
		value_changed.emit(previous_value, _value, _value - previous_value)
	return _value

func _connect_modifier(modifier: AttributeModifier) -> void:
	var callback := _on_modifier_changed.bind(modifier)
	if not modifier.changed.is_connected(callback):
		modifier.changed.connect(callback)

func _disconnect_modifier(modifier: AttributeModifier) -> void:
	var callback := _on_modifier_changed.bind(modifier)
	if modifier.changed.is_connected(callback):
		modifier.changed.disconnect(callback)

func _disconnect_modifier_if_unused(modifier: AttributeModifier) -> void:
	if not attribute_modifiers.values().has(modifier):
		_disconnect_modifier(modifier)

func _on_modifier_changed(_modifier: AttributeModifier) -> void:
	calculate_final_value()
