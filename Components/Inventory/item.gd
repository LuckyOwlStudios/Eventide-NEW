## Shared, immutable definition of one kind of item.
## Runtime state belongs to ItemInstance resources, not to this definition.
class_name Item
extends Resource

## Stable identifier used by game logic and save data, such as "metal_scrap".
@export var id: StringName
## Name shown to the player.
@export var display_name: String
## Description shown to the player.
@export_multiline var description: String
## Icon shown in inventory interfaces.
@export var icon: Texture2D
## Maximum quantity represented by one ItemInstance. Unique items use 1.
@export_range(1, 9999, 1, "or_greater") var max_stack_size: int = 1
## Cells this item covers in a grid container: width, then height. Slots ignore it.
@export var grid_size := Vector2i.ONE
## What kind of thing this is, such as &"tool". Containers use these to decide what they accept.
@export var tags: Array[StringName] = []
## The item's one scene, used wherever it is: on the ground, on a shelf, in a hand. Its root must be an
## ItemActor, so build it from WorldItem.tscn (an inherited scene). It names this item with its own Item Id.
@export var actor_scene: PackedScene:
	set(value):
		actor_scene = value
		_carried_parts = -1
## Optional ItemInstance subclass used when creating this item.
@export var instance_script: Script

## 1 when the scene has parts made for carrying, 0 when not, -1 until looked at.
var _carried_parts := -1

func is_valid_definition() -> bool:
	return not id.is_empty() and not display_name.is_empty()

## The cells this item covers in a grid, turned on its side when rotated.
func get_grid_size(rotated: bool = false) -> Vector2i:
	var cells := Vector2i(maxi(grid_size.x, 1), maxi(grid_size.y, 1))
	return Vector2i(cells.y, cells.x) if rotated else cells

## Whether this item has anything to do while it is carried and not in hand: a node of its scene is in the
## group item_carried or item_always (see ItemActor). An item that does not has no actor in a pocket.
func has_carried_parts() -> bool:
	if _carried_parts == -1:
		_carried_parts = 1 if ItemActor.scene_has_carried_parts(actor_scene) else 0
	return _carried_parts == 1

func has_any_tag(wanted: Array[StringName]) -> bool:
	for tag in wanted:
		if tags.has(tag):
			return true
	return false

func create_instance(quantity: int = 1) -> ItemInstance:
	var instance := ItemInstance.new()
	if instance_script != null:
		var custom_instance: Variant = instance_script.new()
		if custom_instance is ItemInstance:
			instance = custom_instance
		else:
			push_error("[Item] instance_script must extend ItemInstance.")
	instance.item = self
	instance.quantity = clampi(quantity, 1, max_stack_size)
	return instance

## Makes the item's scene for an instance, ready to be added to the tree. A plain actor is an item in the
## world; ItemHolder turns it into a held one before adding it.
func create_actor(instance: ItemInstance) -> ItemActor:
	if actor_scene == null:
		return null
	if instance == null or instance.item != self:
		push_error("[Item] Cannot create an actor for a mismatched item instance.")
		return null
	var actor := actor_scene.instantiate() as ItemActor
	if actor == null:
		push_error("[Item] actor_scene root must extend ItemActor.")
		return null
	actor.setup(instance)
	return actor

## Puts an instance into the world as a physical item, at a global transform and moving at a velocity.
## This is how a dropped item, loot or a spilled crate appears. The instance keeps all its state.
func spawn_in_world(
	instance: ItemInstance,
	parent: Node,
	at: Transform3D,
	velocity: Vector3 = Vector3.ZERO,
) -> ItemActor:
	if parent == null:
		return null
	var actor := create_actor(instance)
	if actor == null:
		return null
	parent.add_child(actor)
	actor.global_transform = at
	actor.linear_velocity = velocity
	# It was made somewhere else, and must not slide in from there.
	actor.reset_physics_interpolation()
	return actor
