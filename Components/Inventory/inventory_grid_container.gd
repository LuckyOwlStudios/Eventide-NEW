class_name InventoryGridContainer
extends InventoryContainer
## A grid of cells, like a backpack or a chest. Every item covers its own
## [member Item.grid_size] of cells and can be turned on its side.

## Where an item sits: its top-left cell, and whether it is turned on its side.
class Placement:
	var cell: Vector2i
	var rotated: bool

	func _init(at_cell: Vector2i, is_rotated: bool) -> void:
		cell = at_cell
		rotated = is_rotated


## Columns and rows. The grid can grow with items inside it, but never gets smaller than they need.
@export var size := Vector2i(8, 4):
	set(value):
		size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		for instance: ItemInstance in _placements:
			var rect := get_rect(instance)
			size = Vector2i(maxi(size.x, rect.end.x), maxi(size.y, rect.end.y))

var _placements: Dictionary[ItemInstance, Placement] = {}


func get_instances() -> Array[ItemInstance]:
	var held: Array[ItemInstance] = []
	for instance: ItemInstance in _placements:
		held.append(instance)
	return held


func has_instance(instance: ItemInstance) -> bool:
	return instance != null and _placements.has(instance)


## The cells an instance covers, or an empty rect if it is not here.
func get_rect(instance: ItemInstance) -> Rect2i:
	if not has_instance(instance):
		return Rect2i()
	var placement := _placements[instance]
	return Rect2i(placement.cell, instance.item.get_grid_size(placement.rotated))


func is_rotated(instance: ItemInstance) -> bool:
	return has_instance(instance) and _placements[instance].rotated


## Whatever covers this cell, or null.
func get_instance_at(cell: Vector2i) -> ItemInstance:
	for instance: ItemInstance in _placements:
		if get_rect(instance).has_point(cell):
			return instance
	return null


func can_add(instance: ItemInstance, cell: Vector2i = AUTO_CELL, rotated: bool = false) -> bool:
	if not accepts(instance):
		return false
	if cell != AUTO_CELL:
		return _is_free(_get_occupancy(instance), Rect2i(cell, instance.item.get_grid_size(rotated)))
	return has_instance(instance) or _get_stack_space(instance) >= instance.quantity or _find_spot(instance) != null


func add(instance: ItemInstance, cell: Vector2i = AUTO_CELL, rotated: bool = false) -> bool:
	if not can_add(instance, cell, rotated):
		return false
	if cell != AUTO_CELL:
		_store(instance, Placement.new(cell, rotated))
		return true
	if has_instance(instance):
		return true
	var left := _fill_stacks(instance)
	if left == 0:
		return true
	instance.quantity = left
	_store(instance, _find_spot(instance))
	return true


func remove(instance: ItemInstance) -> bool:
	if not _placements.erase(instance):
		return false
	_notify_removed(instance)
	return true


func _store(instance: ItemInstance, placement: Placement) -> void:
	var was_inside := _placements.has(instance)
	_placements[instance] = placement
	if was_inside:
		_notify_changed(instance)
	else:
		_notify_added(instance)


## The first free spot, reading left to right and top to bottom. Upright anywhere comes before
## on its side anywhere. Null if there is none.
func _find_spot(instance: ItemInstance) -> Placement:
	var occupied := _get_occupancy(instance)
	var upright := instance.item.get_grid_size(false)
	for turn in 2:
		var rotated := turn == 1
		var footprint := instance.item.get_grid_size(rotated)
		if rotated and footprint == upright:
			break
		for y in range(size.y - footprint.y + 1):
			for x in range(size.x - footprint.x + 1):
				if _is_free(occupied, Rect2i(Vector2i(x, y), footprint)):
					return Placement.new(Vector2i(x, y), rotated)
	return null


## One byte per cell: 1 where something sits. The ignored instance is left out, so an item
## already in the grid can be tested against the room it would have once it lifts off.
func _get_occupancy(ignoring: ItemInstance = null) -> PackedByteArray:
	var occupied := PackedByteArray()
	occupied.resize(size.x * size.y)
	for instance: ItemInstance in _placements:
		if instance == ignoring:
			continue
		var rect := get_rect(instance)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				occupied[y * size.x + x] = 1
	return occupied


func _is_free(occupied: PackedByteArray, rect: Rect2i) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > size.x or rect.end.y > size.y:
		return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if occupied[y * size.x + x] != 0:
				return false
	return true
