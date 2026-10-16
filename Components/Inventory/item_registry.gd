class_name ItemRegistry
extends RefCounted
## Every [Item] in the game, looked up by its id.
##
## An item's scene cannot point at its own Item resource, because the Item already points at the scene
## and the engine cannot load two resources that need each other. So a scene says which item it is by
## id (see [member ItemActor.item_id]) and finds it here. Items are the .tres files under [constant ROOT];
## put a new one anywhere in that folder and it is found.

const ROOT := "res://Game/Registry/Items/"

static var _items: Dictionary[StringName, Item] = {}
static var _scanned := false


## The item with this id, or null.
static func get_item(id: StringName) -> Item:
	_scan()
	return _items.get(id)


## Every item, in no particular order.
static func get_items() -> Array[Item]:
	_scan()
	return _items.values()


## Forgets what was found, so the next lookup reads the folder again.
static func clear() -> void:
	_items.clear()
	_scanned = false


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_scan_folder(ROOT)


## Folders come back from list_directory with a slash on the end, and the names are the originals even in
## an exported game, where the files themselves are converted.
static func _scan_folder(folder: String) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_scan_folder(folder.path_join(entry))
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var item := ResourceLoader.load(folder.path_join(entry)) as Item
			if item == null:
				continue
			if _items.has(item.id):
				push_warning("[ItemRegistry] Two items share the id '%s'." % item.id)
			_items[item.id] = item
