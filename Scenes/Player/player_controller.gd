class_name Player
extends CharacterBody3D

@export var health: Health
@export var stamina: Stamina

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_paste") and health:
		health.decrease(20.0)
	if event.is_action_pressed("ui_copy") and health:
		health.increase(20.0)

func _process(delta: float) -> void:
	pass
