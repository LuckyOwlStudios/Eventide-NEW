class_name ChunkStreamer
extends Node3D
## Builds the space around the ship (and the players) as they move, and drops it behind them. Space
## is cut into cubes ([member chunk_size] a side, see [ChunkGenerator]); the ones within
## [member load_distance] of something being followed are loaded as [SpaceChunk]s, and the ones left
## further behind than that plus [member unload_margin] are freed. However far the ship travels, only
## the space near it exists, so the number of asteroids loaded stays about the same.
##
## [b]Fading.[/b] Asteroids fade in and out with distance rather than appearing (see [SpaceChunk]).
## That only hides the loading if everything is invisible when its chunk is made or dropped, which
## needs [member load_distance] to be beyond [code]fade_end + fade_margin[/code]. [method get_fade_distances]
## says where the fade begins and ends, and a warning is printed if the two do not fit.
##
## [b]Keeping up.[/b] Chunks are made a few at a time, nearest first, each frame, within a time budget,
## so crossing into new space never stalls a frame. After a jump ([method begin_system]) the budget is
## raised until everything around the ship is there (see [method request_fast_load]).
##
## [b]What it follows.[/b] Anything handed to [method track], and any node in the
## [code]chunk_focus[/code] group.

## A new system was set up. Everything of the old one is gone and the new one is being built.
signal system_changed(system: StarSystem)
signal chunk_loaded(coord: Vector3i)
signal chunk_unloaded(coord: Vector3i)
## Everything that should be loaded now is. Sent again after each time something had to be built.
signal settled

## Nodes in this group are followed without being tracked.
const FOCUS_GROUP: StringName = &"chunk_focus"

@export_group("Chunks")
## How wide each chunk is. A chunk is what is built or dropped in one go.
@export_range(50.0, 5000.0, 10.0, "suffix:m") var chunk_size := 500.0
## Chunks whose nearest point is within this distance of something followed are loaded.
@export_range(100.0, 20000.0, 10.0, "suffix:m") var load_distance := 1500.0
## A loaded chunk is only dropped once it is this much further than [member load_distance], so one
## that sits right on the edge is not built and dropped again and again.
@export_range(0.0, 2000.0, 10.0, "suffix:m") var unload_margin := 150.0

@export_group("Fading")
## Asteroids are gone from this distance (plus the margin) from the camera.
@export_range(0.0, 20000.0, 10.0, "suffix:m") var fade_end := 1100.0
## The fade starts this far inside [member fade_end] and finishes this far beyond it.
@export_range(1.0, 5000.0, 10.0, "suffix:m") var fade_margin := 300.0

@export_group("Budget")
## The most chunks built in one frame.
@export_range(1, 100) var max_chunks_per_frame := 4
## Building stops for the frame once this much time has gone on it.
@export_range(0.5, 100.0, 0.5, "suffix:ms") var frame_budget_ms := 3.0
## How often it looks again at what should be loaded.
@export_range(0.02, 2.0, 0.01, "suffix:s") var update_interval := 0.25

@export_group("Models")
## How many asteroid shapes a system is made from.
@export_range(1, 64) var model_count := AsteroidShapes.DEFAULT_MODEL_COUNT
## How finely each is cut up (3 is 1280 triangles).
@export_range(0, 5) var model_detail := AsteroidShapes.DEFAULT_DETAIL

## The system being built, or null before there is one.
var system: StarSystem

var _generator: ChunkGenerator
var _shapes: AsteroidShapes
## What is loaded. An empty chunk (a void) has no node, so its value is null.
var _chunks: Dictionary[Vector3i, SpaceChunk] = {}
var _asteroid_total := 0
var _tracked: Array[Node3D] = []
var _manual_points := PackedVector3Array()
## Chunks still to build, farthest first so the nearest is at the back.
var _pending: Array[Vector3i] = []
var _wanted: Dictionary[Vector3i, bool] = {}
var _unloading: Array[Vector3i] = []
var _since_update := 0.0
var _dirty := false
var _settled := false
var _fast_budget_ms := 0.0


func _ready() -> void:
	var distances := get_fade_distances()
	if load_distance < distances.y:
		push_warning("%s loads chunks from %.0f m but asteroids are still visible out to %.0f m, so they will pop in. Raise load_distance or lower fade_end." % [get_path(), load_distance, distances.y])


func _process(delta: float) -> void:
	if system == null:
		return
	_shapes.tick(Time.get_ticks_msec() * 0.001)
	_since_update += delta
	if _dirty or _since_update >= update_interval:
		_since_update = 0.0
		_dirty = false
		_refresh()
	_work()


# --- Setting up a system --------------------------------------------------------

## Starts building [param new_system] and throws away every chunk of the one before.
func begin_system(new_system: StarSystem) -> void:
	_remove_all_chunks()
	system = new_system
	_generator = ChunkGenerator.new(system, chunk_size, model_count)
	_shapes = AsteroidShapes.for_system(system, model_count, model_detail)
	_pending.clear()
	_wanted.clear()
	_unloading.clear()
	_settled = false
	_dirty = true
	_since_update = 0.0
	system_changed.emit(system)


## Throws away everything and stops building until the next [method begin_system].
func clear() -> void:
	_remove_all_chunks()
	system = null
	_generator = null
	_shapes = null
	_pending.clear()
	_wanted.clear()
	_unloading.clear()


# --- What it follows -----------------------------------------------------------

## Keeps the space around [param node] loaded for as long as it is in the game.
func track(node: Node3D) -> void:
	if is_instance_valid(node) and not _tracked.has(node):
		_tracked.append(node)
		refresh()


func untrack(node: Node3D) -> void:
	_tracked.erase(node)
	refresh()


## Follows a fixed point as well (in this node's space), for things that are not nodes.
func set_extra_points(points: PackedVector3Array) -> void:
	_manual_points = points
	refresh()


## Looks again, next frame, at what should be loaded, instead of waiting for the next regular look
## (which is every [member update_interval]). Call it after moving something that is followed a long
## way at once, such as a teleport. Until it has built what was missing, [method is_settled] is false.
func refresh() -> void:
	_dirty = true
	_settled = false


## Where everything followed is, in this node's space.
func get_focus_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var seen: Array[Node3D] = []
	for index in range(_tracked.size() - 1, -1, -1):
		if not is_instance_valid(_tracked[index]):
			_tracked.remove_at(index)
	for node in _tracked:
		seen.append(node)
		if node.is_inside_tree():
			points.append(to_local(node.global_position))
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(FOCUS_GROUP):
			var spatial := node as Node3D
			if spatial != null and not seen.has(spatial) and spatial.is_inside_tree():
				points.append(to_local(spatial.global_position))
	points.append_array(_manual_points)
	return points


# --- Asking about it ---------------------------------------------------------------

## True when every chunk that should be loaded is, and nothing is left to drop.
func is_settled() -> bool:
	return _settled


func get_loaded_chunk_count() -> int:
	return _chunks.size()


func get_asteroid_count() -> int:
	return _asteroid_total


func is_chunk_loaded(coord: Vector3i) -> bool:
	return _chunks.has(coord)


## Every chunk that is loaded.
func get_loaded_coords() -> Array[Vector3i]:
	var coords: Array[Vector3i] = []
	coords.assign(_chunks.keys())
	return coords


## The node of a loaded chunk, or null for one that is not loaded or is empty.
func get_chunk(coord: Vector3i) -> SpaceChunk:
	return _chunks.get(coord)


## The chunk that contains [param point] (in this node's space).
func get_coord(point: Vector3) -> Vector3i:
	return Vector3i((point / chunk_size).floor())


## Where asteroids are fully drawn up to (x) and fully gone from (y), from the camera.
func get_fade_distances() -> Vector2:
	return Vector2(maxf(fade_end - fade_margin, 0.0), fade_end + fade_margin)


## The chunks that should be loaded for a followed point at [param point]: every one whose
## nearest point is within [member load_distance], as a dictionary from chunk to distance.
func get_chunks_in_range(point: Vector3) -> Dictionary[Vector3i, float]:
	var found: Dictionary[Vector3i, float] = {}
	var low := get_coord(point - Vector3.ONE * load_distance)
	var high := get_coord(point + Vector3.ONE * load_distance)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var coord := Vector3i(x, y, z)
				var distance := _distance_to_chunk(point, coord)
				if distance <= load_distance:
					found[coord] = distance
	return found


# --- Building ----------------------------------------------------------------------

## Builds faster, [param budget_ms] a frame and no limit on chunks, until everything that should
## be loaded is. For after a jump, when the space is hidden and wants to be there quickly. (A whole
## neighbourhood of about 200 chunks takes around 60 ms to build in the game, so this is a few frames.)
func request_fast_load(budget_ms: float = 6.0) -> void:
	_fast_budget_ms = budget_ms


## Builds everything that should be loaded this instant and returns. It stalls the frame it is
## called in, so it is for loading screens and tests.
func load_all_now() -> void:
	if system == null:
		return
	_refresh()
	_dirty = false
	while not _pending.is_empty():
		_load_chunk(_pending.pop_back())
	_work(true)


func _refresh() -> void:
	var points := get_focus_points()
	if points.is_empty():
		return
	_wanted.clear()
	var nearest: Dictionary[Vector3i, float] = {}
	for point in points:
		var in_range := get_chunks_in_range(point)
		for coord in in_range:
			if not nearest.has(coord) or in_range[coord] < nearest[coord]:
				nearest[coord] = in_range[coord]
	for coord in nearest:
		_wanted[coord] = true

	# What to build: the wanted chunks that are not there, the nearest last (it is popped first).
	var missing: Array[Vector3i] = []
	for coord in nearest:
		if not _chunks.has(coord):
			missing.append(coord)
	missing.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return nearest[a] > nearest[b])
	_pending = missing

	# What to drop: the loaded chunks that are further than the loading distance plus the margin from everything.
	_unloading.clear()
	var keep_distance := load_distance + unload_margin
	for coord in _chunks:
		var close := false
		for point in points:
			if _distance_to_chunk(point, coord) <= keep_distance:
				close = true
				break
		if not close:
			_unloading.append(coord)
	if not _pending.is_empty() or not _unloading.is_empty():
		_settled = false


func _work(unlimited := false) -> void:
	var budget := maxf(frame_budget_ms, _fast_budget_ms)
	var limit := 1 << 30 if _fast_budget_ms > 0.0 or unlimited else max_chunks_per_frame
	var started := Time.get_ticks_usec()
	var built := 0
	while not _unloading.is_empty():
		_unload_chunk(_unloading.pop_back())
		if not unlimited and (Time.get_ticks_usec() - started) / 1000.0 >= budget:
			return
	while not _pending.is_empty() and built < limit:
		if not unlimited and (Time.get_ticks_usec() - started) / 1000.0 >= budget:
			return
		_load_chunk(_pending.pop_back())
		built += 1
	if _pending.is_empty() and _unloading.is_empty() and not _settled and not _dirty:
		_settled = true
		_fast_budget_ms = 0.0
		settled.emit()


func _load_chunk(coord: Vector3i) -> void:
	if _chunks.has(coord) or not _wanted.has(coord):
		return
	var specs := _generator.generate(coord)
	if specs.is_empty():
		_chunks[coord] = null
	else:
		var chunk := SpaceChunk.new()
		chunk.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
		chunk.coord = coord
		chunk.position = _generator.get_origin(coord)
		chunk.build(specs, _shapes, fade_end, fade_margin)
		add_child(chunk)
		_chunks[coord] = chunk
		_asteroid_total += chunk.asteroid_count
	chunk_loaded.emit(coord)


func _unload_chunk(coord: Vector3i) -> void:
	if not _chunks.has(coord):
		return
	_free_chunk(_chunks[coord])
	_chunks.erase(coord)
	chunk_unloaded.emit(coord)


func _remove_all_chunks() -> void:
	for coord in _chunks.keys():
		_free_chunk(_chunks[coord])
	_chunks.clear()
	_asteroid_total = 0


## Takes the chunk out of the world at once (its bodies stop existing for physics this instant) and
## frees it when the frame is over.
func _free_chunk(chunk: SpaceChunk) -> void:
	if chunk == null:
		return
	_asteroid_total -= chunk.asteroid_count
	remove_child(chunk)
	chunk.queue_free()


func _distance_to_chunk(point: Vector3, coord: Vector3i) -> float:
	var low := Vector3(coord) * chunk_size
	return point.distance_to(point.clamp(low, low + Vector3.ONE * chunk_size))
