class_name Asteroid
extends Resource
## A kind of asteroid: what it looks like, when it turns up, what grows out of it and what it drops. Every
## asteroid in a system is one of the kinds that fit the system.
##
## To add a kind, make a new [Asteroid] resource anywhere under [code]Game/Registry/Asteroids/[/code]. It is found
## by itself (see [AsteroidRegistry]). The simplest way is to copy a kind that is close to what you want and change
## it.
##
## [b]When it turns up.[/b] A system has a temperature (see [TemperatureHandler]), a jump count and tags (see
## [SystemTemplate]), and [method get_weight] says how common this kind is in it. It never turns up outside
## [member temperature_min] to [member temperature_max], is commonest at [member temperature_peak] and gets
## rarer toward the ends of the range. That is how a temperate system gets mostly plain rock with the odd warm or
## cool one, a frozen system mostly frozen and cold rocks and a hot one mostly hot and molten ones. The tags are for
## everything else: a kind can need a tag the system has ([member required_tags]), refuse one, or just be more
## common because of it ([member tag_weights]). Every kind that fits a system takes its share of the asteroids in
## proportion to its weight (see [AsteroidMix]).
##
## [b]What it looks like.[/b] The kind is made from [member base_material] (the rock texture) and the look settings
## below: a tint over it, how shiny it is, a glow, glowing cracks. Anything grown on it (crystals, spikes) is a
## [AsteroidDecorator]. [AsteroidMaterials] and [AsteroidShapes] build them.

## The name shown to the player, such as "Molten". The name of the file when empty.
@export var display_name := ""

@export_group("Where it turns up")
## The system temperatures it turns up in: never at or beyond these (on the [TemperatureHandler]'s scale: 0 is
## comfortable, -100 frozen, 100 scorching).
@export_range(-120.0, 120.0, 1.0) var temperature_min := -60.0
@export_range(-120.0, 120.0, 1.0) var temperature_max := 60.0
## The temperature it is commonest at. It gets rarer on both sides, down to nothing at the ends of the range.
@export_range(-120.0, 120.0, 1.0) var temperature_peak := 0.0
## How common it is where it is commonest, next to the others there. 1 against 0.5 is twice as common.
@export_range(0.0, 100.0, 0.01, "or_greater") var weight := 1.0
## The jump count needed for it to turn up: it never does before it.
@export_range(0, 500, 1, "or_greater") var min_jump := 0
## It only turns up in systems that have all of these tags.
@export var required_tags: Array[String] = []
## It never turns up in systems that have any of these tags.
@export var forbidden_tags: Array[String] = []
## Makes it more or less common in systems that have a tag: its weight is multiplied by the number for each
## tag the system has. 3 makes it three times as common, 0.2 five times as rare.
@export var tag_weights: Dictionary[String, float] = {}

@export_group("Look")
## What the rock is made from: its texture and normal map. [code]Assets/Materials/Asteroid.tres[/code] when
## empty. (The material file itself is never changed; every kind works on a copy of it.)
@export var base_material: StandardMaterial3D
## Colors the rock. White leaves it as the texture is. (The texture is dark, and is brightened a fixed amount first.)
@export var tint := Color.WHITE
## Whether the base material's texture is used at all. Off gives a smooth, untextured surface, like ice.
@export var use_texture := true
## How rough the surface is, from 0 (a mirror) to 1.
@export_range(0.0, 1.0, 0.01) var roughness := 0.75
@export_range(0.0, 1.0, 0.01) var metallic := 0.0
## How much light shines straight back off it, which is what makes ice gleam.
@export_range(0.0, 1.0, 0.01) var specular := 0.5
## How strong the texture's bumps are. 1 is as the material has them.
@export_range(0.0, 2.0, 0.01) var normal_strength := 1.0
## How much the color varies from place to place on one rock, from 0 (an even color) to 1.
@export_range(0.0, 1.0, 0.01) var mottling := 0.32

@export_subgroup("Glow")
## A glow over the whole rock, in [member glow_color]. 0 is none.
@export_range(0.0, 4.0, 0.01) var glow := 0.0
@export var glow_color := Color(0.45, 0.7, 1.0)

@export_subgroup("Cracks")
## Cracks in the rock that glow, like a lava flow under a crust.
@export var cracks := false
@export var crack_color := Color(1.0, 0.3, 0.06)
## How bright the cracks glow. A bright crack above 1 blooms, if the level has glow.
@export_range(0.0, 12.0, 0.1) var crack_energy := 2.0
## How wide the cracks are, from hairlines to a rock that is mostly lava.
@export_range(0.02, 0.5, 0.01) var crack_width := 0.14
## How much glow there is around the cracks and over the rest of the crust.
@export_range(0.0, 1.0, 0.01) var crack_halo := 0.22
## How much the glow swells and fades, slowly, from 0 (steady) to 1.
@export_range(0.0, 1.0, 0.01) var crack_pulse := 0.18

@export_group("Decorators")
## Things that grow out of it: ice crystals, purple crystals. See [AsteroidDecorator].
@export var decorators: Array[AsteroidDecorator] = []

@export_group("Drops")
## What breaking it up gives. (Nothing does that yet.)
@export var drops: Array[AsteroidDrop] = []


## How common this kind is in a system with [param temperature], [param tags] and jump count [param jump]:
## 0 when it cannot turn up there. Only worth comparing with other kinds' numbers.
func get_weight(temperature: float, tags: Array[String], jump: int) -> float:
	if weight <= 0.0 or jump < min_jump:
		return 0.0
	var low := minf(temperature_min, temperature_max)
	var high := maxf(temperature_min, temperature_max)
	if temperature <= low or temperature >= high:
		return 0.0
	for tag in required_tags:
		if not tags.has(tag):
			return 0.0
	for tag in forbidden_tags:
		if tags.has(tag):
			return 0.0
	var peak := clampf(temperature_peak, low, high)
	var shape := 1.0
	if temperature < peak:
		shape = smoothstep(low, peak, temperature)
	elif temperature > peak:
		shape = 1.0 - smoothstep(peak, high, temperature)
	var result := weight * shape
	for tag in tag_weights:
		if tags.has(tag):
			result *= maxf(tag_weights[tag], 0.0)
	return result


## Whether it is a kind with glowing cracks.
func has_cracks() -> bool:
	return cracks and crack_energy > 0.0


## What breaking one up gives this time: a list of [code]{"item": Item, "amount": int}[/code], leaving out what did
## not drop. [param rng] is the dice to roll with (the engine's global ones when empty).
func roll_drops(rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var given: Array[Dictionary] = []
	for drop in drops:
		if drop == null:
			continue
		var amount := drop.roll(rng)
		if amount > 0:
			given.append({"item": drop.item, "amount": amount})
	return given


## The name it is shown by: [member display_name], or the name of its file when that is empty.
func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return resource_path.get_file().get_basename().capitalize() if not resource_path.is_empty() else "Asteroid"
