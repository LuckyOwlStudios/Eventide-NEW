class_name Player
extends CharacterBody3D

@export var health: Health
@export var stamina: Stamina

func _init() -> void:
	set_collision_layer_value(1, false) # Remove from World Layer
	set_collision_layer_value(2, true) # Add to Player Layer
	
	set_collision_mask_value(1, true) # Detect the World
	set_collision_mask_value(5, true) # Detect Vehicle Interiors

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_paste") and health:
		health.decrease(20.0)
	if event.is_action_pressed("ui_copy") and health:
		health.increase(20.0)
