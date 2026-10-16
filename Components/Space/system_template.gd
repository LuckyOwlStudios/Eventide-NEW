class_name SystemTemplate
extends Resource
## A kind of star system. Systems are not made from nothing: each jump picks one of these (see [SystemRegistry]) and
## the seed only fills in what the template leaves open, so a system is always one of a short list of kinds,
## each with its own stars, its own climate and its own thickness of asteroids.
##
## To add a kind of system, make a new [SystemTemplate] resource anywhere under [code]Game/Registry/Systems/[/code]
## and fill it in. It is found by itself. A template says:
## [br]- how often it turns up and from which jump on ([member weight], [member min_jump]),
## [br]- how hot its systems are, as a range ([member temperature_min] to [member temperature_max]); the
## [TemperatureHandler] says what a temperature is called, and every asteroid follows the system's temperature
## (see [Asteroid]),
## [br]- how thick its asteroids are, as a range ([member density_min] to [member density_max]),
## [br]- its stars ([member stars]),
## [br]- [member tags], which asteroids can ask for, and
## [br]- optionally a [member scene] of its own, for anything that makes the system unique, like a black hole.

## The name shown to the player, such as "Giant Star". The name of the file when empty.
@export var display_name := ""
## How often this kind of system turns up next to the others that can. 10 against 5 is twice as often.
@export_range(0.0, 100.0, 0.1, "or_greater") var weight := 1.0
## The jump count needed for this kind of system to appear: it never does before it. The very first system of a
## world is [member SystemTuning.starting_template] whatever this says.
@export_range(0, 500, 1, "or_greater") var min_jump := 0

@export_group("Temperature")
## The coldest and hottest systems of this kind are, on the [TemperatureHandler]'s scale: 0 is comfortable, -100
## is frozen and 100 scorching. Each system picks a spot between the two. The words start at -80 (Cold), -50
## (Cool), -20 (Temperate), 20 (Warm), 50 (Hot) and 80 (Scorching).
@export_range(-120.0, 120.0, 1.0) var temperature_min := -20.0
@export_range(-120.0, 120.0, 1.0) var temperature_max := 20.0

@export_group("Asteroids")
## How thick the asteroids are at the thinnest and the thickest of this kind of system: 0 is sparse, 0.25 low,
## 0.5 medium, 0.75 high and 1 packed. Each system picks a spot between the two.
@export_range(0.0, 1.0, 0.01) var density_min := 0.2
@export_range(0.0, 1.0, 0.01) var density_max := 0.8
## Names that asteroids can ask for (see [member Asteroid.required_tags] and [member Asteroid.tag_weights]), so a
## kind of system can have asteroids that no other has. A system also has the name of its climate ("hot") and
## of how many stars it has ("single", "binary" or "ternary") without anyone writing them here.
@export var tags: Array[String] = []

@export_group("Stars")
## The stars of this kind of system, the first being the main one. None makes a system with no star, and no light.
@export var stars: Array[Star] = []

@export_group("Custom")
## Something unique to this kind of system, put into the world with it: a black hole, a wreck, a station. It is
## made fresh for every system of this kind and freed when the ship leaves. If its root has a method
## [code]setup(system: StarSystem)[/code] it is called before the scene enters the tree, with the system it is
## for, so the scene can place itself from the system's seed. (Every player builds it, so it must depend on nothing
## but the system.)
@export var scene: PackedScene


## The name shown to the player: [member display_name], or the name of the file ("Giant Star" for GiantStar.tres)
## when that is empty.
func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	if not resource_path.is_empty():
		return resource_path.get_file().get_basename().capitalize()
	return "System"


## Whether a system of this kind can turn up at jump [param jump].
func is_available(jump: int) -> bool:
	return jump >= min_jump and weight > 0.0


## The temperature of a system of this kind where [param roll] is 0 for the coldest and 1 for the hottest.
func get_temperature_at(roll: float) -> float:
	return lerpf(minf(temperature_min, temperature_max), maxf(temperature_min, temperature_max), clampf(roll, 0.0, 1.0))


## The density of a system of this kind where [param roll] is 0 for the thinnest and 1 for the thickest.
func get_density_at(roll: float) -> float:
	return lerpf(minf(density_min, density_max), maxf(density_min, density_max), clampf(roll, 0.0, 1.0))


## What this kind's temperatures are called: "Temperate", or "Warm to Hot" when the range runs over more than one word.
func get_temperature_words() -> String:
	var low := minf(temperature_min, temperature_max)
	var high := maxf(temperature_min, temperature_max)
	# (A system never has quite the hottest temperature, which would be the next word if it lay on a limit.)
	var cold := TemperatureHandler.get_word(low)
	var hot := TemperatureHandler.get_word(high - 0.001 if high > low else high)
	return cold if cold == hot else "%s to %s" % [cold, hot]


## A template with nothing filled in: a normal system with one sun-like star. What a system is made from when
## there are no templates at all.
static func make_default() -> SystemTemplate:
	var template := SystemTemplate.new()
	template.display_name = "Normal System"
	template.stars.append(Star.new())
	return template
