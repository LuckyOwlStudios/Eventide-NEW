@icon("uid://b751tm7ec57u4")
class_name MovementAttribute
extends Node
## The numbers that decide how fast a character moves and how high it jumps.
##
## Both are [Attribute]s, so buffs, debuffs and equipment can change them by
## adding an [AttributeModifier] without knowing anything about the mover:
## [codeblock]
## stats.movement_speed.add_attribute_modifier("potion.haste", haste_modifier)
## [/codeblock]
## The mover multiplies speed by its stance factors (sprint, stroll, crouch), so
## modifiers here stack with those instead of fighting them.

## Walking speed in meters per second before any modifiers.
@export_range(0.0, 50.0, 0.1, "or_greater", "suffix:m/s") var base_movement_speed := 5.0:
	set(value):
		base_movement_speed = maxf(value, 0.0)
		movement_speed.base_value = base_movement_speed

## How high a standing jump goes, in meters, before any modifiers.
@export_range(0.0, 20.0, 0.05, "or_greater", "suffix:m") var base_jump_height := 1.0:
	set(value):
		base_jump_height = maxf(value, 0.0)
		jump_height.base_value = base_jump_height

var movement_speed := Attribute.new(base_movement_speed)
var jump_height := Attribute.new(base_jump_height)

func _ready() -> void:
	movement_speed.base_value = base_movement_speed
	jump_height.base_value = base_jump_height
