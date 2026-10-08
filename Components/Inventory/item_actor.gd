## Active scene-tree representation of an ItemInstance.
## Player controllers forward actions to this node while the item is equipped.
class_name ItemActor
extends Node3D

var item_instance: ItemInstance

func setup(instance: ItemInstance) -> void:
	item_instance = instance
	if is_node_ready():
		_on_item_instance_changed()

func _ready() -> void:
	_on_item_instance_changed()

func primary_use() -> void:
	pass

func secondary_use() -> void:
	pass

func _on_item_instance_changed() -> void:
	pass
