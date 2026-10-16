extends Node
## Checks the Cosmic Presence on its own, with no ship or level: the bar counting up, its speed as an attribute
## with modifiers (flat, stacking, timed), what a jump takes off, the aggression it gives, what it tells a guest
## and that other systems can find it.
##
## godot --headless --fixed-fps 60 --path . res://Components/Jump/Testing/CosmicPresenceTest.tscn

var _failures := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	await _test_the_bar()
	await _test_speed()
	await _test_timed_modifiers()
	_test_relief()
	_test_aggression()
	_test_following()
	await _test_finding_and_the_attribute_interface()
	if _failures == 0:
		print("Cosmic presence tests passed.")
	else:
		print("Cosmic presence tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _make(fill_time := 100.0) -> CosmicPresence:
	var presence := CosmicPresence.new()
	presence.base_speed = 1.0 / fill_time
	add_child(presence)
	return presence


func _test_the_bar() -> void:
	print("The bar")
	var presence := _make(100.0)
	_check(presence.progress == 0.0 and presence.running and presence.aggression == 0.0, "it starts empty, running and calm")
	_check(is_equal_approx(presence.get_rate(), 0.01) and is_equal_approx(presence.get_time_to_full(), 100.0), "at a hundredth a second it takes 100 seconds to fill")
	presence.advance(10.0)
	_check(is_equal_approx(presence.progress, 0.1), "ten seconds is a tenth of the bar (%.3f)" % presence.progress)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(presence.progress > 0.1, "and it moves by itself every frame (%.4f)" % presence.progress)
	presence.running = false
	var held := presence.progress
	await get_tree().process_frame
	await get_tree().process_frame
	_check(presence.progress == held, "but not when it is told to hold still")
	presence.running = true
	var changes: Array[float] = []
	var filled: Array[bool] = []
	presence.progress_changed.connect(func(_progress: float, amount: float) -> void: changes.append(amount))
	presence.filled.connect(func() -> void: filled.append(true))
	presence.advance(200.0)
	_check(presence.progress == 1.0 and presence.is_full(), "it stops at a full bar")
	_check(filled.size() == 1 and changes.size() == 1 and changes[0] > 0.0, "and says so, once")
	presence.advance(5.0)
	_check(filled.size() == 1 and changes.size() == 1, "and stays quiet while it stays full")
	_check(presence.get_time_to_full() == 0.0, "no time is left to full")
	presence.progress = 0.4
	_check(is_equal_approx(presence.progress, 0.4) and not presence.is_full(), "the bar can be set")
	presence.progress = 7.0
	_check(presence.progress == 1.0, "but never past the ends")
	presence.progress = -3.0
	_check(presence.progress == 0.0, "either end")
	presence.base_speed = 0.0
	_check(presence.get_time_to_full() == INF and is_equal_approx(presence.get_speed_multiplier(), 1.0), "with no speed it never fills, and nothing divides by zero")
	presence.free()


func _test_speed() -> void:
	print("Speed is an attribute")
	var presence := _make(100.0)
	_check(presence.speed is Attribute and is_equal_approx(presence.speed.base_value, 0.01) and is_equal_approx(presence.speed.value, 0.01), "the speed is an Attribute whose base value is the normal speed")
	var multipliers: Array[float] = []
	presence.speed_changed.connect(func(multiplier: float) -> void: multipliers.append(multiplier))
	_check(presence.add_speed_modifier("mining", 100.0), "a modifier can be added")
	_check(is_equal_approx(presence.get_speed_multiplier(), 2.0) and is_equal_approx(presence.get_rate(), 0.02), "100 percent makes it twice as fast")
	_check(multipliers == [2.0], "and tells whoever is listening (%s)" % str(multipliers))
	presence.advance(10.0)
	_check(is_equal_approx(presence.progress, 0.2), "ten seconds at double speed is a fifth of the bar (%.3f)" % presence.progress)
	presence.add_speed_modifier("noise", 50.0)
	_check(is_equal_approx(presence.get_speed_multiplier(), 2.5), "a second modifier adds to the first (x%.2f)" % presence.get_speed_multiplier())
	presence.add_speed_modifier("noise", 25.0)
	_check(is_equal_approx(presence.get_speed_multiplier(), 2.25), "the same id replaces itself instead of stacking (x%.2f)" % presence.get_speed_multiplier())
	presence.add_speed_modifier("stack_a", 100.0, -1.0, true)
	presence.add_speed_modifier("stack_b", 100.0, -1.0, true)
	_check(is_equal_approx(presence.get_speed_multiplier(), 2.25 * 4.0), "ones that multiply compound (x%.2f)" % presence.get_speed_multiplier())
	presence.clear_speed_modifiers()
	_check(is_equal_approx(presence.get_speed_multiplier(), 1.0) and not presence.has_speed_modifier("mining"), "clearing them puts the speed back")
	presence.add_speed_modifier("calm", -50.0)
	_check(is_equal_approx(presence.get_speed_multiplier(), 0.5), "a negative one slows it (x%.2f)" % presence.get_speed_multiplier())
	presence.add_speed_modifier("freeze", -400.0)
	_check(presence.get_rate() == 0.0 and presence.get_speed_multiplier() == 0.0, "and it never goes backward, however much it is slowed")
	_check(not presence.add_speed_modifier("", 100.0), "a modifier needs a name")
	_check(presence.remove_speed_modifier("calm") and not presence.remove_speed_modifier("calm"), "removing one that is there works, and one that is not says so")
	presence.base_speed = 0.02
	presence.clear_speed_modifiers()
	_check(is_equal_approx(presence.get_rate(), 0.02) and is_equal_approx(presence.get_speed_multiplier(), 1.0), "a new normal speed is the new x1")
	presence.free()
	await get_tree().process_frame


func _test_timed_modifiers() -> void:
	print("Modifiers that run out")
	var presence := _make(100.0)
	presence.running = false
	presence.add_speed_modifier("burst", 100.0, 0.5)
	_check(presence.has_speed_modifier("burst") and is_equal_approx(presence.get_speed_multiplier(), 2.0), "a timed modifier works at once")
	for _frame in 20:
		await get_tree().process_frame
	_check(presence.has_speed_modifier("burst"), "and is still there after a third of a second")
	for _frame in 20:
		await get_tree().process_frame
	_check(not presence.has_speed_modifier("burst") and is_equal_approx(presence.get_speed_multiplier(), 1.0), "and gone after its half second")
	presence.add_speed_modifier("burst", 100.0, 0.4)
	for _frame in 15:
		await get_tree().process_frame
	presence.add_speed_modifier("burst", 100.0, 0.4)
	for _frame in 15:
		await get_tree().process_frame
	_check(presence.has_speed_modifier("burst"), "adding it again starts its time over")
	presence.add_speed_modifier("burst", 100.0)
	for _frame in 60:
		await get_tree().process_frame
	_check(presence.has_speed_modifier("burst"), "and adding it with no time makes it last")
	presence.free()


func _test_relief() -> void:
	print("What a jump takes off")
	var presence := _make(100.0)
	presence.progress = 0.8
	var amounts: Array[float] = []
	presence.relieved.connect(func(amount: float) -> void: amounts.append(amount))
	var taken := presence.relieve(0.5)
	_check(is_equal_approx(taken, 0.5) and is_equal_approx(presence.progress, 0.3) and amounts == [0.5], "half the bar comes off (%.2f, took %.2f)" % [presence.progress, taken])
	taken = presence.relieve(0.5)
	_check(is_equal_approx(taken, 0.3) and presence.progress == 0.0, "it cannot go below empty, and says how much it really took (%.2f)" % taken)
	_check(is_equal_approx(amounts[1], 0.3), "which is what the signal carries")
	_check(presence.relieve(0.5) == 0.0 and amounts.size() == 2, "taking from an empty bar is silent")
	presence.progress = 1.0
	presence.relieve(0.5)
	var refilled: Array[bool] = []
	presence.filled.connect(func() -> void: refilled.append(true))
	presence.advance(100.0)
	_check(refilled.size() == 1, "after a jump it can fill, and say so, again")
	presence.free()


func _test_aggression() -> void:
	print("Aggression")
	var presence := _make(100.0)
	presence.aggression_start = 0.4
	var seen: Array[float] = []
	presence.aggression_changed.connect(func(value: float) -> void: seen.append(value))
	presence.progress = 0.2
	_check(presence.aggression == 0.0 and seen.is_empty(), "far away it is not aggressive, and says nothing")
	presence.progress = 0.4
	_check(presence.aggression == 0.0, "nor at the point where it starts")
	presence.progress = 0.7
	_check(presence.aggression > 0.3 and presence.aggression < 0.7, "halfway between that and full it is halfway there (%.2f)" % presence.aggression)
	_check(not seen.is_empty() and is_equal_approx(seen[seen.size() - 1], presence.aggression), "and it said so (%s)" % str(seen))
	presence.progress = 1.0
	_check(is_equal_approx(presence.aggression, 1.0) and is_equal_approx(seen[seen.size() - 1], 1.0), "a full bar is full aggression")
	var previous := 0.0
	var rising := true
	for step in 101:
		presence.progress = step / 100.0
		rising = rising and presence.aggression >= previous - 0.00001
		previous = presence.aggression
	_check(rising, "it only ever grows as the bar does")
	presence.progress = 0.0
	_check(presence.aggression == 0.0 and is_equal_approx(seen[seen.size() - 1], 0.0), "and falls away when a jump empties the bar")
	_check(is_equal_approx(presence.get_closeness(), presence.progress), "how close it is is the bar")
	var count := seen.size()
	presence.progress = 0.0
	_check(seen.size() == count, "nothing is announced when nothing changed")
	presence.aggression_start = 0.9
	presence.progress = 0.5
	_check(presence.aggression == 0.0, "the point where it starts can be moved")
	presence.free()


func _test_following() -> void:
	print("A guest follows its host")
	var presence := _make(100.0)
	presence.follow(0.5, 0.04)
	_check(is_equal_approx(presence.progress, 0.5) and is_equal_approx(presence.get_rate(), 0.04) and is_equal_approx(presence.get_speed_multiplier(), 4.0), "it takes the host's bar and speed (x%.1f)" % presence.get_speed_multiplier())
	presence.add_speed_modifier("local", 100.0)
	_check(is_equal_approx(presence.get_rate(), 0.04), "and ignores what its own modifiers say")
	presence.advance(5.0)
	_check(is_equal_approx(presence.progress, 0.7), "moving the bar the host's way between messages (%.2f)" % presence.progress)
	_check(presence.is_following(), "it knows it is following")
	presence.stop_following()
	_check(not presence.is_following() and is_equal_approx(presence.get_rate(), 0.02), "and goes its own way after that")
	presence.free()


func _test_finding_and_the_attribute_interface() -> void:
	print("Finding it")
	var presence := _make(50.0)
	await get_tree().process_frame
	_check(CosmicPresence.find(self) == presence, "anything in the game can find the presence, to read how aggressive it is")
	_check(presence.is_in_group(CosmicPresence.GROUP), "it is in a group of its own")
	presence.progress = 0.25
	_check(is_equal_approx(presence.get_percentage(), 0.25) and is_equal_approx(presence.get_current_value(), 0.25) and is_equal_approx(presence.get_maximum_value(), 1.0), "it is an attribute node, so the attribute UI can show it")
	var changes: Array[float] = []
	presence.value_changed.connect(func(_before: float, current: float, _amount: float) -> void: changes.append(current))
	presence.progress = 0.5
	_check(changes == [0.5], "and sends the value_changed that UI listens for")
	presence.free()
	await get_tree().process_frame
	_check(CosmicPresence.find(self) == null, "with none in the game, find says so")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
