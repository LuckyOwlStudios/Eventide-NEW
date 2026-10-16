class_name AsteroidDrop
extends Resource
## One thing an asteroid can drop when it is broken up: an item, how likely it is and how many. (Nothing breaks
## asteroids up yet, so nothing reads these yet. They are here so asteroids can be given what they hold as they
## are made; see [member Asteroid.drops] and [method Asteroid.roll_drops].)

@export var item: Item
## How likely the asteroid is to drop this at all, from 0 (never) to 1 (always).
@export_range(0.0, 1.0, 0.01) var chance := 1.0
## How many of it drops when it does.
@export_range(1, 999, 1, "or_greater") var min_amount := 1
@export_range(1, 999, 1, "or_greater") var max_amount := 1


## How many of the item to drop this time, 0 for none. [param rng] is the dice to roll with (the engine's
## global ones when empty).
func roll(rng: RandomNumberGenerator = null) -> int:
	if item == null:
		return 0
	var chance_roll := rng.randf() if rng != null else randf()
	if chance_roll >= chance:
		return 0
	var low := mini(min_amount, max_amount)
	var high := maxi(min_amount, max_amount)
	return rng.randi_range(low, high) if rng != null else randi_range(low, high)
