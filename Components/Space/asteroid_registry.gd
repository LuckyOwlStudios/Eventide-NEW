class_name AsteroidRegistry
extends RefCounted
## Every [Asteroid] kind in the game. They are the .tres files under [constant ROOT]; put a new one anywhere in
## that folder and it is found. (The same way [ItemRegistry] finds items.)
##
## They are sorted by path, so the order the folder was read in (which can differ between machines) never changes
## which asteroids a system gets. See [AsteroidMix] for how a system picks from them.

const ROOT := "res://Game/Registry/Asteroids/"

static var _asteroids: Array[Asteroid] = []
static var _scanned := false


## Every kind, sorted by path.
static func get_asteroids() -> Array[Asteroid]:
	_scan()
	return _asteroids.duplicate()


## Forgets what was found, so the next lookup reads the folder again.
static func clear() -> void:
	_asteroids.clear()
	_scanned = false


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_asteroids.clear()
	_scan_folder(ROOT)
	_asteroids.sort_custom(func(a: Asteroid, b: Asteroid) -> bool: return a.resource_path < b.resource_path)


## Folders come back from list_directory with a slash on the end, and the names are the originals even in
## an exported game, where the files themselves are converted.
static func _scan_folder(folder: String) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_scan_folder(folder.path_join(entry))
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var asteroid := ResourceLoader.load(folder.path_join(entry)) as Asteroid
			if asteroid != null:
				_asteroids.append(asteroid)
