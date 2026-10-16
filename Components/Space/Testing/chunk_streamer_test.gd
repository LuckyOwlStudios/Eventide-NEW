extends Node
## Checks that space is built around whatever is followed and dropped behind it: the right chunks,
## a few at a time, no work for space that was left, new space for a new system, and asteroids
## that exist for physics and fade by distance for the eye.
##
## godot --headless --fixed-fps 60 --path . res://Components/Space/Testing/ChunkStreamerTest.tscn

var _failures := 0
var _world: Node3D
var _streamer: ChunkStreamer
var _ship: Node3D
var _loads_this_frame := 0
var _most_loads_in_a_frame := 0


func _ready() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	_streamer = ChunkStreamer.new()
	_streamer.update_interval = 0.05
	_world.add_child(_streamer)
	_ship = Node3D.new()
	_world.add_child(_ship)
	_streamer.track(_ship)
	_streamer.chunk_loaded.connect(func(_coord: Vector3i) -> void: _loads_this_frame += 1)

	await _test_loading()
	await _test_asteroid_nodes()
	await _test_physics()
	await _test_ship_hits_asteroids()
	await _test_moving()
	await _test_budget()
	await _test_systems()
	await _test_followers()

	_world.free()
	if _failures == 0:
		print("Chunk streamer tests passed.")
	else:
		print("Chunk streamer tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _process(_delta: float) -> void:
	_most_loads_in_a_frame = maxi(_most_loads_in_a_frame, _loads_this_frame)
	_loads_this_frame = 0


func _system(jump: int, arrival := Vector3.ZERO) -> StarSystem:
	return StarSystem.create(8080, jump, SystemTuning.new(), arrival)


# --- Loading ---------------------------------------------------------------------

func _test_loading() -> void:
	print("Loading space around the ship")
	var fade := _streamer.get_fade_distances()
	_check(_streamer.load_distance >= fade.y, "the default load distance (%.0f m) is beyond where asteroids are gone (%.0f m), so they never pop" % [_streamer.load_distance, fade.y])
	_check(fade.x < fade.y and fade.x > 0.0, "and the fade runs from %.0f m to %.0f m" % [fade.x, fade.y])
	_check(_streamer.system == null and not _streamer.is_settled(), "before a system there is nothing and nothing is settled")

	_ship.global_position = Vector3(10.0, 20.0, -30.0)
	var system := _system(2, _ship.global_position)
	var system_events: Array[StarSystem] = []
	_streamer.system_changed.connect(func(changed: StarSystem) -> void: system_events.append(changed))
	_streamer.begin_system(system)
	_check(system_events.size() == 1 and system_events[0] == system, "starting a system says so")
	_check(not _streamer.is_settled() and _streamer.get_loaded_chunk_count() == 0, "and nothing is built or settled yet")
	var started := Time.get_ticks_usec()
	_streamer.load_all_now()
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	var expected := _streamer.get_chunks_in_range(_ship.global_position)
	print("  info %d chunks, %d asteroids built in %.1f ms (%.2f ms a chunk)" % [_streamer.get_loaded_chunk_count(), _streamer.get_asteroid_count(), elapsed, elapsed / maxi(_streamer.get_loaded_chunk_count(), 1)])
	_check(_streamer.is_settled(), "once loaded it is settled")
	_check(_streamer.get_loaded_chunk_count() == expected.size(), "exactly the %d chunks within %.0f m of the ship are loaded" % [expected.size(), _streamer.load_distance])
	var every_chunk := true
	for coord in expected:
		every_chunk = every_chunk and _streamer.is_chunk_loaded(coord)
	_check(every_chunk, "each of them")
	_check(_streamer.is_chunk_loaded(_streamer.get_coord(_ship.global_position)), "including the one the ship is in")
	var far := _streamer.get_coord(_ship.global_position + Vector3(0.0, 0.0, 6000.0))
	_check(not _streamer.is_chunk_loaded(far), "and none far away")
	_check(expected.size() > 80 and expected.size() < 400, "a sensible number of chunks (%d)" % expected.size())
	_check(_streamer.get_asteroid_count() > 200, "and of asteroids (%d)" % _streamer.get_asteroid_count())

	var counted := 0
	var voids := 0
	var all_named := true
	for coord in _streamer.get_loaded_coords():
		var chunk := _streamer.get_chunk(coord)
		if chunk == null:
			voids += 1
		else:
			counted += chunk.asteroid_count
			all_named = all_named and chunk.coord == coord and chunk.get_child_count() == chunk.asteroid_count and chunk.position == Vector3(coord) * _streamer.chunk_size
	_check(counted == _streamer.get_asteroid_count(), "the asteroid count adds up over the chunks (%d)" % counted)
	_check(all_named and voids > 0, "chunks know where they are, and empty ones (%d) are loaded without a node" % voids)
	_check(_streamer.get_child_count() == _streamer.get_loaded_chunk_count() - voids, "so the streamer holds one node per chunk that has something in it")

	# The clear area around the arrival is empty.
	var intruder := false
	for coord in _streamer.get_loaded_coords():
		var chunk := _streamer.get_chunk(coord)
		if chunk == null:
			continue
		for child in chunk.get_children():
			var asteroid := child as Asteroid3D
			if asteroid.global_position.distance_to(system.arrival_position) < system.arrival_clear_radius + asteroid.radius - 0.01:
				intruder = true
	_check(not intruder, "and nothing is built inside the area kept clear around the arrival point")


func _test_asteroid_nodes() -> void:
	print("The asteroids")
	var generator := ChunkGenerator.new(_streamer.system, _streamer.chunk_size, _streamer.model_count)
	var shapes := AsteroidShapes.for_system(_streamer.system, _streamer.model_count, _streamer.model_detail)
	var coord := Vector3i.ZERO
	for candidate in _streamer.get_loaded_coords():
		var chunk := _streamer.get_chunk(candidate)
		if chunk != null and chunk.asteroid_count >= 3:
			coord = candidate
			break
	var chunk := _streamer.get_chunk(coord)
	_check(chunk != null, "there is a chunk with a few asteroids to look at %s" % str(coord))
	var specs := generator.generate(coord)
	_check(specs.size() == chunk.asteroid_count, "it holds what the generator says it should (%d)" % specs.size())
	var matches := true
	var layers := true
	var shaped := true
	var fading := true
	for index in specs.size():
		var asteroid := chunk.get_child(index) as Asteroid3D
		var spec := specs[index]
		if asteroid == null:
			matches = false
			continue
		matches = matches and asteroid.position.is_equal_approx(spec.position) and asteroid.basis.is_equal_approx(spec.basis) and is_equal_approx(asteroid.radius, spec.radius) and asteroid.model_index == spec.model
		layers = layers and asteroid.collision_layer == PhysicsLayers.WORLD and asteroid.collision_mask == 0
		var model := shapes.get_model(spec.model)
		var collision := asteroid.get_child(0) as CollisionShape3D
		var visual := asteroid.get_child(1) as MeshInstance3D
		shaped = shaped and collision.shape.get_faces() == model.collision.get_faces() and collision.scale.is_equal_approx(Vector3.ONE * spec.radius) and visual.scale.is_equal_approx(Vector3.ONE * spec.radius) and asteroid.type == model.asteroid
		shaped = shaped and visual.mesh.get_surface_count() == model.mesh.get_surface_count()
		fading = fading and visual.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF and is_equal_approx(visual.visibility_range_end, _streamer.fade_end) and is_equal_approx(visual.visibility_range_end_margin, _streamer.fade_margin)
		fading = fading and asteroid.scale.is_equal_approx(Vector3.ONE)
	_check(matches, "each asteroid is where, how big, how turned and which model the generator says")
	_check(layers, "each is on the World layer and scans nothing, like scenery")
	_check(shaped, "each has the model's mesh and collision shape, sized by scaling the shape and the mesh (the body stays unscaled)")
	_check(fading, "and each fades with distance from %.0f m out to %.0f m" % [_streamer.get_fade_distances().x, _streamer.get_fade_distances().y])
	var shared_meshes := {}
	var shared_shapes := {}
	for candidate in _streamer.get_loaded_coords():
		var other := _streamer.get_chunk(candidate)
		if other == null:
			continue
		for child in other.get_children():
			shared_meshes[(child.get_child(1) as MeshInstance3D).mesh] = true
			shared_shapes[(child.get_child(0) as CollisionShape3D).shape] = true
	_check(shared_meshes.size() <= _streamer.model_count and shared_shapes.size() <= _streamer.model_count, "and thousands of them share a handful of meshes and shapes (%d meshes, %d shapes for %d asteroids)" % [shared_meshes.size(), shared_shapes.size(), _streamer.get_asteroid_count()])


func _test_physics() -> void:
	print("Physics")
	# Let physics register the new bodies, then shoot a ray at a few asteroids from outside.
	for _i in 4:
		await get_tree().physics_frame
	var space := _world.get_world_3d().direct_space_state
	var hits := 0
	var shots := 0
	var worst := 0.0
	for coord in _streamer.get_loaded_coords():
		var chunk := _streamer.get_chunk(coord)
		if chunk == null:
			continue
		for child in chunk.get_children():
			var asteroid := child as Asteroid3D
			if shots >= 40:
				break
			shots += 1
			var direction := Vector3(0.3, 0.9, 0.3).normalized()
			var from := asteroid.global_position + direction * (asteroid.radius * 3.0)
			var query := PhysicsRayQueryParameters3D.create(from, asteroid.global_position, PhysicsLayers.WORLD)
			var result := space.intersect_ray(query)
			if not result.is_empty() and result["collider"] == asteroid:
				hits += 1
				var depth: float = (result["position"] as Vector3).distance_to(asteroid.global_position) / asteroid.radius
				worst = maxf(worst, absf(depth - 0.8))
	_check(shots >= 20, "there are asteroids to shoot at (%d)" % shots)
	_check(hits == shots, "a ray hits each asteroid it is aimed at, so they exist for physics (%d of %d)" % [hits, shots])

	# A heavy ball dropped onto an asteroid stops on it instead of falling through.
	var target: Asteroid3D
	for coord in _streamer.get_loaded_coords():
		var chunk := _streamer.get_chunk(coord)
		if chunk != null:
			for child in chunk.get_children():
				if (child as Asteroid3D).radius > 12.0:
					target = child as Asteroid3D
					break
		if target != null:
			break
	_check(target != null, "there is a big asteroid to drop a ball on")
	if target != null:
		var ball := RigidBody3D.new()
		ball.gravity_scale = 0.0
		ball.collision_layer = PhysicsLayers.ITEMS
		ball.collision_mask = PhysicsLayers.ITEM_MASK
		var ball_shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.5
		ball_shape.shape = sphere
		ball.add_child(ball_shape)
		_world.add_child(ball)
		ball.global_position = target.global_position + Vector3(0.0, target.radius * 2.0, 0.0)
		ball.linear_velocity = Vector3(0.0, -15.0, 0.0)
		var closest := 1.0e9
		for _frame in 240:
			await get_tree().physics_frame
			closest = minf(closest, ball.global_position.distance_to(target.global_position))
		var stopped := ball.global_position.distance_to(target.global_position)
		_check(closest > 0.3 * target.radius, "a ball thrown at a %.0f m asteroid at 15 m/s is stopped by it (closest %.1f m from the middle)" % [target.radius, closest])
		_check(stopped > 0.3 * target.radius, "and does not pass through (%.1f m from the middle after 4 s)" % stopped)
		ball.free()


## The real Mule flies into a big asteroid, as fast as it can boost, and is stopped by it.
func _test_ship_hits_asteroids() -> void:
	print("A ship flying into an asteroid")
	var target: Asteroid3D
	for coord in _streamer.get_loaded_coords():
		var chunk := _streamer.get_chunk(coord)
		if chunk == null:
			continue
		for child in chunk.get_children():
			var candidate := child as Asteroid3D
			if candidate.radius >= 14.0 and (target == null or candidate.radius > target.radius):
				target = candidate
	_check(target != null, "there is a big asteroid to fly at (%.0f m)" % (target.radius if target != null else 0.0))
	if target == null:
		return
	var mule := (load("res://Scenes/Vehicles/Mule/Mule.tscn") as PackedScene).instantiate() as RigidBody3D
	_world.add_child(mule)
	var heading := Vector3(0.6, 0.1, 0.8).normalized()
	mule.global_position = target.global_position - heading * (target.radius + 120.0)
	var speed := 75.0
	mule.linear_velocity = heading * speed
	var closest := 1.0e9
	var first_contact := -1.0
	for frame in 420:
		await get_tree().physics_frame
		closest = minf(closest, mule.global_position.distance_to(target.global_position))
		if first_contact < 0.0 and mule.linear_velocity.dot(heading) < speed * 0.5:
			first_contact = frame / 60.0
	var along := (mule.global_position - target.global_position).dot(heading)
	print("  info the ship got to %.1f m from the middle of a %.0f m asteroid, and ended %.1f m past its middle (first slowed after %.1f s)" % [closest, target.radius, along, first_contact])
	_check(first_contact > 0.0, "the ship is slowed when it reaches the asteroid (%.1f s in)" % first_contact)
	_check(closest > target.radius * 0.35, "and does not get inside it (closest %.1f m from the middle)" % closest)
	_check(along < target.radius * 0.5, "or come out the other side (%.1f m past the middle)" % along)
	mule.free()


# --- Following ----------------------------------------------------------------------

func _test_moving() -> void:
	print("Flying through space")
	var before := _streamer.get_loaded_coords()
	var before_asteroids := _streamer.get_asteroid_count()
	var unloaded: Array[Vector3i] = []
	var loaded: Array[Vector3i] = []
	var on_unload := func(coord: Vector3i) -> void: unloaded.append(coord)
	var on_load := func(coord: Vector3i) -> void: loaded.append(coord)
	_streamer.chunk_unloaded.connect(on_unload)
	_streamer.chunk_loaded.connect(on_load)

	# A short hop: nothing nearby is dropped, because it is still in range.
	_ship.global_position += Vector3(300.0, 0.0, 0.0)
	_streamer.refresh()
	await _until_settled(120)
	_check(_streamer.is_settled(), "after a short hop everything is loaded again")
	var wanted := _streamer.get_chunks_in_range(_ship.global_position)
	_check(_streamer.get_loaded_chunk_count() >= wanted.size(), "everything now in range is there (%d of %d)" % [_streamer.get_loaded_chunk_count(), wanted.size()])
	var hysteresis := 0
	for coord in _streamer.get_loaded_coords():
		if not wanted.has(coord):
			hysteresis += 1
	_check(hysteresis > 0, "and chunks just past the loading distance are kept rather than dropped at once (%d)" % hysteresis)
	var keep := _streamer.load_distance + _streamer.unload_margin
	var too_far := 0
	for coord in _streamer.get_loaded_coords():
		if _distance_to_chunk(_ship.global_position, coord) > keep + 0.01:
			too_far += 1
	_check(too_far == 0, "but nothing is kept beyond the loading distance plus the margin")

	# A long way: all the old space goes and new space is built.
	loaded.clear()
	unloaded.clear()
	_ship.global_position += Vector3(5000.0, 400.0, 0.0)
	_streamer.refresh()
	await _until_settled(600)
	_check(_streamer.is_settled(), "after a long flight it settles")
	var old_left := 0
	for coord in before:
		if _streamer.is_chunk_loaded(coord):
			old_left += 1
	_check(old_left == 0, "none of the space left behind is still loaded")
	var now_wanted := _streamer.get_chunks_in_range(_ship.global_position)
	_check(_streamer.get_loaded_chunk_count() >= now_wanted.size() and _streamer.get_loaded_chunk_count() <= now_wanted.size() + 80, "the new space is there and not much else (%d loaded, %d in range)" % [_streamer.get_loaded_chunk_count(), now_wanted.size()])
	_check(loaded.size() >= now_wanted.size() and unloaded.size() >= before.size(), "with a signal for each chunk loaded (%d) and dropped (%d)" % [loaded.size(), unloaded.size()])
	var ratio := float(_streamer.get_asteroid_count()) / maxf(before_asteroids, 1.0)
	_check(ratio > 0.4 and ratio < 2.5, "so how many asteroids are loaded stays about the same wherever the ship is (%d now, %d at the start)" % [_streamer.get_asteroid_count(), before_asteroids])
	# The nodes of dropped chunks are really gone.
	await get_tree().process_frame
	await get_tree().process_frame
	var nodes := 0
	for child in _streamer.get_children():
		nodes += 1
	_check(nodes <= _streamer.get_loaded_chunk_count(), "and so are their nodes (%d chunk nodes for %d chunks)" % [nodes, _streamer.get_loaded_chunk_count()])
	_streamer.chunk_unloaded.disconnect(on_unload)
	_streamer.chunk_loaded.disconnect(on_load)

	print("A flight at 75 m/s for twenty seconds")
	_ship.global_position = Vector3.ZERO
	_streamer.begin_system(_system(3, Vector3.ZERO))
	_streamer.load_all_now()
	var start_count := _streamer.get_asteroid_count()
	var low := start_count
	var high := start_count
	var longest := 0.0
	var last := Time.get_ticks_usec()
	for _frame in 1200:
		_ship.global_position += Vector3(1.25, 0.2, 0.4)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		longest = maxf(longest, (now - last) / 1000.0)
		last = now
		low = mini(low, _streamer.get_asteroid_count())
		high = maxi(high, _streamer.get_asteroid_count())
	await _until_settled(120)
	var travelled := _ship.global_position.length()
	print("  info flew %.0f m; asteroids loaded between %d and %d; longest frame %.1f ms; most chunks built in one frame %d" % [travelled, low, high, longest, _most_loads_in_a_frame])
	_check(travelled > 1500.0, "the ship got a good way (%.0f m)" % travelled)
	_check(low > start_count * 0.4 and high < start_count * 2.5, "and the number of asteroids stayed between %d and %d" % [low, high])


func _test_budget() -> void:
	print("Not stalling the game")
	_ship.global_position = Vector3.ZERO
	_streamer.begin_system(_system(4))
	_most_loads_in_a_frame = 0
	_loads_this_frame = 0
	var frames := 0
	while not _streamer.is_settled() and frames < 2000:
		await get_tree().process_frame
		frames += 1
	var total := _streamer.get_loaded_chunk_count()
	_check(_streamer.is_settled(), "a whole new neighbourhood is built bit by bit (%d chunks in %d frames)" % [total, frames])
	_check(_most_loads_in_a_frame <= _streamer.max_chunks_per_frame, "never more than %d chunks in a frame (most %d)" % [_streamer.max_chunks_per_frame, _most_loads_in_a_frame])
	_check(frames >= float(total) / _streamer.max_chunks_per_frame - 1.0, "so it takes its time rather than all at once")

	_streamer.begin_system(_system(5))
	_streamer.request_fast_load()
	_most_loads_in_a_frame = 0
	var fast_frames := 0
	while not _streamer.is_settled() and fast_frames < 2000:
		await get_tree().process_frame
		fast_frames += 1
	_check(_streamer.is_settled() and fast_frames < frames, "asked to hurry, it settles sooner (%d frames against %d)" % [fast_frames, frames])
	_check(_streamer.get_loaded_chunk_count() >= total - 40, "with the same space around the ship")


# --- Systems and followers ---------------------------------------------------------------

func _test_systems() -> void:
	print("A new system")
	_ship.global_position = Vector3.ZERO
	_streamer.begin_system(_system(6))
	_streamer.load_all_now()
	var first_positions := _asteroid_positions()
	var first_count := _streamer.get_asteroid_count()
	var first_chunks := _streamer.get_child_count()
	_streamer.begin_system(_system(7))
	_check(_streamer.get_child_count() == 0 and _streamer.get_loaded_chunk_count() == 0 and _streamer.get_asteroid_count() == 0, "starting another system throws away all of the old one at once")
	_check(not _streamer.is_settled(), "and it is not settled until the new one is built")
	_streamer.load_all_now()
	var second_positions := _asteroid_positions()
	_check(first_positions != second_positions and not first_positions.is_empty() and not second_positions.is_empty(), "the new one is different space (%d against %d asteroids)" % [first_count, _streamer.get_asteroid_count()])
	_check(_streamer.is_settled(), "and settles")
	# Going back to the first system rebuilds it exactly.
	_streamer.begin_system(_system(6))
	_streamer.load_all_now()
	_check(_asteroid_positions() == first_positions and _streamer.get_child_count() == first_chunks, "while building the same system again gives exactly the same asteroids")
	await get_tree().process_frame
	await get_tree().process_frame
	_streamer.clear()
	_check(_streamer.system == null and _streamer.get_child_count() == 0 and _streamer.get_loaded_chunk_count() == 0, "and clearing leaves nothing")
	_streamer.begin_system(_system(1))


func _test_followers() -> void:
	print("What it follows")
	_ship.global_position = Vector3.ZERO
	_streamer.begin_system(_system(1))
	_streamer.load_all_now()
	var near_ship := _streamer.get_loaded_chunk_count()
	var player := Node3D.new()
	_world.add_child(player)
	player.global_position = Vector3(20000.0, 0.0, 0.0)
	_streamer.track(player)
	await _until_settled(600)
	_check(_streamer.is_chunk_loaded(_streamer.get_coord(Vector3.ZERO)) and _streamer.is_chunk_loaded(_streamer.get_coord(player.global_position)), "with a second thing followed, space is loaded around both")
	_check(_streamer.get_loaded_chunk_count() > near_ship * 1.5, "so about twice as much is loaded (%d chunks against %d)" % [_streamer.get_loaded_chunk_count(), near_ship])
	_streamer.untrack(player)
	await _until_settled(600)
	_check(not _streamer.is_chunk_loaded(_streamer.get_coord(player.global_position)) and _streamer.is_chunk_loaded(_streamer.get_coord(Vector3.ZERO)), "when it is no longer followed, its space is dropped and the ship's is kept")
	var spotter := Node3D.new()
	spotter.add_to_group(ChunkStreamer.FOCUS_GROUP)
	_world.add_child(spotter)
	spotter.global_position = Vector3(0.0, 30000.0, 0.0)
	_streamer.refresh()
	await _until_settled(600)
	_check(_streamer.is_chunk_loaded(_streamer.get_coord(spotter.global_position)), "anything in the chunk_focus group is followed too")
	spotter.free()
	_streamer.refresh()
	await _until_settled(600)
	_check(not _streamer.is_chunk_loaded(_streamer.get_coord(Vector3(0.0, 30000.0, 0.0))), "and let go of when it is gone")
	var doomed := Node3D.new()
	_world.add_child(doomed)
	_streamer.track(doomed)
	doomed.free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_streamer.get_focus_points().size() == 1, "a followed node that is freed is forgotten without an error")
	_ship.free()
	await get_tree().process_frame
	_streamer.set_extra_points(PackedVector3Array([Vector3(0.0, 0.0, 40000.0)]))
	await _until_settled(600)
	_check(_streamer.is_chunk_loaded(_streamer.get_coord(Vector3(0.0, 0.0, 40000.0))), "a fixed point can be followed with no node at all")


func _asteroid_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	var coords := _streamer.get_loaded_coords()
	coords.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	for coord in coords:
		var chunk := _streamer.get_chunk(coord)
		if chunk != null:
			for child in chunk.get_children():
				positions.append((child as Node3D).global_position)
	return positions


func _distance_to_chunk(point: Vector3, coord: Vector3i) -> float:
	var low := Vector3(coord) * _streamer.chunk_size
	return point.distance_to(point.clamp(low, low + Vector3.ONE * _streamer.chunk_size))


func _until_settled(max_frames: int) -> void:
	var frames := 0
	while not _streamer.is_settled() and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	# One more look, since moving again after settling clears it only at the next refresh.
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
