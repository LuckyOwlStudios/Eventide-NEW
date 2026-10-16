class_name SystemRegistry
extends RefCounted
## Every [SystemTemplate] in the game, and the choosing of which one a system is.
##
## The templates are the .tres files under [constant ROOT]; put a new one anywhere in that folder and it is
## found. (The same way [ItemRegistry] finds items.)
##
## [b]Choosing.[/b] A system's template depends on nothing but the system's seed and its jump count: of the templates
## whose [member SystemTemplate.min_jump] has been reached, one is picked with chances in proportion to their
## [member SystemTemplate.weight]. The templates are sorted by their path first, so the order the folder was read
## in (which can differ between machines) never changes the pick, and every player gets the same system.

const ROOT := "res://Game/Registry/Systems/"
## Mixed into the system's seed, so the choice of template has a stream of random numbers of its own.
const SEED_SALT := 0x74656D70

static var _templates: Array[SystemTemplate] = []
static var _scanned := false


## Every template, sorted by path.
static func get_templates() -> Array[SystemTemplate]:
	_scan()
	return _templates.duplicate()


## Forgets what was found, so the next lookup reads the folder again.
static func clear() -> void:
	_templates.clear()
	_scanned = false


## The templates from [param pool] (every template when it is empty) that systems at [param jump] can be.
static func get_available(jump: int, pool: Array[SystemTemplate] = []) -> Array[SystemTemplate]:
	var found: Array[SystemTemplate] = []
	for template in pool if not pool.is_empty() else get_templates():
		if template != null and template.is_available(jump):
			found.append(template)
	return found


## The template of the system with seed [param system_seed] at jump [param jump], chosen from [param pool] (every
## template when it is empty). A plain default template when none can be.
static func pick(system_seed: int, jump: int, pool: Array[SystemTemplate] = []) -> SystemTemplate:
	var available := get_available(jump, pool)
	if available.is_empty():
		return SystemTemplate.make_default()
	var weights := PackedFloat32Array()
	for template in available:
		weights.append(template.weight)
	var rng := SpaceRandom.new(SpaceRandom.combine(system_seed, SEED_SALT))
	var index := rng.pick_weighted(weights)
	return available[maxi(index, 0)]


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_templates.clear()
	_scan_folder(ROOT)
	_templates.sort_custom(func(a: SystemTemplate, b: SystemTemplate) -> bool: return a.resource_path < b.resource_path)


## Folders come back from list_directory with a slash on the end, and the names are the originals even in
## an exported game, where the files themselves are converted.
static func _scan_folder(folder: String) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_scan_folder(folder.path_join(entry))
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var template := ResourceLoader.load(folder.path_join(entry)) as SystemTemplate
			if template != null:
				_templates.append(template)
