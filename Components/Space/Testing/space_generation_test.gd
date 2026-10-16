extends Node
## Checks the seeded part of space generation, which makes no nodes: the random numbers, the system templates and the
## systems they make, the stars, the kinds of asteroid and how they are mixed, the asteroid models and what is in a
## chunk. The main thing they all promise is that the same seed builds the same space, so a saved world and every player
## in a lobby agree.
##
## godot --headless --fixed-fps 60 --path . res://Components/Space/Testing/SpaceGenerationTest.tscn

const Kit := preload("res://Components/Space/Testing/space_test_kit.gd")

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	_test_random()
	_test_system()
	_test_templates()
	_test_shipped_templates()
	_test_stars()
	_test_icosphere()
	_test_asteroid_weights()
	_test_asteroid_mix()
	_test_shipped_asteroids()
	_test_models()
	_test_decorations()
	_test_materials()
	_test_drops()
	_test_chunks()
	_test_difficulty_in_chunks()
	if _failures == 0:
		print("Space generation tests passed.")
	else:
		print("Space generation tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- SpaceRandom -------------------------------------------------------------

func _test_random() -> void:
	print("Random numbers")
	# The reference output of SplitMix64 for the state 1234567, from the algorithm's authors.
	var reference := SpaceRandom.new()
	reference._state = 1234567
	var expected := ["6457827717110365317", "3203168211198807973", "9817491932198370423", "4593380528125082431", "16408922859458223821"]
	var matches := true
	for text in expected:
		if String.num_uint64(reference.next_int()) != text:
			matches = false
	_check(matches, "the generator is SplitMix64: it reproduces the reference numbers")

	var a := SpaceRandom.new(99)
	var b := SpaceRandom.new(99)
	var same := true
	for _i in 200:
		if a.next_int() != b.next_int():
			same = false
	_check(same, "the same seed gives the same numbers")
	_check(SpaceRandom.new(1).next_int() != SpaceRandom.new(2).next_int(), "neighbouring seeds give different numbers")
	_check(SpaceRandom.chunk_seed(5, Vector3i(1, 2, 3)) == SpaceRandom.chunk_seed(5, Vector3i(1, 2, 3)), "a chunk's seed is always the same")
	var neighbours := {}
	for x in range(-4, 5):
		for y in range(-4, 5):
			for z in range(-4, 5):
				neighbours[SpaceRandom.chunk_seed(5, Vector3i(x, y, z))] = true
	_check(neighbours.size() == 729, "729 neighbouring chunks all get a seed of their own (%d)" % neighbours.size())
	_check(SpaceRandom.chunk_seed(5, Vector3i(1, 2, 3)) != SpaceRandom.chunk_seed(6, Vector3i(1, 2, 3)), "and another system's chunk gets another")
	_check(SpaceRandom.chunk_seed(5, Vector3i(1, 2, 3)) != SpaceRandom.chunk_seed(5, Vector3i(3, 2, 1)), "and the order of the coordinates matters")

	var rng := SpaceRandom.new(7)
	var low := 1.0
	var high := 0.0
	var sum := 0.0
	for _i in 20000:
		var value := rng.next_float()
		low = minf(low, value)
		high = maxf(high, value)
		sum += value
	_check(low >= 0.0 and high < 1.0, "next_float stays from 0 up to but not including 1 (%.5f to %.5f)" % [low, high])
	_check(absf(sum / 20000.0 - 0.5) < 0.01, "and averages a half (%.4f)" % (sum / 20000.0))
	var counts := [0, 0, 0, 0]
	for _i in 8000:
		counts[rng.range_int(2, 5) - 2] += 1
	_check(counts.min() > 1800 and counts.max() < 2200, "range_int reaches both ends evenly %s" % str(counts))
	_check(rng.range_int(4, 4) == 4 and rng.range_int(5, 3) == 5, "and copes with a range of one")
	var straight := true
	for _i in 100:
		var turn := rng.rotation()
		if not (turn * turn.transposed()).is_equal_approx(Basis.IDENTITY) or absf(turn.determinant() - 1.0) > 0.001:
			straight = false
		if absf(rng.unit_vector().length() - 1.0) > 0.0001:
			straight = false
	_check(straight, "rotations are proper turns and directions have length one")
	var picks := [0, 0, 0]
	var weights := PackedFloat32Array([1.0, 0.0, 3.0])
	for _i in 4000:
		picks[rng.pick_weighted(weights)] += 1
	_check(picks[1] == 0 and picks[2] > picks[0] * 2, "pick_weighted follows the weights %s" % str(picks))
	_check(rng.pick_weighted(PackedFloat32Array([0.0, 0.0])) == -1, "and says -1 when nothing can be picked")


# --- StarSystem ---------------------------------------------------------------

func _test_system() -> void:
	print("Systems")
	var tuning := SystemTuning.new()
	var flat := Kit.flat_template()
	var first := StarSystem.create(1234, 7, tuning)
	var again := StarSystem.create(1234, 7, tuning)
	_check(first.system_seed == again.system_seed and first.system_name == again.system_name and is_equal_approx(first.presence_fill_time, again.presence_fill_time) and is_equal_approx(first.asteroid_density, again.asteroid_density) and first.template == again.template and is_equal_approx(first.temperature, again.temperature), "a system built twice from the same two numbers is the same system")
	_check(first.jump_count == 7, "it knows its jump count")
	var seeds := {}
	for jump in 300:
		seeds[StarSystem.create(1234, jump, tuning).system_seed] = true
	_check(seeds.size() == 300, "every one of 300 jumps gets a seed of its own (%d)" % seeds.size())
	_check(StarSystem.create(1, 5, tuning).system_seed != StarSystem.create(2, 5, tuning).system_seed, "another world gets another seed at the same jump")
	_check(StarSystem.create(1234, -5, tuning).jump_count == 0, "a negative jump count counts as the start")

	# (A flat template keeps the temperature and density the same, so only the jump count changes the numbers.)
	var difficulty := -1.0
	var rising := true
	var fill_time := 1.0e9
	var shrinking := true
	var density := -1.0
	var thickening := true
	var largest := -1.0
	var growing := true
	for jump in range(0, 400, 5):
		var system := StarSystem.create(9, jump, tuning, Vector3.ZERO, flat)
		rising = rising and system.difficulty >= difficulty and system.difficulty >= 0.0 and system.difficulty < 1.0
		shrinking = shrinking and system.presence_fill_time <= fill_time + 0.0001
		thickening = thickening and system.asteroid_density >= density - 0.0001
		growing = growing and system.largest_radius >= largest - 0.0001
		difficulty = system.difficulty
		fill_time = system.presence_fill_time
		density = system.asteroid_density
		largest = system.largest_radius
	_check(rising, "difficulty only goes up with the jump count, and stays below 1")
	_check(shrinking, "the time the presence takes to cross the bar only shrinks")
	_check(thickening, "the asteroids only get thicker")
	_check(growing, "and the biggest asteroid only gets bigger")
	var start := StarSystem.create(9, 0, tuning, Vector3.ZERO, flat)
	_check(is_zero_approx(start.difficulty) and is_equal_approx(start.presence_fill_time, tuning.easy_fill_time) and is_equal_approx(start.asteroid_density, tuning.easy_density), "the first system is the easiest one: the slowest presence and easy density")
	var halfway := StarSystem.create(9, int(tuning.halfway_jump), tuning, Vector3.ZERO, flat)
	_check(is_equal_approx(halfway.difficulty, 0.5), "at the halfway jump it is half as hard as it gets (%.3f)" % halfway.difficulty)
	var late := StarSystem.create(9, 5000, tuning, Vector3.ZERO, flat)
	_check(late.presence_fill_time >= tuning.hard_fill_time - 0.001 and late.presence_fill_time < tuning.hard_fill_time + 10.0, "far on, the time to cross the bar approaches the fastest (%.1f s)" % late.presence_fill_time)

	var custom := SystemTuning.new()
	custom.easy_fill_time = 90.0
	custom.hard_fill_time = 30.0
	custom.easy_density = 1.0
	_check(is_equal_approx(StarSystem.create(3, 0, custom, Vector3.ZERO, flat).presence_fill_time, 90.0) and is_equal_approx(StarSystem.create(3, 0, custom, Vector3.ZERO, flat).asteroid_density, 1.0), "tuning decides the numbers")
	var arrival := StarSystem.create(3, 1, custom, Vector3(10.0, 20.0, 30.0))
	_check(arrival.arrival_position == Vector3(10.0, 20.0, 30.0) and is_equal_approx(arrival.arrival_clear_radius, custom.arrival_clear_radius), "and the arrival point is kept")
	var names := {}
	var well_formed := true
	var pattern := RegEx.create_from_string("^[A-Z][a-z]+-\\d{3}$")
	for jump in 200:
		var named := StarSystem.create(77, jump, tuning).system_name
		names[named] = true
		if pattern.search(named) == null:
			well_formed = false
	_check(well_formed, "every system name looks like Hel-417")
	_check(names.size() > 150, "and most of them are different (%d of 200)" % names.size())


# --- Templates ------------------------------------------------------------------

func _test_templates() -> void:
	print("Templates")
	var tuning := SystemTuning.new()
	var early := Kit.flat_template()
	early.display_name = "Early"
	early.weight = 3.0
	var late := Kit.flat_template()
	late.display_name = "Late"
	late.weight = 1.0
	late.min_jump = 10
	var never := Kit.flat_template()
	never.display_name = "Never"
	never.weight = 0.0
	var pool: Array[SystemTemplate] = [early, late, never]

	_check(early.is_available(0) and not late.is_available(9) and late.is_available(10) and not never.is_available(50), "a template is available from its jump on, and not at all with no weight")
	var available_at_five := SystemRegistry.get_available(5, pool)
	_check(available_at_five.size() == 1 and available_at_five[0] == early and SystemRegistry.get_available(10, pool).size() == 2, "so only those turn up in the pool for a jump")
	var gated := true
	for system_seed in 300:
		gated = gated and SystemRegistry.pick(system_seed * 7919, 9, pool) == early
	_check(gated, "a template whose jump has not come is never picked")
	var late_picks := 0
	var early_picks := 0
	var zero_picks := 0
	for system_seed in 4000:
		var picked := SystemRegistry.pick(system_seed * 104729, 30, pool)
		if picked == late:
			late_picks += 1
		elif picked == early:
			early_picks += 1
		else:
			zero_picks += 1
	_check(zero_picks == 0 and absf(float(late_picks) / 4000.0 - 0.25) < 0.04, "and the odds follow the weights: 3 to 1 is a quarter (%.1f%%, none of the weightless one)" % (late_picks / 40.0))
	_check(SystemRegistry.pick(5, 3, pool) == SystemRegistry.pick(5, 3, pool), "the same seed and jump always pick the same template")
	var empty_pool: Array[SystemTemplate] = [never]
	var fallback := SystemRegistry.pick(1, 5, empty_pool)
	_check(fallback != null and fallback.stars.size() == 1 and fallback.is_available(0), "with no template to pick, a plain normal system is made")
	var registry_sorted := true
	var paths: Array[String] = []
	for template in SystemRegistry.get_templates():
		paths.append(template.resource_path)
	for index in range(1, paths.size()):
		registry_sorted = registry_sorted and paths[index - 1] < paths[index]
	_check(paths.size() >= 3 and registry_sorted, "the registry finds the templates in the folder, sorted by path (%d)" % paths.size())

	# The first system.
	var starting := Kit.flat_template()
	starting.display_name = "Starting"
	var with_start := SystemTuning.new()
	with_start.starting_template = starting
	var always_start := true
	for world in 60:
		always_start = always_start and StarSystem.create(world * 31 + 1, 0, with_start).template == starting
	_check(always_start, "the first system of every world is the starting template")
	var by_default := StarSystem.create(5, 0, tuning)
	_check(by_default.template != null and by_default.template.get_display_name() == "Normal System" and by_default.stars.size() == 1, "(and a plain normal system when there is none)")
	var shipped_tuning := load("res://Game/Registry/Systems/default_system_tuning.tres") as SystemTuning
	_check(shipped_tuning != null and shipped_tuning.starting_template != null and shipped_tuning.starting_template.get_display_name() == "Normal System", "the game's own tuning starts in the normal system")
	var forced := StarSystem.create(5, 0, with_start, Vector3.ZERO, early)
	_check(forced.template == early, "a template can be forced (for testing)")
	var not_always_start := false
	for world in 200:
		if StarSystem.create(world * 31 + 1, 12, with_start).template != starting:
			not_always_start = true
	_check(not_always_start, "while later systems are picked by the odds")

	# What a system takes from its template.
	var hot := Kit.flat_template(60.0, 0.75, 2)
	hot.display_name = "Flat"
	var hot_system := StarSystem.create(1, 4, tuning, Vector3.ZERO, hot)
	_check(is_equal_approx(hot_system.temperature, 60.0) and hot_system.climate == TemperatureHandler.Climate.HOT and hot_system.get_climate_name() == "Hot", "a system's temperature comes from its template's range, and its climate from the temperature")
	_check(is_equal_approx(hot_system.density, 0.75) and hot_system.get_density_name() == "High", "and so does its density")
	_check(hot_system.get_description() == "Hot · 80°C · Flat", "described as the climate, the degrees and the kind (%s)" % hot_system.get_description())
	var ranged := SystemTemplate.new()
	ranged.temperature_min = -30.0
	ranged.temperature_max = 40.0
	ranged.density_min = 0.2
	ranged.density_max = 0.6
	ranged.stars.append(Kit.star())
	var inside := true
	var coldest := 1000.0
	var hottest := -1000.0
	var thinnest := 10.0
	var thickest := -10.0
	for system_seed in 500:
		var system := StarSystem.create(system_seed * 6007, 3, tuning, Vector3.ZERO, ranged)
		inside = inside and system.temperature >= -30.0 and system.temperature <= 40.0 and system.density >= 0.2 and system.density <= 0.6
		coldest = minf(coldest, system.temperature)
		hottest = maxf(hottest, system.temperature)
		thinnest = minf(thinnest, system.density)
		thickest = maxf(thickest, system.density)
	_check(inside, "every system's temperature and density lie inside the template's ranges")
	_check(coldest < -20.0 and hottest > 30.0 and thinnest < 0.28 and thickest > 0.52, "and use the whole of them (%.0f to %.0f degrees, %.2f to %.2f density)" % [coldest, hottest, thinnest, thickest])
	var backwards := SystemTemplate.new()
	backwards.temperature_min = 40.0
	backwards.temperature_max = -30.0
	_check(is_equal_approx(backwards.get_temperature_at(0.0), -30.0) and is_equal_approx(backwards.get_temperature_at(1.0), 40.0), "a range written the wrong way round still works")
	_check(ranged.get_temperature_words() == "Cool to Warm" and Kit.flat_template(0.0).get_temperature_words() == "Temperate", "a template says what its temperatures are called (%s)" % ranged.get_temperature_words())

	# Density.
	_check(StarSystem.get_density_word(0.0) == "Sparse" and StarSystem.get_density_word(0.25) == "Low" and StarSystem.get_density_word(0.5) == "Medium" and StarSystem.get_density_word(0.75) == "High" and StarSystem.get_density_word(1.0) == "Packed", "densities have words: sparse, low, medium, high and packed")
	_check(is_equal_approx(StarSystem.get_density_factor(0.0, tuning), tuning.sparse_density_factor) and is_equal_approx(StarSystem.get_density_factor(0.5, tuning), 1.0) and is_equal_approx(StarSystem.get_density_factor(1.0, tuning), tuning.packed_density_factor), "a medium system has the usual asteroids, a sparse one fewer and a packed one more")
	var density_rises := true
	var last_factor := -1.0
	for step in 21:
		var factor := StarSystem.get_density_factor(step / 20.0, tuning)
		density_rises = density_rises and factor >= last_factor
		last_factor = factor
	_check(density_rises, "and the thicker the density, the more asteroids")
	var sparse := StarSystem.create(3, 0, tuning, Vector3.ZERO, Kit.flat_template(0.0, 0.0))
	var packed := StarSystem.create(3, 0, tuning, Vector3.ZERO, Kit.flat_template(0.0, 1.0))
	_check(is_equal_approx(sparse.asteroid_density, tuning.easy_density * tuning.sparse_density_factor) and is_equal_approx(packed.asteroid_density, tuning.easy_density * tuning.packed_density_factor), "so a system's asteroids per chunk follow its density (%.1f, %.1f)" % [sparse.asteroid_density, packed.asteroid_density])

	# Tags.
	var tagged := Kit.flat_template(-90.0, 0.5, 2)
	tagged.tags.append("crystalline")
	tagged.tags.append("hot")
	tagged.tags.append("crystalline")
	var tagged_system := StarSystem.create(8, 2, tuning, Vector3.ZERO, tagged)
	_check(tagged_system.has_tag("crystalline") and tagged_system.has_tag("frozen") and tagged_system.has_tag("binary") and not tagged_system.has_tag("single"), "a system has its template's tags, its climate's and its star count's (%s)" % str(tagged_system.tags))
	var duplicates := tagged_system.tags.size() == 4
	_check(duplicates, "each only once (%d)" % tagged_system.tags.size())
	var no_stars := Kit.flat_template(0.0, 0.5, 0)
	var starless := StarSystem.create(8, 2, tuning, Vector3.ZERO, no_stars)
	_check(starless.stars.is_empty() and starless.get_star_count() == 0 and not starless.has_tag("single"), "a template with no stars makes a system with none, which is nothing to be afraid of")
	var triple := StarSystem.create(8, 2, tuning, Vector3.ZERO, Kit.flat_template(0.0, 0.5, 3))
	_check(triple.has_tag("ternary") and triple.stars.size() == 3, "and three stars make it ternary")

	var scene_template := SystemTemplate.new()
	scene_template.scene = Kit.cone_scene()
	var with_scene := StarSystem.create(8, 2, tuning, Vector3.ZERO, scene_template)
	_check(with_scene.template.scene != null, "a system knows its template's own scene (the jump director puts it into the world)")


## The three kinds of system the game ships with, as they were asked for.
func _test_shipped_templates() -> void:
	print("The game's templates")
	var tuning := SystemTuning.new()
	var templates := Kit.registry_templates()
	_check(templates.has("Normal System") and templates.has("Giant Star") and templates.has("Binary System"), "the Normal System, the Giant Star and the Binary System are registered (%s)" % str(templates.keys()))
	if not (templates.has("Normal System") and templates.has("Giant Star") and templates.has("Binary System")):
		return
	var normal: SystemTemplate = templates["Normal System"]
	var giant: SystemTemplate = templates["Giant Star"]
	var binary: SystemTemplate = templates["Binary System"]

	_check(normal.min_jump == 0 and normal.get_temperature_words() == "Temperate" and StarSystem.get_density_word(normal.density_min) == "Low" and StarSystem.get_density_word(normal.density_max - 0.001) == "High" and normal.stars.size() == 1, "a Normal System: from jump 0, temperate, low to high density, one star")
	_check(giant.min_jump == 5 and giant.get_temperature_words() == "Scorching" and StarSystem.get_density_word(giant.density_min) == "Medium" and StarSystem.get_density_word(giant.density_max - 0.001) == "High" and giant.stars.size() == 1, "a Giant Star: from jump 5, scorching, medium to high density, one star")
	_check(binary.min_jump == 0 and binary.get_temperature_words() == "Hot" and StarSystem.get_density_word(binary.density_min) == "Medium" and StarSystem.get_density_word(binary.density_max - 0.001) == "Medium" and binary.stars.size() == 2, "a Binary System: from jump 0, hot, medium density, two stars")
	_check(normal.weight > binary.weight and binary.weight > giant.weight, "the normal system is the commonest, then the binary one, then the giant")
	_check(giant.stars[0].color.r > 0.8 and giant.stars[0].color.b < 0.4 and giant.stars[0].distance < 0.15, "the giant is one massive red star (distance %.2f)" % giant.stars[0].distance)
	_check(binary.stars[0].random_color and binary.stars[1].random_color and not normal.stars[0].random_color and normal.stars[0].color.r > 0.9 and normal.stars[0].color.b > 0.5, "the binary's stars have randomized colors and the normal star is a plain warm white")

	var normal_ok := true
	var giant_ok := true
	var binary_ok := true
	var counts := {"Normal System": 0, "Giant Star": 0, "Binary System": 0}
	var smallest_giant := 1000.0
	var radii_normal := PackedFloat32Array()
	var colors_differ := 0
	var binary_count := 0
	for system_seed in 1500:
		var jump := 5 + system_seed % 60
		var system := StarSystem.create(system_seed * 7919 + 11, jump, tuning)
		var kind := system.template.get_display_name()
		counts[kind] = int(counts.get(kind, 0)) + 1
		match kind:
			"Normal System":
				normal_ok = normal_ok and system.stars.size() == 1 and system.climate == TemperatureHandler.Climate.TEMPERATE and system.temperature >= -20.0 and system.temperature <= 20.0
				radii_normal.append(rad_to_deg(system.stars[0].angular_radius))
			"Giant Star":
				giant_ok = giant_ok and system.stars.size() == 1 and system.climate == TemperatureHandler.Climate.SCORCHING and system.temperature >= 80.0
				smallest_giant = minf(smallest_giant, rad_to_deg(system.stars[0].angular_radius))
			"Binary System":
				binary_ok = binary_ok and system.stars.size() == 2 and system.climate == TemperatureHandler.Climate.HOT
				binary_count += 1
				if not system.stars[0].color.is_equal_approx(system.stars[1].color):
					colors_differ += 1
	_check(normal_ok, "every normal system is temperate with one star")
	_check(giant_ok, "every giant system is scorching with one star")
	_check(binary_ok, "every binary system is hot with two")
	_check(counts["Normal System"] > counts["Binary System"] and counts["Binary System"] > counts["Giant Star"] and counts["Giant Star"] > 50, "and all three turn up, in the order of their weights (%s)" % str(counts))
	_check(smallest_giant > 14.0, "a giant's star fills a large part of the sky: never under %.0f degrees across half" % smallest_giant)
	var normal_low := 100.0
	var normal_high := 0.0
	for radius in radii_normal:
		normal_low = minf(normal_low, radius)
		normal_high = maxf(normal_high, radius)
	_check(normal_low > 4.0 and normal_high < 8.5, "while a normal star looks about six degrees across half, a little more when the system is warmer (%.1f to %.1f)" % [normal_low, normal_high])
	_check(binary_count > 0 and colors_differ > binary_count * 0.5, "and the two stars of a binary are mostly different colors (%d of %d)" % [colors_differ, binary_count])

	var gated := true
	var giant_early := 0
	var first_ok := true
	for system_seed in 600:
		for jump in range(1, 5):
			var system := StarSystem.create(system_seed * 6007 + jump, jump, tuning)
			if system.template == giant:
				giant_early += 1
			gated = gated and system.template != giant
		first_ok = first_ok and StarSystem.create(system_seed * 6007, 0, load("res://Game/Registry/Systems/default_system_tuning.tres")).template == normal
	_check(gated and giant_early == 0, "no giant star before jump 5")
	var giants_at_five := 0
	var binaries_at_one := 0
	for system_seed in 800:
		if StarSystem.create(system_seed * 31 + 5, 5, tuning).template == giant:
			giants_at_five += 1
		if StarSystem.create(system_seed * 31 + 1, 1, tuning).template == binary:
			binaries_at_one += 1
	_check(giants_at_five > 0, "and they do turn up at jump 5 (%d of 800)" % giants_at_five)
	_check(binaries_at_one > 0, "while a binary system can turn up from the first jump (%d of 800 at jump 1)" % binaries_at_one)
	_check(first_ok, "and the first system of a world is always a normal one")


# --- Stars ---------------------------------------------------------------------

func _test_stars() -> void:
	print("Stars")
	var tuning := SystemTuning.new()
	var binary := Kit.flat_template(0.0, 0.5, 0)
	for _index in 2:
		var companion := Kit.star(0.3, 0.1)
		companion.random_color = true
		binary.stars.append(companion)
	var first := StarGenerator.generate(555, binary, 0.5, 0.0, tuning)
	var again := StarGenerator.generate(555, binary, 0.5, 0.0, tuning)
	var same := first.stars.size() == again.stars.size() and is_equal_approx(first.heat, again.heat) and is_equal_approx(first.light_energy, again.light_energy)
	for index in mini(first.stars.size(), again.stars.size()):
		same = same and first.stars[index].direction == again.stars[index].direction and is_equal_approx(first.stars[index].angular_radius, again.stars[index].angular_radius) and first.stars[index].color == again.stars[index].color
	_check(same, "the same template and seed give the same stars")
	var differs := 0
	for system_seed in range(100, 140):
		if StarGenerator.generate(system_seed, binary, 0.5, 0.0, tuning).stars[0].direction != first.stars[0].direction:
			differs += 1
	_check(differs == 40, "and another seed gives other ones")

	# A star for every entry in the template.
	var skipping := Kit.flat_template(0.0, 0.5, 0)
	skipping.stars.append(null)
	skipping.stars.append(Kit.star(0.4))
	_check(StarGenerator.generate(1, skipping, 0.5, 0.0, tuning).stars.size() == 1, "one star for every entry of the template (an empty entry is skipped)")
	_check(StarGenerator.generate(1, Kit.flat_template(0.0, 0.5, 0), 0.5, 0.0, tuning).stars.is_empty(), "and none for a template with none")

	# Distance and size.
	_check(is_equal_approx(StarGenerator.get_radius_for_distance(0.0), StarGenerator.MAXIMUM_RADIUS) and is_equal_approx(StarGenerator.get_radius_for_distance(1.0), StarGenerator.MINIMUM_RADIUS), "a distance of 0 is the biggest a star looks (%.0f degrees) and 1 the smallest (%.1f)" % [rad_to_deg(StarGenerator.MAXIMUM_RADIUS), rad_to_deg(StarGenerator.MINIMUM_RADIUS)])
	var shrinks := true
	var inverts := true
	var last_radius := 10.0
	for step in 21:
		var distance := step / 20.0
		var radius := StarGenerator.get_radius_for_distance(distance)
		shrinks = shrinks and radius < last_radius
		last_radius = radius
		inverts = inverts and absf(StarGenerator.get_distance_for_radius(radius) - distance) < 0.0001
	_check(shrinks and inverts, "the farther away, the smaller it looks, and the distance can be read back from the size")
	var sun_radius := rad_to_deg(StarGenerator.get_radius_for_distance(0.42))
	_check(sun_radius > 5.0 and sun_radius < 7.0, "a distance of 0.42 is a sun-like star, about six degrees (%.1f)" % sun_radius)

	# The temperature pulls stars in and pushes them out.
	var template := Kit.flat_template(0.0, 0.5, 0)
	template.stars.append(Kit.star(0.5, 0.2))
	var bounded := true
	var cold_sum := 0.0
	var hot_sum := 0.0
	var steady := true
	for system_seed in 300:
		var cold_star := StarGenerator.generate(system_seed, template, 0.0, -20.0, tuning).stars[0]
		var hot_star := StarGenerator.generate(system_seed, template, 1.0, 20.0, tuning).stars[0]
		var cold_edge := 0.5 + 0.2 * (1.0 - 2.0 * StarGenerator.ROLL_DRIFT)
		var hot_edge := 0.5 - 0.2 * (1.0 - 2.0 * StarGenerator.ROLL_DRIFT)
		bounded = bounded and cold_star.distance >= cold_edge - 0.0001 and cold_star.distance <= 0.7001 and hot_star.distance <= hot_edge + 0.0001 and hot_star.distance >= 0.2999
		bounded = bounded and is_equal_approx(cold_star.angular_radius, StarGenerator.get_radius_for_distance(cold_star.distance))
		cold_sum += cold_star.angular_radius
		hot_sum += hot_star.angular_radius
		var fixed := StarGenerator.generate(system_seed, Kit.flat_template(0.0, 0.5, 1), system_seed / 300.0, 0.0, tuning).stars[0]
		steady = steady and is_equal_approx(fixed.distance, 0.42)
	_check(bounded, "a star's distance stays within its variation of the template's, a little less at the ends")
	_check(hot_sum > cold_sum * 1.8, "the hotter end of the range pulls a star closer, so it looks bigger (%.1f against %.1f degrees on average)" % [rad_to_deg(hot_sum / 300.0), rad_to_deg(cold_sum / 300.0)])
	_check(steady, "and a star with no variation is always exactly where the template put it")

	# Colors.
	var fixed_color := Kit.star(0.42, 0.0, Color(1.0, 0.36, 0.2))
	var exact := StarGenerator.generate(3, _template_of(fixed_color), 0.5, 0.0, tuning).stars[0]
	_check(exact.color.is_equal_approx(Color(1.0, 0.36, 0.2)) and is_equal_approx(exact.brightness, 1.0), "a color with no variation is exactly the template's")
	var varied_star := Star.new()
	varied_star.color = Color(1.0, 0.36, 0.2)
	varied_star.color_variation = 1.0
	var moved := 0
	var hue_ok := true
	var value_ok := true
	for system_seed in 300:
		var star := StarGenerator.generate(system_seed, _template_of(varied_star), 0.5, 0.0, tuning).stars[0]
		var hue_gap := absf(star.color.h - varied_star.color.h)
		hue_gap = minf(hue_gap, 1.0 - hue_gap)
		hue_ok = hue_ok and hue_gap <= StarGenerator.HUE_VARIATION + 0.001
		value_ok = value_ok and star.color.v >= varied_star.color.v * (1.0 - StarGenerator.VALUE_VARIATION) - 0.001
		if not star.color.is_equal_approx(varied_star.color):
			moved += 1
	_check(moved > 280 and hue_ok and value_ok, "a color with variation moves a little, never past what the variation allows (%d of 300 moved)" % moved)
	var natural := Star.new()
	natural.random_color = true
	var kelvins := {}
	var natural_ok := true
	var palest := 0.0
	for system_seed in 300:
		var star := StarGenerator.generate(system_seed, _template_of(natural), 0.5, 0.0, tuning).stars[0]
		kelvins[roundi(star.kelvin / 50.0)] = true
		natural_ok = natural_ok and star.kelvin >= StarGenerator.COOLEST_KELVIN and star.kelvin <= StarGenerator.HOTTEST_KELVIN and star.color.is_equal_approx(StarGenerator.color_for_kelvin(star.kelvin))
		palest = maxf(palest, star.color.s)
	_check(natural_ok and kelvins.size() > 40, "a random color is a natural one, different for every system (%d different out of 300)" % kelvins.size())
	_check(palest < 0.45, "and never strongly colored: the most saturated is %.2f" % palest)
	var red := StarGenerator.color_for_kelvin(3500.0)
	var white := StarGenerator.color_for_kelvin(5800.0)
	var blue := StarGenerator.color_for_kelvin(9500.0)
	_check(red.r > red.b + 0.1 and blue.b > blue.r + 0.05, "cool stars are warm colored and hot stars are blue (%s, %s)" % [red.to_html(false), blue.to_html(false)])
	_check(white.r > 0.9 and white.g > 0.9 and white.b > 0.85, "and a sun-like star is nearly white (%s)" % white.to_html(false))

	# Several stars.
	var crowd := Kit.flat_template(0.0, 0.5, 0)
	for _index in 3:
		var star := Kit.star(0.3, 0.1)
		star.random_color = true
		crowd.stars.append(star)
	var unit := true
	var apart := true
	var shares_add_up := true
	var heat_matches := true
	var bounded_sizes := true
	for system_seed in 400:
		var count := 1 + system_seed % 3
		var many := Kit.flat_template(0.0, 0.5, 0)
		for index in count:
			many.stars.append(crowd.stars[index])
		var lit := StarGenerator.generate(system_seed * 7919, many, (system_seed % 11) / 10.0, 0.0, tuning)
		var energy := 0.0
		var heat := 0.0
		for index in lit.stars.size():
			var star := lit.stars[index]
			unit = unit and absf(star.direction.length() - 1.0) < 0.0001
			bounded_sizes = bounded_sizes and star.angular_radius >= StarGenerator.MINIMUM_RADIUS - 0.00001 and star.angular_radius <= StarGenerator.MAXIMUM_RADIUS + 0.00001
			energy += star.light_energy
			heat += star.heat
			heat_matches = heat_matches and absf(star.heat - pow(star.angular_radius / StarGenerator.REFERENCE_RADIUS, 2.0) * star.brightness) < 0.0001
			for other in range(index):
				if star.direction.angle_to(lit.stars[other].direction) < star.angular_radius + lit.stars[other].angular_radius:
					apart = false
		shares_add_up = shares_add_up and absf(energy - lit.light_energy) < 0.0001
		heat_matches = heat_matches and absf(heat - lit.heat) < 0.0001
	_check(unit and bounded_sizes, "each star is a direction, no smaller than %.1f degrees and no bigger than %.0f" % [rad_to_deg(StarGenerator.MINIMUM_RADIUS), rad_to_deg(StarGenerator.MAXIMUM_RADIUS)])
	_check(apart, "the discs of the stars of a system never touch")
	_check(heat_matches, "a star's share is how big it looks, squared, times how bright its surface is")
	_check(shares_add_up, "and the light each star gives adds up to the system's")

	# Light.
	_check(is_equal_approx(StarGenerator.get_light_energy(0.0, tuning), tuning.temperate_light), "a comfortable system has the temperate light")
	_check(is_equal_approx(StarGenerator.get_light_energy(100.0, tuning), tuning.temperate_light * pow(2.0, StarGenerator.LIGHT_PER_DOUBLING)) and is_equal_approx(StarGenerator.get_light_energy(-100.0, tuning), tuning.temperate_light / pow(2.0, StarGenerator.LIGHT_PER_DOUBLING)), "a scorching one has more than twice that and a frozen one less than half")
	var brightens := true
	var last_light := 0.0
	for step in range(-120, 121, 10):
		var light := StarGenerator.get_light_energy(float(step), tuning)
		brightens = brightens and light > last_light
		last_light = light
	_check(brightens, "the hotter the system, the brighter the light")
	_check(is_equal_approx(StarGenerator.get_light_energy(900.0, tuning), StarGenerator.get_light_energy(120.0, tuning)) and is_equal_approx(StarGenerator.get_light_energy(-900.0, tuning), StarGenerator.get_light_energy(-120.0, tuning)), "until the ends of the scale, where it stays")
	var hot_system := StarSystem.create(4, 3, tuning, Vector3.ZERO, Kit.flat_template(90.0))
	var cold_system := StarSystem.create(4, 3, tuning, Vector3.ZERO, Kit.flat_template(-90.0))
	_check(is_equal_approx(hot_system.light_energy, StarGenerator.get_light_energy(90.0, tuning)) and hot_system.light_energy > cold_system.light_energy * 3.0, "a system is lit by its temperature: %.2f scorching, %.2f frozen" % [hot_system.light_energy, cold_system.light_energy])
	_check(StarSystem.create(9, 0, tuning).stars.size() == 1 and absf(StarSystem.create(9, 0, tuning).light_energy - tuning.temperate_light) < tuning.temperate_light * 0.4, "while the first system is lit about as much as the old sun was (%.2f against %.2f)" % [StarSystem.create(9, 0, tuning).light_energy, tuning.temperate_light])


func _template_of(star: Star) -> SystemTemplate:
	var template := Kit.flat_template(0.0, 0.5, 0)
	template.stars.append(star)
	return template


# --- The sphere models start from --------------------------------------------

func _test_icosphere() -> void:
	print("The starting sphere")
	var expected_vertices := [12, 42, 162, 642, 2562]
	for detail in 5:
		var base := AsteroidShapes.get_base(detail)
		var vertices: PackedVector3Array = base["vertices"]
		var triangles: PackedInt32Array = base["triangles"]
		_check(vertices.size() == expected_vertices[detail] and triangles.size() == 3 * 20 * int(pow(4, detail)), "detail %d has %d corners and %d triangles" % [detail, vertices.size(), triangles.size() / 3.0])
	var base := AsteroidShapes.get_base(3)
	var vertices: PackedVector3Array = base["vertices"]
	var triangles: PackedInt32Array = base["triangles"]
	var unit := true
	for vertex in vertices:
		if absf(vertex.length() - 1.0) > 0.0001:
			unit = false
	_check(unit, "every corner is a meter from the middle")
	var outward := 0
	var uses := {}
	for corner in range(0, triangles.size(), 3):
		var a := vertices[triangles[corner]]
		var b := vertices[triangles[corner + 1]]
		var c := vertices[triangles[corner + 2]]
		if (b - a).cross(c - a).dot(a + b + c) > 0.0:
			outward += 1
		for index in 3:
			uses[triangles[corner + index]] = true
	_check(outward * 3 == triangles.size(), "every triangle is wound counter-clockwise seen from outside")
	_check(uses.size() == vertices.size(), "and every corner is used (corners are shared between triangles)")


# --- Asteroid kinds: when they turn up -------------------------------------------

func _test_asteroid_weights() -> void:
	print("When a kind of asteroid turns up")
	var none: Array[String] = []
	var kind := Kit.kind("Test", -50.0, 0.0, 30.0, 2.0)
	_check(kind.get_weight(-50.0, none, 0) == 0.0 and kind.get_weight(30.0, none, 0) == 0.0 and kind.get_weight(-80.0, none, 0) == 0.0 and kind.get_weight(60.0, none, 0) == 0.0, "never at or beyond the ends of its temperature range")
	_check(is_equal_approx(kind.get_weight(0.0, none, 0), 2.0), "its full weight at its peak")
	var rises := true
	var falls := true
	var last := 0.0
	for step in range(-49, 1):
		var weight := kind.get_weight(float(step), none, 0)
		rises = rises and weight >= last - 0.00001 and weight > 0.0
		last = weight
	for step in range(0, 30):
		var weight := kind.get_weight(float(step), none, 0)
		falls = falls and weight <= last + 0.00001 and weight > 0.0
		last = weight
	_check(rises and falls, "rarer on either side of the peak, but never nothing inside the range")
	_check(kind.get_weight(-25.0, none, 0) < 2.0 and kind.get_weight(-25.0, none, 0) > 0.5 and kind.get_weight(-45.0, none, 0) < 0.2, "and fading out toward the ends")
	var peak_outside := Kit.kind("Outside", -50.0, 100.0, 30.0)
	_check(peak_outside.get_weight(29.0, none, 0) > 0.9, "a peak outside the range counts as the nearest end of it")
	var backwards := Kit.kind("Backwards", 30.0, 0.0, -50.0, 2.0)
	_check(is_equal_approx(backwards.get_weight(0.0, none, 0), 2.0) and backwards.get_weight(40.0, none, 0) == 0.0, "a range written the wrong way round still works")
	var late := Kit.kind("Late", -50.0, 0.0, 30.0)
	late.min_jump = 5
	_check(late.get_weight(0.0, none, 4) == 0.0 and late.get_weight(0.0, none, 5) > 0.0, "a kind never turns up before its jump")
	var weightless := Kit.kind("None", -50.0, 0.0, 30.0, 0.0)
	_check(weightless.get_weight(0.0, none, 0) == 0.0, "and one with no weight never does")

	var needs := Kit.kind("Needs", -50.0, 0.0, 30.0)
	needs.required_tags.append("crystalline")
	needs.required_tags.append("dark")
	var both: Array[String] = ["dark", "crystalline", "hot"]
	var one: Array[String] = ["crystalline"]
	_check(needs.get_weight(0.0, none, 0) == 0.0 and needs.get_weight(0.0, one, 0) == 0.0 and needs.get_weight(0.0, both, 0) > 0.0, "a kind that needs tags only turns up in systems that have all of them")
	var refuses := Kit.kind("Refuses", -50.0, 0.0, 30.0)
	refuses.forbidden_tags.append("binary")
	var binary_tags: Array[String] = ["binary"]
	_check(refuses.get_weight(0.0, none, 0) > 0.0 and refuses.get_weight(0.0, binary_tags, 0) == 0.0, "and one that refuses a tag never turns up where it is")
	var favours := Kit.kind("Favours", -50.0, 0.0, 30.0)
	favours.tag_weights["crystalline"] = 3.0
	favours.tag_weights["dark"] = 0.5
	_check(is_equal_approx(favours.get_weight(0.0, one, 0), 3.0) and is_equal_approx(favours.get_weight(0.0, both, 0), 1.5) and is_equal_approx(favours.get_weight(0.0, none, 0), 1.0), "a tag can make a kind more or less common: its weight is multiplied for each tag the system has")
	favours.tag_weights["dark"] = 0.0
	_check(favours.get_weight(0.0, both, 0) == 0.0, "and a weight of nothing keeps it out")


# --- Asteroid kinds: the mix ---------------------------------------------------------

func _test_asteroid_mix() -> void:
	print("Mixing the kinds")
	var none: Array[String] = []
	var a := Kit.kind("A", -50.0, 0.0, 50.0, 1.0)
	var b := Kit.kind("B", -50.0, 0.0, 50.0, 1.0)
	var c := Kit.kind("C", -50.0, 0.0, 50.0, 2.0)
	var far := Kit.kind("Far", 80.0, 100.0, 120.0)
	var pool: Array[Asteroid] = [a, b, c, far]
	var mix := AsteroidMix.make(0.0, none, 0, pool)
	_check(mix.get_count() == 3 and mix.get_share(far) == 0.0 and is_equal_approx(mix.get_share(a), 0.25) and is_equal_approx(mix.get_share(c), 0.5), "the mix holds the kinds that fit, in proportion to their weights")
	var total := 0.0
	for share in mix.shares:
		total += share
	_check(is_equal_approx(total, 1.0), "which add up to one")
	var rare := Kit.kind("Rare", -50.0, 0.0, 50.0, 0.0001)
	var heavy := Kit.kind("Heavy", -50.0, 0.0, 50.0, 1000.0)
	var rare_pool: Array[Asteroid] = [rare, heavy]
	var trimmed := AsteroidMix.make(0.0, none, 0, rare_pool)
	_check(trimmed.get_count() == 1 and trimmed.asteroids[0] == heavy and is_equal_approx(trimmed.shares[0], 1.0), "a kind with under %.0f%% of the system is left out, and the others share its asteroids" % (AsteroidMix.MINIMUM_SHARE * 100.0))
	var nothing := AsteroidMix.make(500.0, none, 0, pool)
	_check(nothing.get_count() == 1 and nothing.asteroids[0] != null and is_equal_approx(nothing.shares[0], 1.0), "and when no kind fits there is a plain rock, never nothing")
	var same := AsteroidMix.make(0.0, none, 0, pool)
	_check(same.asteroids == mix.asteroids and same.shares == mix.shares, "the same temperature, tags and jump make the same mix")
	var equal := AsteroidMix.of(pool)
	_check(equal.get_count() == 4 and is_equal_approx(equal.shares[0], 0.25), "a mix of chosen kinds is in equal parts, whatever their ranges")

	# Sharing the models out.
	var counts := mix.get_model_counts(10)
	var sum := 0
	var close := true
	var every := true
	for index in counts.size():
		sum += counts[index]
		every = every and counts[index] >= 1
		close = close and absf(counts[index] - mix.shares[index] * 10.0) <= 1.0
	_check(sum == 10 and every and close, "ten models are shared out in proportion to the shares, a kind never going without (%s)" % str(counts))
	var kinds := mix.allocate(10)
	var grouped := kinds.size() == 10
	for index in range(1, kinds.size()):
		grouped = grouped and kinds[index] >= kinds[index - 1]
	_check(grouped, "every model has a kind, the models of one kind together")
	var weights := mix.get_model_weights(10)
	var weight_sum := 0.0
	var per_kind := PackedFloat32Array([0.0, 0.0, 0.0])
	for index in weights.size():
		weight_sum += weights[index]
		per_kind[kinds[index]] += weights[index]
	_check(is_equal_approx(weight_sum, 1.0) and is_equal_approx(per_kind[0], mix.shares[0]) and is_equal_approx(per_kind[2], mix.shares[2]), "the chance of each model adds up to one, and to each kind's share between its models")
	var crowded := AsteroidMix.of(pool)
	var few := crowded.get_model_counts(2)
	var few_weights := crowded.get_model_weights(2)
	var few_sum := 0.0
	for weight in few_weights:
		few_sum += weight
	_check(few.size() == 4 and few[0] + few[1] + few[2] + few[3] == 2 and few_weights.size() == 2 and is_equal_approx(few_sum, 1.0), "with more kinds than models, the biggest shares get one each and the chances still add up (%s)" % str(few))
	_check(mix.get_model_counts(1)[2] == 1 and mix.get_model_weights(1).size() == 1, "and a single model is the biggest kind")
	var rng := SpaceRandom.new(5)
	var picked := {}
	for _i in 4000:
		var kind := mix.pick(rng)
		picked[kind] = int(picked.get(kind, 0)) + 1
	_check(absf(int(picked[c]) / 4000.0 - 0.5) < 0.04 and absf(int(picked[a]) / 4000.0 - 0.25) < 0.04, "picking a kind follows the shares")


## The kinds the game ships with, and the mixes the three example systems were asked to have.
func _test_shipped_asteroids() -> void:
	print("The game's asteroids")
	var kinds := Kit.registry_kinds()
	var names := ["Normal", "Metallic", "Warm", "Hot", "Molten", "Cool", "Cold", "Frozen", "Crystal"]
	var missing: Array[String] = []
	for kind_name in names:
		if not kinds.has(kind_name):
			missing.append(kind_name)
	_check(missing.is_empty(), "Normal, Metallic, Warm, Hot, Molten, Cool, Cold, Frozen and Crystal are registered (missing: %s)" % str(missing))
	if not missing.is_empty():
		return
	var sorted := true
	var paths: Array[String] = []
	for asteroid in AsteroidRegistry.get_asteroids():
		paths.append(asteroid.resource_path)
	for index in range(1, paths.size()):
		sorted = sorted and paths[index - 1] < paths[index]
	_check(sorted, "found in the folder in a fixed order, sorted by path")
	var sane := true
	for kind_name in names:
		var kind: Asteroid = kinds[kind_name]
		sane = sane and kind.temperature_min < kind.temperature_peak and kind.temperature_peak < kind.temperature_max and kind.weight > 0.0
	_check(sane, "each has a range with its peak inside, and some weight")
	# Colder kinds turn up at colder temperatures.
	var order := ["Frozen", "Cold", "Cool", "Normal", "Warm", "Hot", "Molten"]
	var ordered := true
	for index in range(1, order.size()):
		ordered = ordered and (kinds[order[index - 1]] as Asteroid).temperature_peak < (kinds[order[index]] as Asteroid).temperature_peak
	_check(ordered, "Frozen, Cold, Cool, Normal, Warm, Hot and Molten peak in that order, coldest to hottest")

	var none: Array[String] = []
	# Temperate: mostly normal, with a small chance of warm and cool.
	var temperate_ok := true
	for temperature in [-15.0, -5.0, 0.0, 5.0, 15.0]:
		var mix := AsteroidMix.make(temperature, none, 20)
		temperate_ok = temperate_ok and mix.get_share(kinds["Normal"]) >= mix.get_share(kinds["Warm"]) and mix.get_share(kinds["Normal"]) >= mix.get_share(kinds["Cool"]) and mix.get_share(kinds["Frozen"]) == 0.0 and mix.get_share(kinds["Molten"]) == 0.0
	var comfortable := AsteroidMix.make(0.0, none, 20)
	_check(temperate_ok, "in a temperate system the commonest kind is Normal, with no Frozen or Molten at all")
	_check(comfortable.get_share(kinds["Normal"]) > 0.6 and comfortable.get_share(kinds["Warm"]) > 0.03 and comfortable.get_share(kinds["Warm"]) < 0.2 and comfortable.get_share(kinds["Cool"]) > 0.03 and comfortable.get_share(kinds["Cool"]) < 0.2, "at 0, mostly Normal with a small chance of Warm and Cool (%.0f%%, %.0f%%, %.0f%%)" % [comfortable.get_share(kinds["Normal"]) * 100.0, comfortable.get_share(kinds["Warm"]) * 100.0, comfortable.get_share(kinds["Cool"]) * 100.0])
	# Frozen: mostly frozen and cold, and some cool.
	var frozen := AsteroidMix.make(-90.0, none, 20)
	_check(frozen.get_share(kinds["Frozen"]) > frozen.get_share(kinds["Cold"]) and frozen.get_share(kinds["Frozen"]) > 0.45 and frozen.get_share(kinds["Cold"]) > 0.2 and frozen.get_share(kinds["Cool"]) > 0.03 and frozen.get_share(kinds["Cool"]) < 0.25 and frozen.get_share(kinds["Normal"]) == 0.0 and frozen.get_share(kinds["Hot"]) == 0.0, "in a frozen system, mostly Frozen, then Cold, and some Cool (%.0f%%, %.0f%%, %.0f%%)" % [frozen.get_share(kinds["Frozen"]) * 100.0, frozen.get_share(kinds["Cold"]) * 100.0, frozen.get_share(kinds["Cool"]) * 100.0])
	# Hot: mostly hot, with some molten and warm.
	var hot := AsteroidMix.make(65.0, none, 20)
	_check(hot.get_share(kinds["Hot"]) > 0.5 and hot.get_share(kinds["Molten"]) > 0.08 and hot.get_share(kinds["Warm"]) > 0.08 and hot.get_share(kinds["Frozen"]) == 0.0 and hot.get_share(kinds["Cold"]) == 0.0 and hot.get_share(kinds["Cool"]) == 0.0, "in a hot system, mostly Hot, with some Molten and Warm (%.0f%%, %.0f%%, %.0f%%)" % [hot.get_share(kinds["Hot"]) * 100.0, hot.get_share(kinds["Molten"]) * 100.0, hot.get_share(kinds["Warm"]) * 100.0])
	var scorching := AsteroidMix.make(105.0, none, 20)
	_check(scorching.get_share(kinds["Molten"]) > scorching.get_share(kinds["Hot"]) and scorching.get_share(kinds["Molten"]) > 0.5, "in a scorching one, mostly Molten (%.0f%%)" % (scorching.get_share(kinds["Molten"]) * 100.0))
	# The trend as it gets colder and hotter.
	var frozen_falls := true
	var molten_rises := true
	for step in range(-12, 11):
		var colder := AsteroidMix.make(step * 10.0, none, 20)
		var warmer := AsteroidMix.make((step + 1) * 10.0, none, 20)
		frozen_falls = frozen_falls and colder.get_share(kinds["Frozen"]) >= warmer.get_share(kinds["Frozen"]) - 0.0001
		if step >= 4:
			molten_rises = molten_rises and colder.get_share(kinds["Molten"]) <= warmer.get_share(kinds["Molten"]) + 0.0001
	_check(frozen_falls and molten_rises, "the warmer the system, the fewer Frozen and the more Molten")
	# The crystal kind needs its tag, and heat.
	var crystalline: Array[String] = ["crystalline"]
	var crystal_never := true
	for step in range(-12, 13):
		crystal_never = crystal_never and AsteroidMix.make(step * 10.0, none, 40).get_share(kinds["Crystal"]) == 0.0
	_check(crystal_never, "Crystal asteroids turn up nowhere without the crystalline tag")
	_check(AsteroidMix.make(70.0, crystalline, 40).get_share(kinds["Crystal"]) > 0.3 and AsteroidMix.make(-50.0, crystalline, 40).get_share(kinds["Crystal"]) == 0.0 and AsteroidMix.make(0.0, crystalline, 40).get_share(kinds["Crystal"]) == 0.0, "and with it, only in hot systems (%.0f%% at 70)" % (AsteroidMix.make(70.0, crystalline, 40).get_share(kinds["Crystal"]) * 100.0))
	# Every temperature has something.
	var always := true
	for step in range(-125, 126, 5):
		var mix := AsteroidMix.make(float(step), none, 0)
		always = always and mix.get_count() >= 1 and mix.get_share(mix.asteroids[0]) > 0.0
		var total := 0.0
		for share in mix.shares:
			total += share
		always = always and absf(total - 1.0) < 0.0001
	_check(always, "every temperature from -125 to 125 has asteroids, adding up to a whole")
	# And through a real system.
	var tuning := SystemTuning.new()
	var templates := Kit.registry_templates()
	var giant_system := StarSystem.create(3, 8, tuning, Vector3.ZERO, templates["Giant Star"])
	_check(giant_system.asteroid_mix != null and giant_system.asteroid_mix.get_share(kinds["Molten"]) > 0.5, "a giant star's asteroids are mostly molten (%.0f%%)" % (giant_system.asteroid_mix.get_share(kinds["Molten"]) * 100.0))
	var normal_system := StarSystem.create(3, 8, tuning, Vector3.ZERO, templates["Normal System"])
	_check(normal_system.asteroid_mix.get_share(kinds["Normal"]) > 0.4 and normal_system.asteroid_mix.get_share(kinds["Molten"]) == 0.0, "and a normal system's mostly normal (%.0f%%)" % (normal_system.asteroid_mix.get_share(kinds["Normal"]) * 100.0))
	var mixed_up := false
	for system_seed in 300:
		var system := StarSystem.create(system_seed * 7919 + 2, 10 + system_seed % 30, tuning)
		var hot_and_cold := system.asteroid_mix.get_share(kinds["Frozen"]) + system.asteroid_mix.get_share(kinds["Cold"]) > 0.0 and system.asteroid_mix.get_share(kinds["Hot"]) + system.asteroid_mix.get_share(kinds["Molten"]) > 0.0
		mixed_up = mixed_up or hot_and_cold
	_check(not mixed_up, "no system has cold asteroids and hot ones together")


# --- AsteroidShapes -------------------------------------------------------------

func _test_models() -> void:
	print("Asteroid models")
	var started := Time.get_ticks_usec()
	var shapes := AsteroidShapes.build(2024)
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print("  info built %d models in %.1f ms" % [shapes.models.size(), elapsed])
	_check(shapes.models.size() == AsteroidShapes.DEFAULT_MODEL_COUNT, "the usual number of models are built")
	# A headless run draws nothing, so a mesh cannot be read back there; the models keep their numbers.
	var sound := true
	var outward_share := 1.0
	var smallest_extent := 100.0
	var largest_extent := 0.0
	var faces_match := true
	var clockwise_share := 1.0
	for model in shapes.models:
		sound = sound and model.asteroid != null and model.mesh.get_surface_count() == 1 and model.mesh.surface_get_material(0) != null and model.decoration_count == 0
		var farthest := 0.0
		var nearest := 100.0
		var facing_out := 0
		for index in model.positions.size():
			farthest = maxf(farthest, model.positions[index].length())
			nearest = minf(nearest, model.positions[index].length())
			if model.normals[index].dot(model.positions[index]) > 0.0:
				facing_out += 1
		smallest_extent = minf(smallest_extent, farthest)
		largest_extent = maxf(largest_extent, farthest)
		outward_share = minf(outward_share, float(facing_out) / model.positions.size())
		sound = sound and nearest > 0.25 and absf(model.normals[0].length() - 1.0) < 0.001
		var faces := model.collision.get_faces()
		faces_match = faces_match and faces.size() == 1280 * 3
		# Godot draws clockwise triangles, so cross() of a drawn triangle points inward.
		var drawn_clockwise := 0
		for corner in range(0, 1280 * 3, 3):
			if (faces[corner + 1] - faces[corner]).cross(faces[corner + 2] - faces[corner]).dot(faces[corner] + faces[corner + 1] + faces[corner + 2]) < 0.0:
				drawn_clockwise += 1
		clockwise_share = minf(clockwise_share, float(drawn_clockwise) / 1280.0)
	_check(sound, "each model is a kind of asteroid with one surface and a material, and nothing collapsed to a point")
	_check(smallest_extent > 0.9999 and largest_extent < 1.0001, "a model reaches exactly one meter from its middle (%.5f to %.5f)" % [smallest_extent, largest_extent])
	_check(outward_share > 0.97, "the normals point outward (worst model %.1f%%)" % (outward_share * 100.0))
	_check(clockwise_share > 0.97, "the triangles are wound the way Godot draws them (worst model %.1f%%)" % (clockwise_share * 100.0))
	_check(faces_match, "and the collision shape has the same 1280 triangles")

	var again := AsteroidShapes.build(2024)
	var identical := true
	for index in shapes.models.size():
		identical = identical and shapes.models[index].positions == again.models[index].positions \
				and shapes.models[index].normals == again.models[index].normals \
				and shapes.models[index].asteroid == again.models[index].asteroid \
				and shapes.models[index].collision.get_faces() == again.models[index].collision.get_faces()
	_check(identical, "the same seed builds the same models")
	var other := AsteroidShapes.build(2025)
	var differs := 0
	for index in shapes.models.size():
		if shapes.models[index].positions != other.models[index].positions:
			differs += 1
	_check(differs == shapes.models.size(), "and another seed builds other models (%d of %d differ)" % [differs, shapes.models.size()])
	var distinct := {}
	for model in shapes.models:
		var low := Vector3.ONE * 10.0
		var high := Vector3.ONE * -10.0
		for point in model.positions:
			low = low.min(point)
			high = high.max(point)
		distinct[(high - low).snappedf(0.001)] = true
	_check(distinct.size() >= 8, "the models are not all the same size and shape (%d different boxes)" % distinct.size())

	# Which kind each model is.
	var kinds := Kit.registry_kinds()
	var none: Array[String] = []
	var temperate := AsteroidMix.make(0.0, none, 20)
	var counts := temperate.get_model_counts(10)
	var shared_out := AsteroidShapes.build(77, 10, 1, temperate)
	var by_kind := {}
	for model in shared_out.models:
		by_kind[model.asteroid] = int(by_kind.get(model.asteroid, 0)) + 1
	var matches := true
	for index in temperate.asteroids.size():
		matches = matches and int(by_kind.get(temperate.asteroids[index], 0)) == counts[index]
	_check(matches, "the models are shared out between the kinds as the mix says (%s)" % str(counts))
	_check(shared_out.get_material(kinds["Normal"]) != null and shared_out.get_materials(kinds["Normal"]).size() == 1, "every kind in the mix has its material")
	var limited := AsteroidShapes.build(3, 6, 1, AsteroidMix.of([kinds["Frozen"], kinds["Molten"]]))
	var only_two := true
	for model in limited.models:
		only_two = only_two and (model.asteroid == kinds["Frozen"] or model.asteroid == kinds["Molten"])
	_check(only_two and limited.models.size() == 6, "and only the kinds in the mix are built")


func _test_decorations() -> void:
	print("Things that grow out of asteroids")
	var kinds := Kit.registry_kinds()
	var base_faces := 1280 * 3

	# The ice crystals of the game, built from their scene.
	var frozen: Asteroid = kinds["Frozen"]
	var decorator: AsteroidDecorator = frozen.decorators[0]
	var parts := decorator.get_parts()
	var parts_ok := parts.size() == 2
	for part in parts:
		parts_ok = parts_ok and part.material != null and part.vertices.size() >= 18 and part.vertices.size() % 3 == 0 and part.normals.size() == part.vertices.size() and part.uvs.size() == part.vertices.size()
	_check(decorator.scene != null and decorator.has_parts() and parts_ok, "the ice crystal scene is read as its two meshes, a column and a point, as plain triangles")
	_check(decorator.get_parts() == parts, "(and only read once)")
	var shapes := AsteroidShapes.build(77, 10, 3, AsteroidMix.of([frozen]))
	var crystals_everywhere := true
	var shaped := true
	var inside := true
	var pokes_out := true
	var faces_right := true
	var one_surface := true
	var total_crystals := 0
	for model in shapes.models:
		crystals_everywhere = crystals_everywhere and model.decoration_count >= decorator.clusters_min
		total_crystals += model.decoration_count
		shaped = shaped and model.decoration_vertices.size() == model.decoration_count * 18 * 3
		var body_reach := 0.0
		var decoration_reach := 0.0
		for point in model.positions:
			body_reach = maxf(body_reach, point.length())
		for point in model.decoration_vertices:
			decoration_reach = maxf(decoration_reach, point.length())
		inside = inside and decoration_reach <= 1.0001 and body_reach <= 1.0001 and maxf(body_reach, decoration_reach) > 0.9999
		pokes_out = pokes_out and decoration_reach > body_reach + 0.04
		faces_right = faces_right and model.collision.get_faces().size() == base_faces + model.decoration_count * 18 * 3
		one_surface = one_surface and model.mesh.get_surface_count() == 2 and model.mesh.surface_get_material(1) == parts[0].material
	_check(crystals_everywhere, "every frozen model has at least the fewest crystals the decorator asks for (%d in all)" % total_crystals)
	_check(shaped, "each crystal is 18 triangles")
	_check(inside, "the crystals are part of the model's size: nothing reaches past the meter, and something reaches exactly that far")
	_check(pokes_out, "and they poke out past the body of the rock")
	_check(faces_right, "the collision shape has the rock's 1280 triangles and the crystals' 18 each")
	_check(one_surface, "the crystals are a surface of their own, with the crystal scene's material")
	var again := AsteroidShapes.build(77, 10, 3, AsteroidMix.of([frozen]))
	var same := true
	for index in shapes.models.size():
		same = same and shapes.models[index].decoration_vertices == again.models[index].decoration_vertices and shapes.models[index].collision.get_faces() == again.models[index].collision.get_faces()
	_check(same, "the same system makes the same crystals")
	var other := AsteroidShapes.build(78, 10, 3, AsteroidMix.of([frozen]))
	_check(other.models[0].decoration_vertices != shapes.models[0].decoration_vertices, "and another system other ones")
	var purple: Asteroid = kinds["Crystal"]
	var purple_shapes := AsteroidShapes.build(77, 4, 2, AsteroidMix.of([purple]))
	var purple_ok := true
	for model in purple_shapes.models:
		purple_ok = purple_ok and model.decoration_count >= 5 and model.mesh.get_surface_count() == 2 and model.mesh.surface_get_material(1) != shapes.models[0].mesh.surface_get_material(1)
	_check(purple_ok, "the Crystal asteroid grows purple ones, with a material of their own")

	# Decorators made in code.
	var cones := Kit.kind("Cones", -50.0, 0.0, 50.0)
	cones.decorators.append(Kit.cone_decorator(8))
	var coned := AsteroidShapes.build(5, 4, 3, AsteroidMix.of([cones]))
	var cone_ok := true
	for model in coned.models:
		cone_ok = cone_ok and model.decoration_count == 8 and model.decoration_vertices.size() == 8 * 6 * 3 and model.collision.get_faces().size() == base_faces + 8 * 6 * 3 and model.mesh.get_surface_count() == 2
	_check(cone_ok, "a decorator made in code grows as many pieces as it says: 8 cones of 6 triangles each")
	var soft := Kit.kind("Soft", -50.0, 0.0, 50.0)
	soft.decorators.append(Kit.cone_decorator(8, false))
	var soft_shapes := AsteroidShapes.build(5, 4, 3, AsteroidMix.of([soft]))
	var passes_through := true
	for model in soft_shapes.models:
		passes_through = passes_through and model.decoration_count == 8 and model.collision.get_faces().size() == base_faces and model.mesh.get_surface_count() == 2
	_check(passes_through, "one that does not collide is in the mesh and not in the collision shape")
	var empty := Kit.kind("Empty", -50.0, 0.0, 50.0)
	empty.decorators.append(null)
	empty.decorators.append(AsteroidDecorator.new())
	var empty_scene := AsteroidDecorator.new()
	var nothing_in_it := Node3D.new()
	var nothing_scene := PackedScene.new()
	nothing_scene.pack(nothing_in_it)
	nothing_in_it.free()
	empty_scene.scene = nothing_scene
	empty.decorators.append(empty_scene)
	var bare := AsteroidShapes.build(5, 2, 2, AsteroidMix.of([empty]))
	var bare_ok := true
	for model in bare.models:
		bare_ok = bare_ok and model.decoration_count == 0 and model.mesh.get_surface_count() == 1
	_check(bare_ok, "an empty slot, a decorator with no scene and a scene with nothing in it are all ignored")
	var two := Kit.kind("Two", -50.0, 0.0, 50.0)
	two.decorators.append(Kit.cone_decorator(3))
	two.decorators.append(Kit.cone_decorator(4))
	var doubled := AsteroidShapes.build(5, 2, 2, AsteroidMix.of([two]))
	_check(doubled.models[0].decoration_count == 7, "two decorators grow both their pieces (%d)" % doubled.models[0].decoration_count)

	# Where they grow.
	var surface_ok := true
	var leans_ok := true
	for model in coned.models:
		# A cone is 0.3 tall and its base is 0.2 wide at most, so every corner is near the rock's skin or beyond it.
		for point in model.decoration_vertices:
			var nearest := 10.0
			for body_point in model.positions:
				nearest = minf(nearest, point.distance_to(body_point))
			surface_ok = surface_ok and nearest < 0.5
	_check(surface_ok, "the pieces grow from the surface of the rock")
	for model in coned.models:
		leans_ok = leans_ok and model.decoration_vertices.size() > 0
	_check(leans_ok, "(and every model has some)")


func _test_materials() -> void:
	print("Looks")
	var kinds := Kit.registry_kinds()
	var picked: Array[Asteroid] = [kinds["Normal"], kinds["Metallic"], kinds["Warm"], kinds["Cold"], kinds["Frozen"], kinds["Hot"], kinds["Molten"], kinds["Crystal"]]
	var shapes := AsteroidShapes.build(2024, 16, 1, AsteroidMix.of(picked))
	var base := load("res://Assets/Materials/Asteroid.tres") as StandardMaterial3D

	var rock := shapes.get_material(kinds["Normal"]) as StandardMaterial3D
	_check(base != null and rock.albedo_texture == base.albedo_texture and rock.normal_texture == base.normal_texture and rock.normal_enabled, "Normal uses the Asteroid material's own textures")
	_check(rock.uv1_triplanar and rock.vertex_color_use_as_albedo and rock.cull_mode == BaseMaterial3D.CULL_BACK, "wrapped on from every side, since the models have no flat map, and only drawn from outside")
	_check(rock != base and base.cull_mode == BaseMaterial3D.CULL_DISABLED and not base.uv1_triplanar, "without changing the material file itself")
	var kind: Asteroid = kinds["Normal"]
	_check(absf(rock.albedo_color.r - kind.tint.r * AsteroidMaterials.TEXTURE_BOOST) < 0.001 and rock.roughness == kind.roughness, "its tint is brightened to make up for the dark texture, and its roughness is the kind's")
	var metal := shapes.get_material(kinds["Metallic"]) as StandardMaterial3D
	_check(metal.metallic > 0.3 and metal.albedo_texture == base.albedo_texture, "Metallic is the same rock, shiny")
	var warm := shapes.get_material(kinds["Warm"]) as StandardMaterial3D
	_check(warm.albedo_color.r > warm.albedo_color.b * 1.3 and warm.albedo_texture == base.albedo_texture, "Warm is the same rock turned orange")
	var cold := shapes.get_material(kinds["Cold"]) as StandardMaterial3D
	_check(cold.albedo_color.b > cold.albedo_color.r * 1.3 and cold.emission_enabled, "Cold is blue, with a faint glow")
	var ice := shapes.get_material(kinds["Frozen"]) as StandardMaterial3D
	_check(ice.albedo_texture == null and ice.roughness < 0.3 and ice.emission_enabled and ice.emission_texture == null and ice.normal_scale < base.normal_scale, "Frozen is glossy and pale, with a faint glow of its own and less of the rock's bumps")
	var dark := shapes.get_material(kinds["Crystal"]) as StandardMaterial3D
	_check(dark.albedo_color.r < 0.5 and dark.albedo_color.g < 0.5 and dark.roughness < 0.5, "and the Crystal asteroid is blackish and shiny")

	var hot_materials := shapes.get_materials(kinds["Hot"])
	var molten_materials := shapes.get_materials(kinds["Molten"])
	_check(hot_materials.size() == AsteroidMaterials.CRACK_VARIANTS and molten_materials.size() == AsteroidMaterials.CRACK_VARIANTS, "a cracked kind has several strengths of glow")
	var distinct := {}
	var crack_ok := true
	for material in hot_materials:
		distinct[material.emission_energy_multiplier] = true
		crack_ok = crack_ok and material.emission_enabled and material.emission_texture != null and material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY
	_check(crack_ok and distinct.size() == hot_materials.size(), "each with an emission picture that is multiplied in, and a strength of its own")
	var hot_texture: Texture2D = hot_materials[0].emission_texture
	var molten_texture: Texture2D = molten_materials[0].emission_texture
	_check(hot_texture != molten_texture and hot_texture == AsteroidMaterials.get_crack_texture((kinds["Hot"] as Asteroid).crack_width, (kinds["Hot"] as Asteroid).crack_halo), "each kind's crack picture is made once for its width and halo, and kept")
	_check(hot_texture.get_width() == 256 and hot_texture.get_image().has_mipmaps(), "the cracks are a picture of lines, with mipmaps so they do not sparkle far away")
	var crack_image: Image = hot_texture.get_image()
	var brightest := 0.0
	var linear_average := 0.0
	for y in 256:
		for x in 256:
			var level: float = crack_image.get_pixel(x, y).r
			brightest = maxf(brightest, level)
			linear_average += pow(level, 2.2)
	linear_average /= 65536.0
	var molten_image: Image = molten_texture.get_image()
	var molten_average := 0.0
	for y in 256:
		for x in 256:
			molten_average += pow(molten_image.get_pixel(x, y).r, 2.2)
	molten_average /= 65536.0
	# (The picture is read as a color, so the brightness it gives is each value raised to 2.2.)
	_check(brightest > 0.85 and linear_average < 0.3 and linear_average > 0.04, "bright cracks on a dim picture: the brightest spot is nearly full strength (%.2f) and it averages %.2f once read as light" % [brightest, linear_average])
	_check(molten_average > linear_average * 1.4, "more of a molten rock glows than of a hot one (%.2f against %.2f)" % [molten_average, linear_average])
	var hot_glow := 0.0
	var molten_glow := 0.0
	for material in hot_materials:
		hot_glow = maxf(hot_glow, material.emission_energy_multiplier)
	for material in molten_materials:
		molten_glow = maxf(molten_glow, material.emission_energy_multiplier)
	_check(molten_glow > hot_glow * 1.5, "and glows brighter (%.2f against %.2f)" % [molten_glow, hot_glow])
	var hot_kind: Asteroid = kinds["Hot"]
	var before := hot_materials[0].emission_energy_multiplier
	var frozen_before := ice.emission_energy_multiplier
	shapes.tick(1.0)
	var middle := hot_materials[0].emission_energy_multiplier
	shapes.tick(3.0)
	var after := hot_materials[0].emission_energy_multiplier
	_check(not is_equal_approx(middle, after) and before > 0.0 and after <= hot_kind.crack_energy + 0.0001 and after >= hot_kind.crack_energy * 0.75 * (1.0 - 2.0 * hot_kind.crack_pulse) - 0.0001, "the glow breathes: it changes with the time, within the kind's strength (%.2f, %.2f)" % [middle, after])
	_check(is_equal_approx(ice.emission_energy_multiplier, frozen_before) and is_equal_approx(rock.emission_energy_multiplier, 1.0), "and nothing that has no cracks changes")
	_check(shapes.get_material(kinds["Normal"]) != AsteroidShapes.build(2024, 16, 1, AsteroidMix.of(picked)).get_material(kinds["Normal"]), "each system gets materials of its own")
	var surface_ok := true
	for model in shapes.models:
		var made := shapes.get_materials(model.asteroid)
		surface_ok = surface_ok and made.has(model.mesh.surface_get_material(0))
	_check(surface_ok, "and every model's body uses one of its kind's materials")

	var plain := Asteroid.new()
	plain.cracks = true
	plain.crack_energy = 0.0
	_check(not plain.has_cracks() and AsteroidMaterials.make(plain).size() == 1, "cracks with no brightness are no cracks")
	var own_base := Asteroid.new()
	own_base.base_material = StandardMaterial3D.new()
	own_base.base_material.albedo_color = Color.RED
	var own := AsteroidMaterials.make(own_base)[0]
	_check(own.albedo_texture == null and own.uv1_triplanar and own.vertex_color_use_as_albedo, "a kind can start from a material of its own, which gets the same treatment")


func _test_drops() -> void:
	print("Drops")
	var scrap := Item.new()
	scrap.id = &"scrap"
	var always := AsteroidDrop.new()
	always.item = scrap
	always.chance = 1.0
	always.min_amount = 2
	always.max_amount = 5
	var never := AsteroidDrop.new()
	never.item = scrap
	never.chance = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var amounts := {}
	for _i in 200:
		amounts[always.roll(rng)] = true
	_check(amounts.keys().min() == 2 and amounts.keys().max() == 5 and amounts.size() == 4, "a drop that always happens gives between its fewest and most (%s)" % str(amounts.keys()))
	_check(never.roll(rng) == 0 and AsteroidDrop.new().roll(rng) == 0, "one with no chance, or no item, gives nothing")
	var half := AsteroidDrop.new()
	half.item = scrap
	half.chance = 0.5
	var drops := 0
	for _i in 2000:
		if half.roll(rng) > 0:
			drops += 1
	_check(absf(drops / 2000.0 - 0.5) < 0.05, "and one with a chance happens that often (%.0f%%)" % (drops / 20.0))
	var kind := Kit.kind("Dropper", -50.0, 0.0, 50.0)
	kind.drops.append(always)
	kind.drops.append(never)
	kind.drops.append(null)
	var given := kind.roll_drops(rng)
	_check(given.size() == 1 and given[0]["item"] == scrap and given[0]["amount"] >= 2 and given[0]["amount"] <= 5, "a kind gives what its drops give, leaving out what did not happen")
	_check(Kit.kind("Bare", -50.0, 0.0, 50.0).roll_drops().is_empty(), "and nothing when it has none")


# --- ChunkGenerator -------------------------------------------------------------

func _test_chunks() -> void:
	print("Chunk contents")
	var tuning := SystemTuning.new()
	var system := StarSystem.create(4242, 3, tuning)
	var generator := ChunkGenerator.new(system)

	var identical := true
	for coord in [Vector3i(0, 0, 0), Vector3i(3, -2, 5), Vector3i(-7, 4, -1)]:
		var first := generator.generate(coord)
		var second := ChunkGenerator.new(system).generate(coord)
		identical = identical and first.size() == second.size()
		for index in mini(first.size(), second.size()):
			identical = identical and first[index].position == second[index].position and is_equal_approx(first[index].radius, second[index].radius) and first[index].model == second[index].model and first[index].basis == second[index].basis
	_check(identical, "a chunk made twice, even by another generator, has the same asteroids")

	var inside := true
	var apart := true
	var models_ok := true
	var counts: PackedInt32Array = []
	var empty := 0
	var crowded := 0
	var biggest := 0
	var all_radii_ok := true
	for x in range(-6, 6):
		for y in range(-6, 6):
			for z in range(-6, 6):
				var specs := generator.generate(Vector3i(x, y, z))
				counts.append(specs.size())
				biggest = maxi(biggest, specs.size())
				if specs.is_empty():
					empty += 1
				if specs.size() >= int(system.asteroid_density * 2.0):
					crowded += 1
				for index in specs.size():
					var spec := specs[index]
					var size := generator.chunk_size
					inside = inside and spec.position.x >= spec.radius - 0.001 and spec.position.x <= size - spec.radius + 0.001 \
							and spec.position.y >= spec.radius - 0.001 and spec.position.y <= size - spec.radius + 0.001 \
							and spec.position.z >= spec.radius - 0.001 and spec.position.z <= size - spec.radius + 0.001
					models_ok = models_ok and spec.model >= 0 and spec.model < generator.model_count
					all_radii_ok = all_radii_ok and spec.radius >= system.smallest_radius - 0.001 and spec.radius <= system.largest_radius + 0.001
					for other in range(index):
						if spec.position.distance_to(specs[other].position) < spec.radius + specs[other].radius + ChunkGenerator.GAP - 0.001:
							apart = false
	var total := 0
	for count in counts:
		total += count
	var mean := float(total) / counts.size()
	print("  info %d chunks: %.2f asteroids on average, %d empty, %d crowded, most in one %d" % [counts.size(), mean, empty, crowded, biggest])
	_check(inside, "every asteroid lies completely inside its own chunk")
	_check(apart, "no two asteroids in a chunk touch")
	_check(models_ok and all_radii_ok, "each uses a model that exists and a radius in range")
	_check(mean > system.asteroid_density * 0.4 and mean < system.asteroid_density * 2.0, "the average thickness is close to the system's (%.2f against %.2f)" % [mean, system.asteroid_density])
	_check(empty > counts.size() / 20.0, "there are voids with next to nothing in them (%d empty)" % empty)
	_check(crowded > counts.size() / 40.0, "and belts several times as thick as average (%d crowded)" % crowded)
	_check(biggest <= ChunkGenerator.MAX_ASTEROIDS, "no chunk is over the limit")

	# The kinds of asteroid come out in the shares of the mix.
	var kinds := Kit.registry_kinds()
	var temperate := StarSystem.create(4242, 3, tuning, Vector3.ZERO, Kit.flat_template(0.0, 0.8))
	var temperate_generator := ChunkGenerator.new(temperate)
	var model_kinds := temperate.asteroid_mix.allocate(temperate_generator.model_count)
	var tally := {}
	var asteroid_total := 0
	for x in range(-6, 6):
		for y in range(-6, 6):
			for z in range(-6, 6):
				for spec in temperate_generator.generate(Vector3i(x, y, z)):
					var kind := temperate.asteroid_mix.asteroids[model_kinds[spec.model]]
					tally[kind] = int(tally.get(kind, 0)) + 1
					asteroid_total += 1
	var shares_ok := asteroid_total > 600
	for kind in temperate.asteroid_mix.asteroids:
		var wanted := temperate.asteroid_mix.get_share(kind)
		var got := int(tally.get(kind, 0)) / float(maxi(asteroid_total, 1))
		shares_ok = shares_ok and absf(got - wanted) < 0.05
	_check(shares_ok, "the kinds of the asteroids in a system follow the mix: Normal %.0f%% against %.0f%% (%d asteroids)" % [int(tally.get(kinds["Normal"], 0)) * 100.0 / maxi(asteroid_total, 1), temperate.asteroid_mix.get_share(kinds["Normal"]) * 100.0, asteroid_total])

	var coord := generator.get_coord(Vector3(-0.1, 499.9, 1000.0))
	_check(coord == Vector3i(-1, 0, 2), "a point finds its chunk, negative coordinates included %s" % str(coord))
	_check(generator.get_origin(Vector3i(-1, 0, 2)) == Vector3(-500.0, 0.0, 1000.0), "and a chunk its corner")

	print("The arrival area")
	# Arrive in the middle of the thickest belt nearby, with a wide area kept clear, so there is plenty to carve out.
	var wide := SystemTuning.new()
	wide.arrival_clear_radius = 300.0
	var scout := ChunkGenerator.new(StarSystem.create(4242, 3, wide))
	var richest := Vector3i.ZERO
	var most := 0.0
	for x in range(-4, 5):
		for y in range(-4, 5):
			for z in range(-4, 5):
				var expected := scout.get_expected_count(Vector3i(x, y, z))
				if expected > most:
					most = expected
					richest = Vector3i(x, y, z)
	var arrival := scout.get_origin(richest) + Vector3.ONE * 250.0
	var near := StarSystem.create(4242, 3, wide, arrival)
	var far := StarSystem.create(4242, 3, wide, Vector3(1000000.0, 0.0, 0.0))
	var near_gen := ChunkGenerator.new(near)
	var far_gen := ChunkGenerator.new(far)
	var clear := true
	var nearby := 0
	var in_the_way := 0
	for x in range(-2, 3):
		for y in range(-2, 3):
			for z in range(-2, 3):
				var coord_here := richest + Vector3i(x, y, z)
				var origin_here := near_gen.get_origin(coord_here)
				for spec in near_gen.generate(coord_here):
					var distance := (origin_here + spec.position).distance_to(arrival)
					if distance < near.arrival_clear_radius + spec.radius - 0.001:
						clear = false
					elif distance < near.arrival_clear_radius + 400.0:
						nearby += 1
				for spec in far_gen.generate(coord_here):
					if (origin_here + spec.position).distance_to(arrival) < near.arrival_clear_radius + spec.radius:
						in_the_way += 1
	print("  info arriving in chunk %s (%.1f expected): %d asteroids would have been in the way, %d now stand just outside" % [str(richest), most, in_the_way, nearby])
	_check(clear, "no asteroid reaches into the area kept clear around the arrival point")
	_check(in_the_way > 0, "though the same field, with no arrival there, does put asteroids in that spot")
	_check(nearby > 3, "and the field starts just outside the clear area")

	print("Other chunk sizes")
	var small := ChunkGenerator.new(system, 250.0)
	var small_total := 0
	var small_chunks := 0
	for x in range(-8, 8):
		for y in range(-8, 8):
			for z in range(-8, 8):
				small_total += small.generate(Vector3i(x, y, z)).size()
				small_chunks += 1
	var small_mean := float(small_total) / small_chunks
	_check(small_mean < mean * 0.5 and small_mean > mean * 0.04, "a chunk half as wide holds about an eighth as many (%.2f against %.2f)" % [small_mean, mean])
	var tiny := ChunkGenerator.new(system, 8.0)
	var held := 0
	for x in range(-20, 20):
		held += tiny.generate(Vector3i(x, 0, 0)).size()
	_check(held == 0, "a chunk smaller than the smallest asteroid copes: it just holds none")


func _test_difficulty_in_chunks() -> void:
	print("Harder systems")
	var tuning := SystemTuning.new()
	var flat := Kit.flat_template()
	var easy := ChunkGenerator.new(StarSystem.create(31, 0, tuning, Vector3.ZERO, flat))
	var hard := ChunkGenerator.new(StarSystem.create(31, 400, tuning, Vector3.ZERO, flat))
	var easy_total := 0
	var hard_total := 0
	var easy_big := 0.0
	var hard_big := 0.0
	for x in range(-5, 5):
		for y in range(-5, 5):
			for z in range(-5, 5):
				var coord := Vector3i(x, y, z)
				for spec in easy.generate(coord):
					easy_total += 1
					easy_big = maxf(easy_big, spec.radius)
				for spec in hard.generate(coord):
					hard_total += 1
					hard_big = maxf(hard_big, spec.radius)
	_check(hard_total > easy_total, "a late system holds more asteroids than the first (%d against %d)" % [hard_total, easy_total])
	_check(hard_big > easy_big, "and bigger ones (%.0f m against %.0f m)" % [hard_big, easy_big])
	var first := easy.generate(Vector3i(2, 2, 2))
	var rebuilt := ChunkGenerator.new(StarSystem.create(31, 0, tuning, Vector3.ZERO, flat)).generate(Vector3i(2, 2, 2))
	_check(first.size() == rebuilt.size(), "and the first system is still built the same way")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
