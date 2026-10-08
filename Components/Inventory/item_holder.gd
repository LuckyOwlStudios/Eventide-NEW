## Equips one inventory item at a time and forwards use actions to its active actor.
class_name ItemHolder
extends Node

const SLOT_COUNT := 4
const SLOT_ACTIONS := [
	&"inventory_slot_1",
	&"inventory_slot_2",
	&"inventory_slot_3",
	&"inventory_slot_4",
]

signal item_equipped(instance: ItemInstance, actor: ItemActor)
signal item_unequipped(instance: ItemInstance)

## Inventory whose items this holder is allowed to equip.
@export var inventory: Inventory
## Position where the equipped ItemActor is instantiated, such as a hand or camera mount.
@export var actor_parent: Node3D

var equipped_instance: ItemInstance
var equipped_actor: ItemActor

func _ready() -> void:
	if inventory == null:
		push_warning("[ItemHolder] Inventory is not assigned.")
	elif not inventory.item_removed.is_connected(_on_inventory_item_removed):
		inventory.item_removed.connect(_on_inventory_item_removed)
	if actor_parent == null:
		push_warning("[ItemHolder] Actor parent is not assigned.")

func _unhandled_input(event: InputEvent) -> void:
	for slot_index in SLOT_COUNT:
		if event.is_action_pressed(SLOT_ACTIONS[slot_index]):
			get_viewport().set_input_as_handled()
			toggle_inventory_slot(slot_index)
			return

## Equips a slot, switches to it, or unequips it when it is already held.
func toggle_inventory_slot(slot_index: int) -> bool:
	if inventory == null or slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	if slot_index >= inventory.items.size() or inventory.items[slot_index] == null:
		unequip_item()
		return false
	var instance := inventory.items[slot_index]
	if instance == equipped_instance:
		unequip_item()
		return true
	return equip_item(instance)

func equip_item(instance: ItemInstance) -> bool:
	if inventory == null or actor_parent == null:
		return false
	if instance == null or not inventory.has_item(instance):
		return false
	if instance == equipped_instance and is_instance_valid(equipped_actor):
		return true
	if instance.item == null:
		return false

	var new_actor := instance.item.create_actor(instance)
	if new_actor == null:
		return false

	unequip_item()
	equipped_instance = instance
	equipped_actor = new_actor
	actor_parent.add_child(equipped_actor)
	equipped_actor.transform = Transform3D.IDENTITY
	item_equipped.emit(equipped_instance, equipped_actor)
	return true

func unequip_item() -> void:
	if equipped_instance == null and not is_instance_valid(equipped_actor):
		return
	var previous_instance := equipped_instance
	equipped_instance = null
	if is_instance_valid(equipped_actor):
		equipped_actor.queue_free()
	equipped_actor = null
	if previous_instance != null:
		item_unequipped.emit(previous_instance)

func primary_use() -> void:
	if is_instance_valid(equipped_actor):
		equipped_actor.primary_use()

func secondary_use() -> void:
	if is_instance_valid(equipped_actor):
		equipped_actor.secondary_use()

func has_equipped_item() -> bool:
	return equipped_instance != null and is_instance_valid(equipped_actor)

func _on_inventory_item_removed(instance: ItemInstance, _index: int) -> void:
	if instance == equipped_instance:
		unequip_item()
