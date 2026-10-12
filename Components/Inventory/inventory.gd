@icon("uid://btqplk7fct0cg")
class_name Inventory
extends Node
## Holds items for whatever it is added to: a player, a chest, a creature, a fuse box.
##
## It is a list of [InventoryContainer]s. A player might have a hotbar (one slot container with
## nine slots), a tool belt (a slot container that only takes tools) and a backpack grid, while a
## fuse box has one slot that only takes a fuse. Items go to the first container, in list order,
## that accepts them and has room.

signal item_added(container: InventoryContainer, instance: ItemInstance)
signal item_removed(container: InventoryContainer, instance: ItemInstance)
## An item gained or lost units, or moved within its container.
signal item_changed(container: InventoryContainer, instance: ItemInstance)
## Anything in any container changed.
signal changed

## The layout, set up in the inspector. Each inventory works on its own copies of these, so two
## chests made from one scene never share contents. Look containers up with [method get_container].
@export var containers: Array[InventoryContainer] = []

var _containers: Array[InventoryContainer] = []
var _built := false


func _enter_tree() -> void:
	_build()


## The live containers, in order.
func get_containers() -> Array[InventoryContainer]:
	return _list().duplicate()


func get_container(id: StringName) -> InventoryContainer:
	for container in _list():
		if container.id == id:
			return container
	return null


## Adds a container made in code, such as a backpack's grid when it is put on. It is used as it is,
## not copied.
func add_container(container: InventoryContainer) -> void:
	_build()
	_register(container)


## Takes a container out, keeping whatever is in it.
func remove_container(container: InventoryContainer) -> bool:
	if not _list().has(container):
		return false
	_containers.erase(container)
	container.item_added.disconnect(_on_item_added.bind(container))
	container.item_removed.disconnect(_on_item_removed.bind(container))
	container.item_changed.disconnect(_on_item_changed.bind(container))
	container.changed.disconnect(changed.emit)
	return true


## The container holding this instance, or null.
func find_container_of(instance: ItemInstance) -> InventoryContainer:
	for container in _list():
		if container.has_instance(instance):
			return container
	return null


func has_instance(instance: ItemInstance) -> bool:
	return find_container_of(instance) != null


## Total units of an item, across every container.
func get_count(item: Item) -> int:
	var total := 0
	for container in _list():
		total += container.get_count(item)
	return total


func find_instances(item: Item) -> Array[ItemInstance]:
	var found: Array[ItemInstance] = []
	for container in _list():
		found.append_array(container.find_instances(item))
	return found


## Whether [method add] would find room for the instance.
func can_add(instance: ItemInstance) -> bool:
	return not has_instance(instance) and _find_container_for(instance) != null


## Puts the instance in the first container that accepts it and has room, all at once or not
## at all. A stackable instance tops up matching stacks first, so it can end up absorbed into one:
## do not keep using it after a successful add. False if it is already in here.
func add(instance: ItemInstance) -> bool:
	if has_instance(instance):
		return false
	var container := _find_container_for(instance)
	return container != null and container.add(instance)


## Takes the instance out of whichever container holds it.
func remove(instance: ItemInstance) -> bool:
	var container := find_container_of(instance)
	return container != null and container.remove(instance)


## Takes units off a stack, removing the instance when none are left. False if there are fewer.
func remove_quantity(instance: ItemInstance, amount: int = 1) -> bool:
	var container := find_container_of(instance)
	return container != null and container.remove_quantity(instance, amount)


## Moves an instance from its container to another, all or nothing. For a grid destination,
## [param cell] and [param rotated] say where.
func move(
	instance: ItemInstance,
	destination: InventoryContainer,
	cell: Vector2i = InventoryContainer.AUTO_CELL,
	rotated: bool = false
) -> bool:
	var source := find_container_of(instance)
	return source != null and source.move_to(instance, destination, cell, rotated)


## Moves an instance into another inventory (or to a different container of this one), into the
## first container there that accepts it. All or nothing, like taking an item from a chest.
func transfer(instance: ItemInstance, to: Inventory) -> bool:
	var source := find_container_of(instance)
	if source == null:
		return false
	var destination := to._find_container_for(instance, source)
	return destination != null and source.move_to(instance, destination)


func _list() -> Array[InventoryContainer]:
	_build()
	return _containers


## Makes this inventory's own copies of the laid-out containers. Done as soon as the node enters
## the tree, or on first use if something asks sooner, so no other node's _ready sees it empty.
func _build() -> void:
	if _built:
		return
	_built = true
	for template in containers:
		if template == null:
			continue
		var container := template.duplicate() as InventoryContainer
		var starting := container.starting_items
		container.starting_items = []
		_register(container)
		for instance in starting:
			if instance == null or not container.add(instance.duplicate()):
				push_warning("[Inventory] Could not put a starting item in container '%s'." % container.id)


func _register(container: InventoryContainer) -> void:
	if container == null or _containers.has(container):
		return
	if not container.id.is_empty() and _containers.any(func(other: InventoryContainer) -> bool: return other.id == container.id):
		push_warning("[Inventory] Two containers share the id '%s'." % container.id)
	_containers.append(container)
	container.item_added.connect(_on_item_added.bind(container))
	container.item_removed.connect(_on_item_removed.bind(container))
	container.item_changed.connect(_on_item_changed.bind(container))
	container.changed.connect(changed.emit)


func _find_container_for(instance: ItemInstance, skipping: InventoryContainer = null) -> InventoryContainer:
	for container in _list():
		if container != skipping and container.can_add(instance):
			return container
	return null


func _on_item_added(instance: ItemInstance, container: InventoryContainer) -> void:
	item_added.emit(container, instance)


func _on_item_removed(instance: ItemInstance, container: InventoryContainer) -> void:
	item_removed.emit(container, instance)


func _on_item_changed(instance: ItemInstance, container: InventoryContainer) -> void:
	item_changed.emit(container, instance)
