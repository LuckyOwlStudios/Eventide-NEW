class_name AttributeNode
extends Node
## Shared interface for node-based values displayed by attribute UI.

signal value_changed(previous_value: float, current_value: float, change_amount: float)

func get_current_value() -> float:
	return 0.0

func get_maximum_value() -> float:
	return 0.0

func get_percentage() -> float:
	var maximum := get_maximum_value()
	if maximum <= 0.0:
		return 0.0
	return get_current_value() / maximum
