class_name CosmicPresence
extends AttributeNode
## The thing consuming the universe behind the ship, which is why nobody can stay in a system for long.
## It is a bar from nothing ([member progress] 0) to everything (1) that only ever creeps up: when it is
## full it has caught the ship, and the ship has to jump. Every jump leaves it behind (see [method relieve]),
## which takes some of the bar off.
##
## [b]Speed is an attribute.[/b] [member speed] is an [Attribute]: its base value is how much of the bar
## the presence covers each second, and anything the crew does that draws it on adds a modifier to it
## ([method add_speed_modifier]) and removes it when that stops. [method get_speed_multiplier] is how many
## times its normal speed it is going now, which is the "x2" the HUD shows.
##
## [b]Aggression.[/b] The closer the presence is, the nearer and the angrier it gets. [member aggression] is
## that, from 0 (it is far away and quiet) to 1 (it is upon the ship), and rises with the bar from
## [member aggression_start] on. Nothing reads it yet; it is here for what will spawn because of it.
## Any node can find the presence with [method find] and read [member aggression], or listen for [signal aggression_changed].
##
## This node only moves the bar. The [JumpDirector] owns it: it sets the speed for each system, pauses it
## while the ship jumps, takes the jump's relief off and starts the jump when the bar fills.

## The bar changed by [param amount] (negative when a jump took some off). Also sent as
## [signal AttributeNode.value_changed], for the attribute UI.
signal progress_changed(progress: float, amount: float)
## Aggression went to [param aggression] (sent when it moves by a visible amount, not every frame).
signal aggression_changed(aggression: float)
## The speed it is going changed: [param multiplier] times its normal speed.
signal speed_changed(multiplier: float)
## A jump took [param amount] off the bar.
signal relieved(amount: float)
## The bar became full.
signal filled

## Every presence is in this group.
const GROUP: StringName = &"cosmic_presence"
## Aggression is only reported again after it has moved this much.
const AGGRESSION_STEP := 0.01

@export_group("Bar")
## Where the bar stands, from 0 to 1.
@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		_set_progress(value)
	get:
		return _progress
## Moving at all. The jump director turns this off while the ship is jumping.
@export var running := true
## What the presence covers each second, as a share of the bar, at normal speed.
@export_range(0.0, 0.2, 0.0001, "or_greater") var base_speed := 1.0 / 1200.0:
	set(value):
		base_speed = maxf(value, 0.0)
		speed.base_value = base_speed

@export_group("Aggression")
## The bar must be this full before the presence starts to get aggressive.
@export_range(0.0, 0.99, 0.01) var aggression_start := 0.35:
	set(value):
		aggression_start = clampf(value, 0.0, 0.99)
		_update_aggression()

## How much of the bar the presence covers a second, as an [Attribute]. Modifiers added to it speed it up
## or slow it down; its value is what the bar moves by.
var speed := Attribute.new()
## How aggressive the presence is, from 0 to 1.
var aggression: float:
	get:
		return _aggression

var _progress := 0.0
var _aggression := 0.0
var _announced_aggression := 0.0
var _timed: Dictionary[String, ActiveAttributeModifier] = {}
var _remote_rate := -1.0
var _last_multiplier := 1.0
var _was_full := false


func _init() -> void:
	speed.base_value = base_speed
	speed.value_changed.connect(_on_speed_changed)


func _ready() -> void:
	add_to_group(GROUP)
	speed.base_value = base_speed
	_update_aggression()


func _process(delta: float) -> void:
	if not _timed.is_empty():
		_tick_timed_modifiers(delta)
	if running:
		advance(delta)


## The presence in the game that [param node] is in, or null when there is none.
static func find(node: Node) -> CosmicPresence:
	return node.get_tree().get_first_node_in_group(GROUP) as CosmicPresence


# --- The bar ---------------------------------------------------------------------------------------------

## Moves the bar by [param delta] seconds of its speed.
func advance(delta: float) -> void:
	var rate := get_rate()
	if rate > 0.0 and delta > 0.0:
		_set_progress(progress + rate * delta)


## Takes [param amount] (a share of the whole bar) off the bar, because a jump left the presence behind.
## Returns how much was taken: less than asked if the bar had less than that on it.
func relieve(amount: float) -> float:
	var before := progress
	_set_progress(progress - maxf(amount, 0.0))
	var taken := before - progress
	if taken > 0.0:
		relieved.emit(taken)
	return taken


## True once the bar is full: the presence has caught up.
func is_full() -> bool:
	return progress >= 1.0


## Seconds until the bar is full at the speed it is going, or [constant INF] when it is not going anywhere.
func get_time_to_full() -> float:
	var rate := get_rate()
	if rate <= 0.0:
		return INF
	return maxf(1.0 - progress, 0.0) / rate


# --- Speed --------------------------------------------------------------------------------------------------

## How much of the bar it covers a second right now, with every modifier on [member speed] in it. Never below 0.
func get_rate() -> float:
	if _remote_rate >= 0.0:
		return _remote_rate
	return maxf(speed.value, 0.0)


## How many times its normal speed it is going: 1 normally, 2 when twice as fast.
func get_speed_multiplier() -> float:
	if base_speed <= 0.0:
		return 1.0
	return get_rate() / base_speed


## Speeds the presence up by [param percent] of its normal speed (100 makes it twice as fast, -50 half),
## for [param seconds] or until [method remove_speed_modifier] when that is negative. [param id] says what
## is drawing it on: adding the same id again replaces the earlier one rather than stacking, and different
## ids add up. With [param multiply] the modifier multiplies whatever the others made instead, so two of
## them compound. Returns whether it was added.
func add_speed_modifier(id: String, percent: float, seconds := -1.0, multiply := false) -> bool:
	if id.is_empty():
		return false
	var modifier := AttributeModifier.new()
	modifier.id = StringName(id)
	modifier.amount = percent
	modifier.operation = AttributeModifier.Operation.MULTIPLY_TOTAL if multiply else AttributeModifier.Operation.ADD_MULTIPLIED_BASE
	modifier.duration = seconds
	if seconds >= 0.0:
		_timed[id] = ActiveAttributeModifier.new(modifier)
	else:
		_timed.erase(id)
	return speed.add_attribute_modifier(id, modifier)


## Takes away what [method add_speed_modifier] added under [param id]. Returns whether there was one.
func remove_speed_modifier(id: String) -> bool:
	_timed.erase(id)
	return speed.remove_attribute_modifier(id)


func has_speed_modifier(id: String) -> bool:
	return speed.has_attribute_modifier(id)


## Takes away every modifier, so the presence goes at its normal speed again.
func clear_speed_modifiers() -> void:
	_timed.clear()
	speed.clear_attribute_modifiers()


# --- Aggression ------------------------------------------------------------------------------------------------

## How aggressive the presence is with the bar at [param bar]: 0 until [member aggression_start], then rising
## smoothly to 1 at a full bar.
func get_aggression_at(bar: float) -> float:
	if aggression_start >= 1.0:
		return 0.0
	return smoothstep(aggression_start, 1.0, bar)


## How near the presence is, from 0 (very far) to 1 (upon the ship). The same as the bar.
func get_closeness() -> float:
	return progress


# --- Multiplayer ----------------------------------------------------------------------------------------------------

## A guest has no way to know what the crew is doing to the host's presence, so it is told where the bar is and how
## fast it is going, and moves the bar itself between messages. Call [method stop_following] to go back to its own speed.
func follow(host_progress: float, host_rate: float) -> void:
	_remote_rate = maxf(host_rate, 0.0)
	_set_progress(host_progress)
	_announce_speed()


func stop_following() -> void:
	_remote_rate = -1.0
	_announce_speed()


func is_following() -> bool:
	return _remote_rate >= 0.0


# --- AttributeNode -------------------------------------------------------------------------------------------------------

func get_current_value() -> float:
	return progress


func get_maximum_value() -> float:
	return 1.0


func get_percentage() -> float:
	return progress


# --- Details ----------------------------------------------------------------------------------------------------------------------

func _set_progress(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if clamped == _progress:
		return
	var before := _progress
	_progress = clamped
	_update_aggression()
	progress_changed.emit(_progress, _progress - before)
	value_changed.emit(before, _progress, _progress - before)
	if _progress >= 1.0 and not _was_full:
		_was_full = true
		filled.emit()
	elif _progress < 1.0:
		_was_full = false


func _update_aggression() -> void:
	_aggression = get_aggression_at(progress)
	if absf(_aggression - _announced_aggression) >= AGGRESSION_STEP or (_aggression != _announced_aggression and (_aggression <= 0.0 or _aggression >= 1.0)):
		_announced_aggression = _aggression
		aggression_changed.emit(_aggression)


func _tick_timed_modifiers(delta: float) -> void:
	var expired: Array[String] = []
	for id in _timed:
		if _timed[id].tick(delta):
			expired.append(id)
	for id in expired:
		remove_speed_modifier(id)


func _on_speed_changed(_previous: float, _current: float, _change: float) -> void:
	_announce_speed()


func _announce_speed() -> void:
	var multiplier := get_speed_multiplier()
	if not is_equal_approx(multiplier, _last_multiplier):
		_last_multiplier = multiplier
		speed_changed.emit(multiplier)
