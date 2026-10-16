class_name SpaceRandom
extends RefCounted
## A random number generator for building space from a seed. The same seed gives the same numbers
## on every machine and in every version of the game, which is what lets a saved world, and every
## player in a lobby, rebuild exactly the same asteroids from one number.
##
## It is SplitMix64, written out here instead of using [RandomNumberGenerator] because the engine
## is free to change the algorithm behind that class between versions, and a world saved by an
## older game would then rebuild differently. Nothing in the numbers below may ever change.
##
## The static functions turn a few numbers into one seed. [code]SpaceRandom.combine(seed, x)[/code]
## folds [code]x[/code] into a seed so that neighbouring values (chunk 4 and chunk 5) give seeds
## with nothing in common.
##
## The methods are not called randf, randf_range and randi_range on purpose: inside a class, GDScript
## runs the engine's own function of that name (the unseeded one) instead of a method that shares it.

## SplitMix64's constants, as signed 64-bit integers (GDScript ints wrap around like they do).
const _GAMMA := -7046029254386353131
const _MULTIPLY_A := -4658895280553007687
const _MULTIPLY_B := -7723592293110705685

var _state := 0


func _init(seed_value: int = 0) -> void:
	_state = mix(seed_value)


## Shifts right without copying the sign bit in, which GDScript's [code]>>[/code] does.
static func _shift_right(value: int, bits: int) -> int:
	return (value >> bits) & ((1 << (64 - bits)) - 1)


## Scrambles [param value] into a number with no pattern left in it (the SplitMix64 finalizer).
static func mix(value: int) -> int:
	var z := value + _GAMMA
	z = (z ^ _shift_right(z, 30)) * _MULTIPLY_A
	z = (z ^ _shift_right(z, 27)) * _MULTIPLY_B
	return z ^ _shift_right(z, 31)


## Folds [param value] into [param seed_value], giving a new seed. Order matters.
static func combine(seed_value: int, value: int) -> int:
	return mix(mix(seed_value) ^ value)


## The seed of one chunk of a system: its own, whatever the chunks around it are.
static func chunk_seed(system_seed: int, coord: Vector3i) -> int:
	return combine(combine(combine(system_seed, coord.x), coord.y), coord.z)


## The next 64 random bits.
func next_int() -> int:
	_state += _GAMMA
	var z := _state
	z = (z ^ _shift_right(z, 30)) * _MULTIPLY_A
	z = (z ^ _shift_right(z, 27)) * _MULTIPLY_B
	return z ^ _shift_right(z, 31)


## A number from 0 up to, but not including, 1.
func next_float() -> float:
	return float(_shift_right(next_int(), 40)) / 16777216.0


## A number from [param from] up to, but not including, [param to].
func range_float(from: float, to: float) -> float:
	return from + (to - from) * next_float()


## A whole number from [param from] to [param to], both included.
func range_int(from: int, to: int) -> int:
	if to <= from:
		return from
	return from + _shift_right(next_int(), 1) % (to - from + 1)


## True this often, as a share from 0 to 1.
func chance(probability: float) -> bool:
	return next_float() < probability


## A direction, equally likely to be any of them.
func unit_vector() -> Vector3:
	var z := range_float(-1.0, 1.0)
	var angle := next_float() * TAU
	var ring := sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(ring * cos(angle), ring * sin(angle), z)


## A turn to any orientation, equally likely to be any of them.
func rotation() -> Basis:
	var u1 := next_float()
	var u2 := next_float() * TAU
	var u3 := next_float() * TAU
	var outer := sqrt(1.0 - u1)
	var inner := sqrt(u1)
	return Basis(Quaternion(outer * sin(u2), outer * cos(u2), inner * sin(u3), inner * cos(u3)))


## The index of one of [param weights], picked in proportion to its weight. -1 when all are zero.
func pick_weighted(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return -1
	var target := next_float() * total
	for index in weights.size():
		target -= maxf(weights[index], 0.0)
		if target < 0.0:
			return index
	return weights.size() - 1
