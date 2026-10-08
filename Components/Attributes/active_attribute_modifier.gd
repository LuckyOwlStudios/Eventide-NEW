class_name ActiveAttributeModifier
extends RefCounted
## Per-application runtime state for an [AttributeModifier] definition.

var definition: AttributeModifier
var remaining_duration: float

func _init(modifier: AttributeModifier) -> void:
	definition = modifier
	remaining_duration = modifier.duration

func tick(delta: float) -> bool:
	if remaining_duration < 0.0:
		return false
	remaining_duration -= delta
	return remaining_duration <= 0.0
