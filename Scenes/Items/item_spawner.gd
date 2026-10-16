class_name ItemSpawner
extends Node3D

@export var item: Item

func _ready() -> void:
	if item == null:
		return
	var scene = item.actor_scene
	if scene == null:
		return
	var actor = item.actor_scene.instantiate()
	add_child(actor)
