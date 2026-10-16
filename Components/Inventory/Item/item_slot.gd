## A place that holds one item: a shelf spot, a bracket, a socket. A player holding an item uses the slot to
## put it there, and the item then sits in the slot as if it lay on the ground, but fixed in place with no
## physics. It is still an ordinary world item: it can be picked up again by looking at it (its own
## [ItemPickup]), and an item that does something in the world, such as a flashlight, keeps doing it.
##
## This is the base for what needs an item put in it. A fuse box extends it, takes a fuse tag and does
## something in [method _on_placed] and [method _on_removed]; a shelf uses it as it is.
##
## Add it as an interactable: give it a collision shape the size of the item and, if the item should sit
## somewhere else (a marker on a shelf), set [member mount]. The item is a child of the mount, so it moves
## with whatever the slot is on, such as a ship. The slot is only offered while the player holds something
## it accepts, and it gets out of the way of the item's own pickup prompt once it is full.
##
## The option to place has the id [constant PLACE_ID]. Change its prompt in the inspector to say what it
## is ("Insert Fuse").
class_name ItemSlot
extends InteractableObject3D

## An item was put in the slot.
signal item_placed(instance: ItemInstance, actor: ItemActor)
## The item left the slot, taken out by a player or by [method remove].
signal item_removed(instance: ItemInstance)

const PLACE_ID: StringName = &"place"

@export_group("Item")
## What the slot takes: items with any of these tags. Both lists empty means anything.
@export var accepted_tags: Array[StringName] = []
## What the slot takes: these items. Both lists empty means anything.
@export var accepted_items: Array[Item] = []
## What the item is attached to. The slot itself when left empty.
@export var mount: Node3D
## Where the item sits, relative to the mount.
@export var item_offset := Transform3D.IDENTITY
## An item that is in the slot when the game starts, such as a fuse that was already fitted. Each copy of
## the scene gets its own copy of it. It goes in a moment after the scene is ready.
@export var starting_instance: ItemInstance

var _instance: ItemInstance
var _actor: ItemActor
## The layer the slot is looked at on while it is empty.
var _empty_layer := 0


func _init() -> void:
	interaction_options.clear()
	var option := _create_default_interaction_option()
	option.option_id = PLACE_ID
	option.prompt = "Place Item"
	interaction_options.append(option)


func _ready() -> void:
	super._ready()
	_empty_layer = collision_layer
	if starting_instance != null:
		_place_starting_instance.call_deferred()


## True when nothing is in the slot.
func is_empty() -> bool:
	_validate()
	return _instance == null


## The item in the slot, or null.
func get_instance() -> ItemInstance:
	_validate()
	return _instance


## The world actor of the item in the slot, or null.
func get_actor() -> ItemActor:
	_validate()
	return _actor


## Whether the slot is empty and takes this item.
func can_place(instance: ItemInstance) -> bool:
	if instance == null or instance.item == null or instance.item.actor_scene == null:
		return false
	if not is_empty():
		return false
	if not accepted_tags.is_empty() or not accepted_items.is_empty():
		if not accepted_items.has(instance.item) and not instance.item.has_any_tag(accepted_tags):
			return false
	return _accepts(instance)


## Puts an item in the slot, with all its state. The caller must already have taken it from wherever it
## was (see [method ItemHolder.take_equipped_item]). Returns false, changing nothing, if the slot cannot
## take it.
func place(instance: ItemInstance) -> bool:
	if not can_place(instance):
		return false
	var actor := instance.item.create_actor(instance)
	if actor == null:
		return false
	# A world item with its body switched off: it stays exactly where it is put.
	actor.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	actor.freeze = true
	actor.collision_layer = 0
	actor.collision_mask = 0
	var parent: Node3D = mount if is_instance_valid(mount) else self
	parent.add_child(actor)
	actor.transform = item_offset
	actor.reset_physics_interpolation()
	actor.tree_exiting.connect(_on_actor_exiting)
	_instance = instance
	_actor = actor
	_refresh_collision()
	_on_placed(instance, actor)
	item_placed.emit(instance, actor)
	return true


## Takes the item out of the slot and returns it (null if it was empty). Its actor goes; the caller
## decides where the item goes next.
func remove() -> ItemInstance:
	_validate()
	if _instance == null:
		return null
	var instance := _instance
	if is_instance_valid(_actor):
		_actor.visible = false
		_actor.queue_free()
	_clear()
	return instance


## An extra rule for what the slot takes, on top of the tags and items it lists. A fuse slot might check
## that the fuse is not blown.
func _accepts(_instance_to_check: ItemInstance) -> bool:
	return true


## An item was put in. [param actor] is its actor, already in the tree.
func _on_placed(_placed: ItemInstance, _placed_actor: ItemActor) -> void:
	pass


## The item left the slot.
func _on_removed(_removed: ItemInstance) -> void:
	pass


func _can_interact_option(interactor: Node3D, option_index: int) -> bool:
	if _get_option_id(option_index) != PLACE_ID:
		return false
	var holder := ItemHolder.find_for(interactor)
	return holder != null and holder.is_local() and holder.has_equipped_item() and can_place(holder.equipped_instance)


func _interact_option(interactor: Node3D, option_index: int) -> bool:
	if _get_option_id(option_index) != PLACE_ID:
		return false
	var holder := ItemHolder.find_for(interactor)
	if holder == null:
		return false
	var instance := holder.take_equipped_item()
	if instance == null:
		return false
	if place(instance):
		return true
	# Cannot happen after the check above, but never lose an item.
	holder.inventory.add(instance)
	return false


func _get_option_id(option_index: int) -> StringName:
	var option := get_interaction_option(option_index)
	return StringName(option.option_id) if option != null else &""


func _place_starting_instance() -> void:
	if not is_empty():
		return
	var copy := starting_instance.duplicate() as ItemInstance
	if copy == null or copy.item == null or not place(copy):
		push_warning("[ItemSlot] %s could not take its starting item." % get_path())


## A picked-up item is freed at the end of the frame; this notices that it has gone.
func _on_actor_exiting() -> void:
	_validate.call_deferred()


## Lets go of an item whose actor is gone (picked up, freed) or was moved out of the slot.
func _validate() -> void:
	if _instance == null:
		return
	if is_instance_valid(_actor) and not _actor.is_queued_for_deletion() and _actor.get_parent() != null:
		return
	_clear()


func _clear() -> void:
	var instance := _instance
	_instance = null
	_actor = null
	_refresh_collision()
	if instance != null:
		_on_removed(instance)
		item_removed.emit(instance)


## A full slot is not looked at, so a ray reaches the item's own pickup inside it.
func _refresh_collision() -> void:
	if not is_node_ready():
		return
	collision_layer = _empty_layer if _instance == null else 0
