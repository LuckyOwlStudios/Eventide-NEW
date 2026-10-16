class_name StarGenerator
extends RefCounted
## Works out the stars of one system from its template and its seed: how big each looks, what color it is and which
## way it is. Nothing in it is random in the engine's sense; the same inputs always give the same stars.
##
## The template ([SystemTemplate]) says which stars there are, as a list of [Star]s with how far away each is and
## what color. The seed only fills in what a [Star] leaves open: the exact distance, within [member Star.distance_variation];
## the color, within [member Star.color_variation] (or any natural one, with [member Star.random_color]);
## and which way the star is, how fast it turns and how it is tilted.
##
## [b]Size and temperature.[/b] A star's size in the sky is how near it is. The system has already picked its temperature
## from the template's range, as [param roll] (0 the coldest end, 1 the hottest), and the stars follow it: a hotter
## system pulls each star closer, a colder one pushes it away, so the sky always agrees with the temperature. Each star
## drifts a little from the system's roll, so the stars of a binary are not twins.
##
## [b]Light.[/b] The light the stars give grows with the temperature, and is shared out between them in proportion
## to how much each gives ([member StarSpec.heat]: how big it looks, squared, times how bright its surface is).

## Mixed into the system's seed, so the stars have a stream of random numbers of their own.
const SEED_SALT := 0x73746172
## Half the width of a sun-like star at a comfortable distance, in radians (six degrees).
const REFERENCE_RADIUS := 0.1047198
## The smallest and biggest a star can look: radians (0.8 and 26 degrees). A distance of 1 is the smallest, 0 the biggest.
const MINIMUM_RADIUS := 0.0139626
const MAXIMUM_RADIUS := 0.4537856
## The light is [member SystemTuning.temperate_light] at temperature 0, and doubles this many times (1.3) going
## from comfortable to a temperature of [constant LIGHT_SCALE]. (Less than the heat itself, or the hot systems
## would be blinding and the cold ones black.)
const LIGHT_PER_DOUBLING := 1.3
const LIGHT_SCALE := 100.0
## The light stops growing and shrinking this many times [constant LIGHT_SCALE] out.
const LIGHT_LIMIT := 1.2
## How far a star's own roll can differ from its system's, in either direction.
const ROLL_DRIFT := 0.15
## The colors of natural stars: kelvin from this to that, mostly in the middle.
const COOLEST_KELVIN := 3500.0
const HOTTEST_KELVIN := 10000.0
const SUN_KELVIN := 5800.0
## Natural stars are this much white, so a red star is orange and a blue one pale.
const COLOR_WASH := 0.22
## The disc of a natural star is drawn this much more strongly colored than its light (see [member StarSpec.color_boost]).
const NATURAL_COLOR_BOOST := 1.7
## How far [member Star.color_variation] of 1 can turn the hue (a share of the color wheel), scale the saturation and
## scale the brightness, in either direction.
const HUE_VARIATION := 0.06
const SATURATION_VARIATION := 0.3
const VALUE_VARIATION := 0.12

## What was worked out for a system.
class Result:
	extends RefCounted
	var stars: Array[StarSpec] = []
	## The heat of the stars added up (see [member StarSpec.heat]).
	var heat := 0.0
	## The total energy of the light all the stars give.
	var light_energy := 0.75


## The stars of the system with seed [param system_seed] made from [param template], at temperature [param temperature]
## which is [param roll] of the way from the template's coldest to its hottest.
static func generate(system_seed: int, template: SystemTemplate, roll: float, temperature: float, tuning: SystemTuning = null) -> Result:
	if tuning == null:
		tuning = SystemTuning.new()
	var rng := SpaceRandom.new(SpaceRandom.combine(system_seed, SEED_SALT))
	var result := Result.new()
	for definition in template.stars:
		if definition == null:
			continue
		var star := StarSpec.new()
		star.source = definition

		# How near it is: the system's roll, drifted a little, picks a spot in the star's range.
		var own_roll := clampf(roll + rng.range_float(-ROLL_DRIFT, ROLL_DRIFT), 0.0, 1.0)
		star.distance = clampf(definition.distance + definition.distance_variation * (1.0 - 2.0 * own_roll), 0.0, 1.0)
		star.angular_radius = get_radius_for_distance(star.distance)

		# What color. (The numbers for both ways are always drawn, so the stars after this one do not change when
		# the way it is colored does.)
		var varied := vary_color(definition.color, definition.color_variation, rng)
		var natural_kelvin := _roll_kelvin(rng)
		if definition.random_color:
			star.kelvin = natural_kelvin
			star.color = color_for_kelvin(natural_kelvin)
			star.brightness = clampf(pow(natural_kelvin / SUN_KELVIN, 1.2), 0.5, 2.0)
			star.color_boost = NATURAL_COLOR_BOOST
		else:
			star.kelvin = SUN_KELVIN
			star.color = varied
			star.brightness = 1.0

		star.heat = pow(star.angular_radius / REFERENCE_RADIUS, 2.0) * star.brightness
		star.spin_speed = rng.range_float(0.008, 0.03) * (1.0 if rng.next_float() < 0.5 else -1.0)
		star.spin_phase = rng.next_float() * TAU
		star.tilt = rng.range_float(-0.6, 0.6)
		if result.stars.is_empty():
			star.direction = _roll_direction(rng)
		else:
			star.direction = _place_companion(rng, result.stars, star.angular_radius)
		result.stars.append(star)
		result.heat += star.heat

	result.light_energy = get_light_energy(temperature, tuning)
	for star in result.stars:
		star.light_energy = result.light_energy * star.heat / result.heat
	return result


## The total energy of the light of a system at [param temperature].
static func get_light_energy(temperature: float, tuning: SystemTuning = null) -> float:
	var comfortable := tuning.temperate_light if tuning != null else 0.75
	return comfortable * pow(2.0, LIGHT_PER_DOUBLING * clampf(temperature / LIGHT_SCALE, -LIGHT_LIMIT, LIGHT_LIMIT))


## Half the angle across a star that is [param distance] away (0 to 1, see [member Star.distance]), in radians.
## The size shrinks the same share for every step of distance, so the middle is a middling star.
static func get_radius_for_distance(distance: float) -> float:
	return MAXIMUM_RADIUS * pow(MINIMUM_RADIUS / MAXIMUM_RADIUS, clampf(distance, 0.0, 1.0))


## The distance (0 to 1) of a star that looks [param radius] radians across half its width.
static func get_distance_for_radius(radius: float) -> float:
	return clampf(log(clampf(radius, MINIMUM_RADIUS, MAXIMUM_RADIUS) / MAXIMUM_RADIUS) / log(MINIMUM_RADIUS / MAXIMUM_RADIUS), 0.0, 1.0)


## The color a star of [param kelvin] shines in, washed toward white so none is very strongly colored.
static func color_for_kelvin(kelvin: float) -> Color:
	var t := kelvin / 100.0
	var red := 255.0 if t <= 66.0 else 329.698727446 * pow(t - 60.0, -0.1332047592)
	var green := 99.4708025861 * log(t) - 161.1195681661 if t <= 66.0 else 288.1221695283 * pow(t - 60.0, -0.0755148492)
	var blue := 255.0 if t >= 66.0 else (0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307)
	var pure := Color(clampf(red, 0.0, 255.0) / 255.0, clampf(green, 0.0, 255.0) / 255.0, clampf(blue, 0.0, 255.0) / 255.0)
	return pure.lerp(Color.WHITE, COLOR_WASH)


## [param base] turned a little: its hue, saturation and brightness each moved by a random share of what
## [param variation] (0 to 1) allows. Always uses the same three random numbers, so the stars after it do not depend on
## how much variation this one asked for.
static func vary_color(base: Color, variation: float, rng: SpaceRandom) -> Color:
	var hue_roll := rng.next_float() * 2.0 - 1.0
	var saturation_roll := rng.next_float() * 2.0 - 1.0
	var value_roll := rng.next_float() * 2.0 - 1.0
	var amount := clampf(variation, 0.0, 1.0)
	var hue := fposmod(base.h + hue_roll * HUE_VARIATION * amount, 1.0)
	var saturation := clampf(base.s * (1.0 + saturation_roll * SATURATION_VARIATION * amount), 0.0, 1.0)
	var value := clampf(base.v * (1.0 + value_roll * VALUE_VARIATION * amount), 0.0, 1.0)
	return Color.from_hsv(hue, saturation, value, base.a)


## Mostly close to the sun's temperature, with the odd red or blue one.
static func _roll_kelvin(rng: SpaceRandom) -> float:
	var spread := rng.next_float() + rng.next_float() + rng.next_float() - 1.5
	return clampf(SUN_KELVIN + spread * 3600.0, COOLEST_KELVIN, HOTTEST_KELVIN)


## Any direction but not straight up or down, which keeps the light coming from the side more often than not.
static func _roll_direction(rng: SpaceRandom) -> Vector3:
	var random := rng.unit_vector()
	return Vector3(random.x, random.z * 0.75, random.y).normalized()


## A direction for a star next to the ones already there: well apart from each, so their discs never touch,
## but in the same part of the sky, like the two stars of a binary.
static func _place_companion(rng: SpaceRandom, others: Array[StarSpec], radius: float) -> Vector3:
	var primary: StarSpec = others[0]
	var best := primary.direction
	for attempt in 10:
		var axis := primary.direction.cross(rng.unit_vector())
		if axis.length_squared() < 0.0001:
			continue
		var widest := deg_to_rad(60.0 + 8.0 * attempt)
		var separation := rng.range_float(deg_to_rad(14.0), widest)
		var direction := primary.direction.rotated(axis.normalized(), separation)
		best = direction
		var clear := true
		for other in others:
			if direction.angle_to(other.direction) < (other.angular_radius + radius) * 1.5 + deg_to_rad(4.0):
				clear = false
		if clear:
			return direction
	return best
