## The area that lets a player use a world item. It belongs to the [ItemActor] it is part of (the
## nearest one above it), so it is only ever in a world actor: held ones free it (see ItemActor).
##
## It offers its options like any interactable. The option with the id [constant PICKUP_ID] picks the item
## up, through the interacting player's [ItemHolder], which says whether it fits in the inventory. While it
## does not, that option is not shown at all. Every other option is the item's own (a flashlight's
## "toggle"): it is passed to [method ItemActor._on_world_option], which decides what it does.
class_name ItemPickup
extends InteractableObject3D

const PICKUP_ID: StringName = &"pickup"


func _can_interact_option(interactor: Node3D, option_index: int) -> bool:
	var actor := _get_actor()
	if not _is_pickup(option_index):
		return actor != null and actor.is_in_world()
	var holder := ItemHolder.find_for(interactor)
	return holder != null and holder.can_pick_up(actor)


func _interact_option(interactor: Node3D, option_index: int) -> bool:
	var actor := _get_actor()
	if not _is_pickup(option_index):
		var option := get_interaction_option(option_index)
		return actor != null and option != null and actor._on_world_option(StringName(option.option_id), interactor)
	var holder := ItemHolder.find_for(interactor)
	return holder != null and holder.pick_up(actor)


func _is_pickup(option_index: int) -> bool:
	var option := get_interaction_option(option_index)
	return option != null and StringName(option.option_id) == PICKUP_ID


func _get_actor() -> ItemActor:
	var node := get_parent()
	while node != null:
		if node is ItemActor:
			return node
		node = node.get_parent()
	return null
