class_name TemperatureHandler
extends InGameSystem
## Everything about temperature in the game, in one place: how warm the system the ship is in is, what to call
## a temperature, and how to show one in degrees.
##
## [b]The scale.[/b] [constant NEUTRAL] (0) is the temperature the game treats as comfortable. Anything hotter is a
## positive number and anything colder a negative one, so how far a temperature is from 0 says how much hotter or
## colder than comfortable it is. -100 is frozen and 100 scorching, and nothing stops a number going further
## (a black hole's edge, a ship's engine). [method to_celsius] and [method to_fahrenheit] turn a number on this
## scale into real degrees for showing to the player; nothing in the game itself works in degrees.
##
## [b]Words.[/b] [method get_climate] and [method get_word] sort a temperature into [enum Climate] (Frozen,
## Cold, Cool, Temperate, Warm, Hot, Scorching), where [constant LIMITS] says where each starts. The helpers are
## static, so any code can use them without a handler.
##
## [b]The handler.[/b] The node (in the level's Ingame Systems, registered with [code]InGameHandler[/code]) holds
## the temperature of the system the ship is in, which the [JumpDirector] sets after every jump. Ask it with
## [method get_system_temperature], or for a place with [method get_temperature_at].
##
## [b]Later.[/b] A [i]temperature[/i] attribute on players, creatures and vehicles is planned. It should start from
## [method get_temperature_at] (so that a fire, an engine or a doorway into a hotter room can later change it
## from place to place without any caller changing) and move toward it, on this same scale. [signal system_temperature_changed]
## is there for anything that has to react to a jump.

## The temperature of the system changed, which is every jump.
signal system_temperature_changed(temperature: float)

## What a temperature is called, from coldest to hottest. See [constant LIMITS] for where each begins.
enum Climate {
	FROZEN,
	COLD,
	COOL,
	TEMPERATE,
	WARM,
	HOT,
	SCORCHING,
}

## The temperature that is neither hot nor cold.
const NEUTRAL := 0.0
## The ends of the scale as the game uses it. Nothing is clamped to them; they are what a word that has no end
## (Frozen, Scorching) counts as when a temperature has to be picked from its range.
const COLDEST := -120.0
const HOTTEST := 120.0
## Where each word after the first begins: Cold from -80, Cool from -50, Temperate from -20, Warm from 20,
## Hot from 50 and Scorching from 80. (A temperature exactly on one belongs to the hotter word.)
const LIMITS: Array[float] = [-80.0, -50.0, -20.0, 20.0, 50.0, 80.0]
const CLIMATE_NAMES: Array[String] = ["Frozen", "Cold", "Cool", "Temperate", "Warm", "Hot", "Scorching"]
## 0 on the game's scale is this many degrees Celsius, and every step up it adds this many.
## (So 80, a hot system, is boiling water at 100 degrees.)
const NEUTRAL_CELSIUS := 20.0
const CELSIUS_PER_STEP := 1.0

## The temperature of the system the ship is in.
var system_temperature := NEUTRAL:
	set(value):
		if is_equal_approx(system_temperature, value):
			return
		system_temperature = value
		system_temperature_changed.emit(system_temperature)


func _enter_tree() -> void:
	InGameHandler.register_temperature_handler(self)


func _exit_tree() -> void:
	InGameHandler.unregister_temperature_handler(self)


# --- Asking the handler ---------------------------------------------------------

## How hot or cold the system the ship is in is.
func get_system_temperature() -> float:
	return system_temperature


## Tells the handler what the system is like. The [JumpDirector] does this after every jump.
func set_system_temperature(value: float) -> void:
	system_temperature = value


func get_system_climate() -> Climate:
	return get_climate(system_temperature)


## "Frozen", "Hot" and so on for the system the ship is in.
func get_system_word() -> String:
	return get_word(system_temperature)


## The temperature at [param point] in the world. For now it is the system's everywhere; this is the one place
## to add the things that change it from place to place, such as a fire.
func get_temperature_at(_point: Vector3) -> float:
	return system_temperature


# --- Words ------------------------------------------------------------------------

## Which word [param temperature] gets.
static func get_climate(temperature: float) -> Climate:
	var climate := 0
	for limit in LIMITS:
		if temperature >= limit:
			climate += 1
	return climate as Climate


## "Frozen" for -100, "Temperate" for 0, "Hot" for 60, "Scorching" for 100.
static func get_word(temperature: float) -> String:
	return CLIMATE_NAMES[get_climate(temperature)]


static func get_climate_name(climate: Climate) -> String:
	return CLIMATE_NAMES[clampi(climate, 0, CLIMATE_NAMES.size() - 1)]


## The temperatures that get [param climate]'s word, coldest first. The first word is cold down to [constant COLDEST]
## and the last hot up to [constant HOTTEST].
static func get_climate_range(climate: Climate) -> Vector2:
	var index := clampi(climate, 0, CLIMATE_NAMES.size() - 1)
	var low := COLDEST if index == 0 else LIMITS[index - 1]
	var high := HOTTEST if index == LIMITS.size() else LIMITS[index]
	return Vector2(low, high)


## How far [param temperature] is from comfortable, hotter or colder.
static func get_deviation(temperature: float) -> float:
	return absf(temperature - NEUTRAL)


# --- Degrees ------------------------------------------------------------------------

static func to_celsius(temperature: float) -> float:
	return NEUTRAL_CELSIUS + (temperature - NEUTRAL) * CELSIUS_PER_STEP


static func to_fahrenheit(temperature: float) -> float:
	return to_celsius(temperature) * 9.0 / 5.0 + 32.0


## The game's number for [param degrees] Celsius.
static func from_celsius(degrees: float) -> float:
	return NEUTRAL + (degrees - NEUTRAL_CELSIUS) / CELSIUS_PER_STEP


## The game's number for [param degrees] Fahrenheit.
static func from_fahrenheit(degrees: float) -> float:
	return from_celsius((degrees - 32.0) * 5.0 / 9.0)


## "58°C", rounded to a whole degree.
static func format_celsius(temperature: float) -> String:
	return "%d°C" % roundi(to_celsius(temperature))


## "136°F", rounded to a whole degree.
static func format_fahrenheit(temperature: float) -> String:
	return "%d°F" % roundi(to_fahrenheit(temperature))


## "Hot (58°C)", or in Fahrenheit when [param fahrenheit] is true.
static func describe(temperature: float, fahrenheit := false) -> String:
	var degrees := format_fahrenheit(temperature) if fahrenheit else format_celsius(temperature)
	return "%s (%s)" % [get_word(temperature), degrees]
