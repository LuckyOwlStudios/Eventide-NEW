class_name StarSystem
extends RefCounted
## One system the ship has jumped to: a name, how hard it is, which kind of system it is, how hot, its stars and how its
## space is laid out, all worked out from the world's seed and the jump count. Nothing in it is random. Two machines
## that make a system from the same two numbers, and the same [SystemTuning] and templates, get the same system, so a
## lobby only has to agree on the seed and the count, and a saved world only has to store them.
##
## [b]How one is made.[/b] The jump count and seed pick a [SystemTemplate] (see [SystemRegistry]) and then the system
## fills in what the template leaves open: a temperature and a density inside the template's ranges, the exact size and
## color of its stars (see [StarGenerator]) and which asteroids it has (see [AsteroidMix]). The first system of a world
## is always [member SystemTuning.starting_template].
##
## Everything about a system that later features need to key off (what lives in it, how dangerous it is) should be
## added here, as a function of [member jump_count], [member difficulty], the template and the system's own seed.

const STAR_COUNT_NAMES: Array[String] = ["", "single", "binary", "ternary"]
## Words for how thick the asteroids are: sparse below the first limit, then low, medium, high, and packed above the last.
const DENSITY_NAMES: Array[String] = ["Sparse", "Low", "Medium", "High", "Packed"]
const DENSITY_LIMITS: Array[float] = [0.125, 0.375, 0.625, 0.875]
## Mixed into the system's seed, so the temperature and density have a stream of random numbers of their own.
const ROLL_SALT := 0x726F6C6C

const _NAME_PREFIXES := [
	"Ar", "Bel", "Cor", "Dra", "Eri", "Fen", "Gal", "Hel", "Ion", "Jor", "Kes", "Lyr", "Mor",
	"Nyx", "Ori", "Pax", "Qua", "Rho", "Sol", "Tau", "Ulm", "Vex", "Wyn", "Xan", "Yor", "Zeph",
]
const _NAME_SUFFIXES := ["", "a", "us", "on", "is", "ia", "ar", "ex"]

## How many jumps the ship has made to get here. The first system is 0.
var jump_count := 0
## Seeds everything built in this system. A new one for every jump.
var system_seed := 0
var system_name := ""
## From 0 (as easy as it gets) to 1 (as hard as it gets), rising with the jump count.
var difficulty := 0.0
## What kind of system it is.
var template: SystemTemplate
## How long the Cosmic Presence takes to cross the whole bar here at normal speed, in seconds.
var presence_fill_time := 1200.0
## How hot or cold it is, on the [TemperatureHandler]'s scale (0 comfortable, -100 frozen, 100 scorching). The
## asteroids and the light follow it, and so will anything that feels the heat.
var temperature := 0.0
var climate := TemperatureHandler.Climate.TEMPERATE
## How thick the asteroids are, from 0 (sparse) to 1 (packed), inside the template's range.
var density := 0.5
## Names that asteroids can ask for: the template's, the climate's ("hot") and how many stars ("binary").
var tags: Array[String] = []
## Asteroids in an average 500 m chunk. See [member SystemTuning.easy_density].
var asteroid_density := 4.0
var smallest_radius := 10.0
var largest_radius := 90.0
## How big the belts and voids are, in meters.
var cluster_size := 1800.0
## Where the ship arrives, and how far around it is kept clear.
var arrival_position := Vector3.ZERO
var arrival_clear_radius := 200.0
## The system's stars, the brightest first. There is usually at least one.
var stars: Array[StarSpec] = []
## How much heat the stars give added up (see [member StarSpec.heat]).
var heat := 1.0
## The total energy of the light the stars give.
var light_energy := 0.75
## Which kinds of asteroid the system has, and how many of its asteroids each is.
var asteroid_mix: AsteroidMix


## Builds the system reached by jump number [param jump] in the world with seed [param world_seed].
## [param arrival] is where the ship is when it arrives. [param forced_template] makes it that kind of system whatever
## the odds say (for testing).
static func create(world_seed: int, jump: int, tuning: SystemTuning = null, arrival := Vector3.ZERO, forced_template: SystemTemplate = null) -> StarSystem:
	if tuning == null:
		tuning = SystemTuning.new()
	var system := StarSystem.new()
	system.jump_count = maxi(jump, 0)
	system.system_seed = SpaceRandom.combine(world_seed, system.jump_count)
	system.difficulty = difficulty_for(system.jump_count, tuning)
	system.system_name = _make_name(system.system_seed)
	system.presence_fill_time = lerpf(tuning.easy_fill_time, minf(tuning.hard_fill_time, tuning.easy_fill_time), system.difficulty)
	system.smallest_radius = tuning.smallest_radius
	system.largest_radius = maxf(lerpf(tuning.easy_largest_radius, tuning.hard_largest_radius, system.difficulty), tuning.smallest_radius)
	system.cluster_size = tuning.cluster_size
	system.arrival_position = arrival
	system.arrival_clear_radius = tuning.arrival_clear_radius

	# What kind of system, and where in the template's ranges.
	system.template = forced_template if forced_template != null else pick_template(system.system_seed, system.jump_count, tuning)
	var rng := SpaceRandom.new(SpaceRandom.combine(system.system_seed, ROLL_SALT))
	var roll := rng.next_float()
	system.temperature = system.template.get_temperature_at(roll)
	system.climate = TemperatureHandler.get_climate(system.temperature)
	system.density = system.template.get_density_at(rng.next_float())
	system.asteroid_density = lerpf(tuning.easy_density, tuning.hard_density, system.difficulty) * get_density_factor(system.density, tuning)

	var lit := StarGenerator.generate(system.system_seed, system.template, roll, system.temperature, tuning)
	system.stars = lit.stars
	system.heat = lit.heat
	system.light_energy = lit.light_energy
	system.tags = _make_tags(system)
	system.asteroid_mix = AsteroidMix.for_system(system)
	return system


## The template for the system with seed [param system_seed] at jump [param jump]: the starting template for the first
## system of a world, and one picked by the odds for every other.
static func pick_template(system_seed: int, jump: int, tuning: SystemTuning = null) -> SystemTemplate:
	if jump <= 0:
		if tuning != null and tuning.starting_template != null:
			return tuning.starting_template
		return SystemTemplate.make_default()
	return SystemRegistry.pick(system_seed, jump)


## How hard jump number [param jump] is: 0 at the start, 0.5 at [member SystemTuning.halfway_jump]
## and closer to 1 for ever after.
static func difficulty_for(jump: int, tuning: SystemTuning) -> float:
	var steps := float(maxi(jump, 0))
	return steps / (steps + maxf(tuning.halfway_jump, 0.001))


## How many times the asteroids of a system of medium density a system of [param density] (0 to 1) has.
static func get_density_factor(density_value: float, tuning: SystemTuning) -> float:
	var clamped := clampf(density_value, 0.0, 1.0)
	if clamped < 0.5:
		return lerpf(tuning.sparse_density_factor, 1.0, clamped * 2.0)
	return lerpf(1.0, tuning.packed_density_factor, (clamped - 0.5) * 2.0)


## "Sparse", "Low", "Medium", "High" or "Packed" for a density from 0 to 1.
static func get_density_word(density_value: float) -> String:
	var index := 0
	for limit in DENSITY_LIMITS:
		if density_value >= limit:
			index += 1
	return DENSITY_NAMES[index]


## How fast the Cosmic Presence moves across the bar here at normal speed, as a share of it a second.
func get_presence_rate() -> float:
	return 1.0 / maxf(presence_fill_time, 1.0)


func get_star_count() -> int:
	return stars.size()


## "Frozen", "Temperate", "Scorching" and so on.
func get_climate_name() -> String:
	return TemperatureHandler.get_climate_name(climate)


func get_density_name() -> String:
	return get_density_word(density)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## What kind of system it is, in a few words: "Temperate · 22°C · Normal System", "Scorching · 112°C · Giant Star".
func get_description() -> String:
	var text := "%s · %s" % [get_climate_name(), TemperatureHandler.format_celsius(temperature)]
	if template != null:
		text += " · " + template.get_display_name()
	return text


static func _make_tags(system: StarSystem) -> Array[String]:
	var found: Array[String] = []
	for tag in system.template.tags:
		if not found.has(tag):
			found.append(tag)
	var climate_tag := system.get_climate_name().to_lower()
	if not found.has(climate_tag):
		found.append(climate_tag)
	var count_tag := STAR_COUNT_NAMES[clampi(system.stars.size(), 0, STAR_COUNT_NAMES.size() - 1)]
	if not count_tag.is_empty() and not found.has(count_tag):
		found.append(count_tag)
	return found


static func _make_name(system_seed_value: int) -> String:
	var rng := SpaceRandom.new(SpaceRandom.combine(system_seed_value, 0x6E616D65))
	var prefix: String = _NAME_PREFIXES[rng.range_int(0, _NAME_PREFIXES.size() - 1)]
	var suffix: String = _NAME_SUFFIXES[rng.range_int(0, _NAME_SUFFIXES.size() - 1)]
	return "%s%s-%d" % [prefix, suffix, rng.range_int(100, 999)]
