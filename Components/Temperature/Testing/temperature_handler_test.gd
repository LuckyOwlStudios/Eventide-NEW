extends Node
## Checks the temperature scale: the word each temperature gets, the ranges those words cover, the translation into
## degrees Celsius and Fahrenheit and back, and the handler node that holds the temperature of the system the ship is in.
##
## godot --headless --fixed-fps 60 --path . res://Components/Temperature/Testing/TemperatureHandlerTest.tscn

var _failures := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_test_words()
	_test_ranges()
	_test_degrees()
	await _test_the_handler()
	if _failures == 0:
		print("Temperature tests passed.")
	else:
		print("Temperature tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_words() -> void:
	print("Words")
	_check(TemperatureHandler.get_climate(-100.0) == TemperatureHandler.Climate.FROZEN and TemperatureHandler.get_word(-100.0) == "Frozen", "-100 is Frozen")
	_check(TemperatureHandler.get_word(0.0) == "Temperate" and TemperatureHandler.NEUTRAL == 0.0, "0, the neutral temperature, is Temperate")
	_check(TemperatureHandler.get_word(60.0) == "Hot" and TemperatureHandler.get_word(100.0) == "Scorching", "60 is Hot and 100 Scorching")
	_check(TemperatureHandler.get_word(80.0) == "Scorching" and TemperatureHandler.get_word(79.9) == "Hot", "80 is where Scorching begins")
	_check(TemperatureHandler.get_climate(-80.0) == TemperatureHandler.Climate.COLD and TemperatureHandler.get_climate(-80.001) == TemperatureHandler.Climate.FROZEN, "and -80 is where Frozen ends: a temperature on a limit gets the hotter word")
	_check(TemperatureHandler.get_climate(-50.0) == TemperatureHandler.Climate.COOL and TemperatureHandler.get_climate(-20.0) == TemperatureHandler.Climate.TEMPERATE and TemperatureHandler.get_climate(19.99) == TemperatureHandler.Climate.TEMPERATE and TemperatureHandler.get_climate(20.0) == TemperatureHandler.Climate.WARM and TemperatureHandler.get_climate(50.0) == TemperatureHandler.Climate.HOT, "Cool from -50, Temperate from -20, Warm from 20, Hot from 50")
	_check(TemperatureHandler.get_climate(5000.0) == TemperatureHandler.Climate.SCORCHING and TemperatureHandler.get_climate(-5000.0) == TemperatureHandler.Climate.FROZEN, "and the scale goes on past 100 either way")
	var never_cools := true
	var previous := -1
	for step in range(-300, 301):
		var climate := TemperatureHandler.get_climate(float(step))
		never_cools = never_cools and climate >= previous
		previous = climate
	_check(never_cools, "going up the scale, the word only ever gets hotter")
	_check(TemperatureHandler.CLIMATE_NAMES.size() == TemperatureHandler.Climate.size() and TemperatureHandler.LIMITS.size() == TemperatureHandler.Climate.size() - 1, "there is a name for every word and a limit between each")
	_check(TemperatureHandler.get_climate_name(TemperatureHandler.Climate.WARM) == "Warm" and TemperatureHandler.get_climate_name(TemperatureHandler.Climate.COOL) == "Cool", "names can be asked for by word")
	_check(is_equal_approx(TemperatureHandler.get_deviation(-30.0), 30.0) and is_equal_approx(TemperatureHandler.get_deviation(45.0), 45.0), "how far from comfortable is the distance from 0, either way")


func _test_ranges() -> void:
	print("Ranges")
	var contiguous := true
	var middle_matches := true
	for climate in TemperatureHandler.Climate.size():
		var range_of := TemperatureHandler.get_climate_range(climate as TemperatureHandler.Climate)
		middle_matches = middle_matches and TemperatureHandler.get_climate((range_of.x + range_of.y) * 0.5) == climate
		middle_matches = middle_matches and TemperatureHandler.get_climate(range_of.x) == climate
		if climate > 0:
			contiguous = contiguous and is_equal_approx(range_of.x, TemperatureHandler.get_climate_range((climate - 1) as TemperatureHandler.Climate).y)
	_check(contiguous, "each word's range starts where the colder one's ends")
	_check(middle_matches, "and every temperature in a range gets that range's word")
	_check(TemperatureHandler.get_climate_range(TemperatureHandler.Climate.FROZEN).x == TemperatureHandler.COLDEST and TemperatureHandler.get_climate_range(TemperatureHandler.Climate.SCORCHING).y == TemperatureHandler.HOTTEST, "the first and last run out to the ends of the scale")
	var temperate := TemperatureHandler.get_climate_range(TemperatureHandler.Climate.TEMPERATE)
	_check(temperate == Vector2(-20.0, 20.0), "Temperate is -20 to 20 (%s)" % str(temperate))


func _test_degrees() -> void:
	print("Degrees")
	_check(is_equal_approx(TemperatureHandler.to_celsius(0.0), 20.0) and is_equal_approx(TemperatureHandler.to_fahrenheit(0.0), 68.0), "0, comfortable, is 20 degrees Celsius and 68 Fahrenheit")
	_check(is_equal_approx(TemperatureHandler.to_celsius(80.0), 100.0) and is_equal_approx(TemperatureHandler.to_fahrenheit(80.0), 212.0), "80 is boiling water")
	_check(is_equal_approx(TemperatureHandler.to_celsius(-100.0), -80.0), "and -100 is minus 80")
	var round_trips := true
	for step in range(-150, 151, 7):
		var temperature := float(step)
		round_trips = round_trips and absf(TemperatureHandler.from_celsius(TemperatureHandler.to_celsius(temperature)) - temperature) < 0.0001
		round_trips = round_trips and absf(TemperatureHandler.from_fahrenheit(TemperatureHandler.to_fahrenheit(temperature)) - temperature) < 0.0001
	_check(round_trips, "degrees translate back to the game's numbers")
	_check(is_equal_approx(TemperatureHandler.from_celsius(0.0), -20.0) and is_equal_approx(TemperatureHandler.from_fahrenheit(32.0), -20.0), "freezing water is -20 whichever way it is said")
	_check(TemperatureHandler.format_celsius(0.0) == "20°C" and TemperatureHandler.format_fahrenheit(0.0) == "68°F", "showing degrees: %s, %s" % [TemperatureHandler.format_celsius(0.0), TemperatureHandler.format_fahrenheit(0.0)])
	_check(TemperatureHandler.format_celsius(-100.0) == "-80°C" and TemperatureHandler.format_celsius(33.4) == "53°C", "rounded to a whole degree (%s, %s)" % [TemperatureHandler.format_celsius(-100.0), TemperatureHandler.format_celsius(33.4)])
	_check(TemperatureHandler.describe(60.0) == "Hot (80°C)" and TemperatureHandler.describe(60.0, true) == "Hot (176°F)", "a word and the degrees together (%s, %s)" % [TemperatureHandler.describe(60.0), TemperatureHandler.describe(60.0, true)])


func _test_the_handler() -> void:
	print("The handler")
	var handler := TemperatureHandler.new()
	_check(handler is InGameSystem and not InGameHandler.has_temperature_handler(), "it is an in-game system, and nothing is registered before it is in a game")
	add_child(handler)
	_check(InGameHandler.has_temperature_handler() and InGameHandler.get_temperature_handler() == handler and InGameHandler.get_temperature_handler_or_null() == handler, "once in the tree it is the session's temperature handler")
	_check(handler.is_in_group("ingame_system"), "and is in the ingame_system group")
	_check(is_zero_approx(handler.get_system_temperature()) and handler.get_system_word() == "Temperate", "the system starts out comfortable")
	var heard: Array[float] = []
	handler.system_temperature_changed.connect(func(value: float) -> void: heard.append(value))
	handler.set_system_temperature(75.0)
	_check(is_equal_approx(handler.get_system_temperature(), 75.0) and handler.get_system_word() == "Hot" and handler.get_system_climate() == TemperatureHandler.Climate.HOT, "it holds the temperature of the system it is told about, and names it")
	handler.set_system_temperature(75.0)
	_check(heard.size() == 1 and is_equal_approx(heard[0], 75.0), "and says so once, not again for the same temperature (%s)" % str(heard))
	handler.set_system_temperature(-100.0)
	_check(heard.size() == 2 and handler.get_system_word() == "Frozen", "or when it changes")
	_check(is_equal_approx(handler.get_temperature_at(Vector3(1000.0, -5.0, 20.0)), -100.0), "the temperature anywhere is the system's, for now")
	handler.free()
	await get_tree().process_frame
	_check(not InGameHandler.has_temperature_handler() and InGameHandler.get_temperature_handler_or_null() == null, "and when it leaves the tree nothing is registered")

	var first := TemperatureHandler.new()
	var second := TemperatureHandler.new()
	add_child(first)
	add_child(second)
	first.free()
	await get_tree().process_frame
	_check(InGameHandler.get_temperature_handler_or_null() == second, "one that leaves does not unregister another")
	second.free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
