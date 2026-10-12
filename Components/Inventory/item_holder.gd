## Equips one inventory item at a time and forwards use actions to its active actor.
class_name ItemHolder
extends Node

signal item_equipped(instance: ItemInstance, actor: ItemActor)
signal item_unequipped(instance: ItemInstance)

## Inventory whose items this holder is allowed to equip.
@export var inventory: Inventory
## The slot container whose slots the number keys pick from. Slot 1 answers to the input action
## inventory_slot_1, and so on for as many of those actions as the project defines.
@export var hotbar_id: StringName = &"hotbar"
## Position where the equipped ItemActor is instantiated, such as a hand or camera mount.
@export var actor_parent: Node3D

var equipped_instance: ItemInstance
var equipped_actor: ItemActor

var _slot_actions: Array[StringName] = []

func _ready() -> void:
	var number := 1
	while InputMap.has_action(StringName("inventory_slot_%d" % number)):
		_slot_actions.append(StringName("inventory_slot_%d" % number))
		number += 1
	if inventory == null:
		push_warning("[ItemHolder] Inventory is not assigned.")
	else:
		if get_hotbar() == null:
			push_warning("[ItemHolder] The inventory has no slot container named '%s'." % hotbar_id)
		if not inventory.item_removed.is_connected(_on_inventory_item_removed):
			inventory.item_removed.connect(_on_inventory_item_removed)
	if actor_parent == null:
		push_warning("[ItemHolder] Actor parent is not assigned.")

func _unhandled_input(event: InputEvent) -> void:
	var hotbar := get_hotbar()
	if hotbar == null:
		return
	for slot_index in mini(_slot_actions.size(), hotbar.size):
		if event.is_action_pressed(_slot_actions[slot_index]):
			get_viewport().set_input_as_handled()
			toggle_inventory_slot(slot_index)
			return

## The slot container the number keys pick from, or null.
func get_hotbar() -> InventorySlotContainer:
	if inventory == null:
		return null
	return inventory.get_container(hotbar_id) as InventorySlotContainer

## Equips a slot, switches to it, or unequips it when it is already held.
func toggle_inventory_slot(slot_index: int) -> bool:
	var hotbar := get_hotbar()
	if hotbar == null or slot_index < 0 or slot_index >= hotbar.size:
		return false
	var instance := hotbar.get_instance(slot_index)
	if instance == null:
		unequip_item()
		return false
	if instance == equipped_instance:
		unequip_item()
		return true
	return equip_item(instance)

func equip_item(instance: ItemInstance) -> bool:
	if inventory == null or actor_parent == null:
		return false
	if instance == null or not inventory.has_instance(instance):
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

## An item leaves its container when it is dropped, traded, or put in a bag, and you cannot
## keep holding it then. Moving it to another hotbar slot is not leaving, so that keeps it in hand.
func _on_inventory_item_removed(_container: InventoryContainer, instance: ItemInstance) -> void:
	if instance == equipped_instance:
		unequip_item()
