class_name WorldSaves
extends RefCounted
## The world slots the player can host from. Each slot is a folder under [member root]
## holding a [constant META_FILE] that describes the world. Whatever the game later saves
## for a world belongs in the same folder, so a slot is "taken" once its metadata exists.
##
## A world's metadata is its name, when it was made and last played, and the numbers that
## carry the game: the [code]jump_count[/code] (how many jumps the ship has made, which is also
## how hard the system it is in is), the [code]world_seed[/code] every system of that world is
## built from (see [StarSystem]) and the [code]presence[/code] (how full the Cosmic Presence's bar was
## when the last jump finished, see [CosmicPresence]). Continuing a world rebuilds the system its jump
## count points to, with the bar where that jump left it.

const SLOT_COUNT := 4
const META_FILE := "world.json"
const FORMAT_VERSION := 2
## Numbers in the metadata. JSON hands numbers back as floats, which cannot be written out
## exactly again, so these are turned back into whole numbers before every write.
const _WHOLE_NUMBERS := ["version", "created", "last_played", "jump_count", "world_seed"]

## Folder that holds the slot folders. Tests point this somewhere disposable.
static var root := "user://worlds"
## The slot being played, or 0 outside a world. Set when a world is started from the menus.
static var active_slot := 0


## Folder that holds everything for [param slot] (1-based).
static func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [root, slot]


static func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


## One entry per slot, in order. See [method read_slot] for the keys.
static func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot in range(1, SLOT_COUNT + 1):
		slots.append(read_slot(slot))
	return slots


## Describes [param slot]:
## [code]slot[/code], [code]exists[/code], [code]corrupt[/code] (a save is there but its
## metadata cannot be read), [code]name[/code], [code]created[/code] and
## [code]last_played[/code] (Unix seconds, 0 when unknown), [code]jump_count[/code] (0 for a world
## that has not jumped, and for saves from before there were jumps), [code]world_seed[/code]
## (0 when the world has none yet; see [method ensure_world_seed]) and [code]presence[/code] (the
## Cosmic Presence's bar from 0 to 1, or -1 when the world never saved one).
static func read_slot(slot: int) -> Dictionary:
	var info := {
		"slot": slot,
		"exists": false,
		"corrupt": false,
		"name": "",
		"created": 0,
		"last_played": 0,
		"jump_count": 0,
		"world_seed": 0,
		"presence": -1.0,
	}
	var path := "%s/%s" % [slot_dir(slot), META_FILE]
	if not FileAccess.file_exists(path):
		return info
	info["exists"] = true
	var meta: Variant = _load_meta(slot)
	if meta == null:
		info["corrupt"] = true
		return info
	info["name"] = str(meta.get("name", "")).strip_edges()
	if info["name"].is_empty():
		info["name"] = default_name(slot)
	info["created"] = int(meta.get("created", 0))
	info["last_played"] = int(meta.get("last_played", 0))
	info["jump_count"] = maxi(int(meta.get("jump_count", 0)), 0)
	info["world_seed"] = int(meta.get("world_seed", 0))
	if meta.has("presence"):
		info["presence"] = clampf(float(meta["presence"]), 0.0, 1.0)
	return info


## Starts a new world in an empty [param slot]. Returns the new slot info, or an empty
## dictionary if the slot is invalid, already taken or cannot be written. The new world is at
## jump 0 and has a seed of its own.
static func create_world(slot: int, world_name := "") -> Dictionary:
	if not is_valid_slot(slot) or read_slot(slot)["exists"]:
		return {}
	var now := int(Time.get_unix_time_from_system())
	var meta := {
		"version": FORMAT_VERSION,
		"name": world_name.strip_edges() if not world_name.strip_edges().is_empty() else default_name(slot),
		"created": now,
		"last_played": now,
		"jump_count": 0,
		"world_seed": new_world_seed(),
	}
	if not _write_meta(slot, meta):
		return {}
	return read_slot(slot)


## Records that [param slot] was just played. Does nothing for a missing or unreadable slot.
static func mark_played(slot: int) -> void:
	_update_meta(slot, {"last_played": int(Time.get_unix_time_from_system())})


## Records that the world in [param slot] is now at jump [param jump_count], and, if [param presence] is
## not negative, where the Cosmic Presence's bar stands. Does nothing for a missing or unreadable slot.
## Returns whether it was written.
static func record_jump(slot: int, jump_count: int, presence := -1.0) -> bool:
	var changes := {"jump_count": maxi(jump_count, 0)}
	if presence >= 0.0:
		# A few decimals are plenty, and keep the file readable.
		changes["presence"] = snappedf(clampf(presence, 0.0, 1.0), 0.0001)
	return _update_meta(slot, changes)


## The seed of the world in [param slot]. A world with none (saved before there were seeds) is
## given one, which is written down so it keeps it. Returns 0 for a missing or unreadable slot.
static func ensure_world_seed(slot: int) -> int:
	var info := read_slot(slot)
	if not info["exists"] or info["corrupt"]:
		return 0
	if info["world_seed"] != 0:
		return info["world_seed"]
	var seed_value := new_world_seed()
	return seed_value if _update_meta(slot, {"world_seed": seed_value}) else 0


## A new seed for a world: a whole number that stays exact when it goes through JSON (under 2^52).
static func new_world_seed() -> int:
	return maxi(((randi() & 0xFFFFF) << 32) | randi(), 1)


static func default_name(slot: int) -> String:
	return "World %d" % slot


## "2026-10-12 14:03" in local time, or an empty string for an unknown time.
static func format_time(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var local := Time.get_datetime_dict_from_unix_time(
		unix_time + int(Time.get_time_zone_from_system()["bias"]) * 60
	)
	return "%04d-%02d-%02d %02d:%02d" % [local["year"], local["month"], local["day"], local["hour"], local["minute"]]


## The metadata of [param slot] as saved, or null when it is missing or cannot be read. Fields this
## version of the game does not know are in it too, so a newer game's save is not stripped by an older one.
static func _load_meta(slot: int) -> Variant:
	var path := "%s/%s" % [slot_dir(slot), META_FILE]
	if not FileAccess.file_exists(path):
		return null
	# JSON.new().parse() reports a bad file quietly; JSON.parse_string() would log an error.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return null
	return json.data


## Changes some fields of a saved world and leaves everything else in it as it was.
static func _update_meta(slot: int, changes: Dictionary) -> bool:
	var meta: Variant = _load_meta(slot)
	if meta == null:
		return false
	meta.merge(changes, true)
	meta["version"] = FORMAT_VERSION
	return _write_meta(slot, meta)


static func _write_meta(slot: int, meta: Dictionary) -> bool:
	var dir_error := DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	if dir_error != OK:
		push_warning("[WorldSaves] Could not create %s (error %d)." % [slot_dir(slot), dir_error])
		return false
	var file := FileAccess.open("%s/%s" % [slot_dir(slot), META_FILE], FileAccess.WRITE)
	if file == null:
		push_warning("[WorldSaves] Could not write slot %d metadata (error %d)." % [slot, FileAccess.get_open_error()])
		return false
	var clean := meta.duplicate()
	for key in _WHOLE_NUMBERS:
		if clean.has(key):
			clean[key] = int(clean[key])
	file.store_string(JSON.stringify(clean, "\t"))
	return true
