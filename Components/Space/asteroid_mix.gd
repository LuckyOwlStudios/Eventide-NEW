class_name AsteroidMix
extends RefCounted
## Which kinds of asteroid a system has and how common each is: the share of its asteroids that are Warm, that are
## Frozen and so on. It depends on nothing but the system's temperature, tags and jump count (see
## [method Asteroid.get_weight]), so every player works out the same mix.
##
## A system builds only a handful of asteroid shapes, and every asteroid is turned and sized from one of them (see
## [AsteroidShapes]). So the mix also says how the shapes are shared out between the kinds ([method allocate]): every
## kind in the mix gets at least one, and the rest go where the shares need them. [method get_model_weights] is the
## chance of each shape being the one an asteroid uses, which makes the share of asteroids of each kind exactly
## the kind's share, however few shapes there are.

## A kind with less than this share of the system is left out, and the others share its asteroids.
const MINIMUM_SHARE := 0.02

## The kinds in the mix, in the order of [member shares].
var asteroids: Array[Asteroid] = []
## How much of the system's asteroids each kind is, adding up to 1.
var shares := PackedFloat32Array()


## The mix of a system with [param temperature], [param tags] and jump count [param jump], from [param candidates]
## (every registered kind when empty). A plain default rock when no kind fits.
static func make(temperature: float, tags: Array[String], jump: int, candidates: Array[Asteroid] = []) -> AsteroidMix:
	var mix := AsteroidMix.new()
	var weights := PackedFloat32Array()
	for asteroid in candidates if not candidates.is_empty() else AsteroidRegistry.get_asteroids():
		if asteroid == null:
			continue
		var weight := asteroid.get_weight(temperature, tags, jump)
		if weight > 0.0:
			mix.asteroids.append(asteroid)
			weights.append(weight)
	if mix.asteroids.is_empty():
		mix.asteroids.append(Asteroid.new())
		mix.shares = PackedFloat32Array([1.0])
		return mix

	# Leave out the very rare kinds, then see what the others come to: a kind just above the line can fall below it.
	while mix.asteroids.size() > 1:
		var total := 0.0
		for weight in weights:
			total += weight
		var smallest := 0
		for index in weights.size():
			if weights[index] < weights[smallest]:
				smallest = index
		if weights[smallest] / total >= MINIMUM_SHARE:
			break
		mix.asteroids.remove_at(smallest)
		weights.remove_at(smallest)
	var sum := 0.0
	for weight in weights:
		sum += weight
	mix.shares.resize(weights.size())
	for index in weights.size():
		mix.shares[index] = weights[index] / sum
	return mix


## The mix of [param system].
static func for_system(system: StarSystem, candidates: Array[Asteroid] = []) -> AsteroidMix:
	return make(system.temperature, system.tags, system.jump_count, candidates)


## A mix of exactly [param kinds], in equal parts, whatever their temperatures, tags and jump counts say. For looking
## at kinds side by side, and for tests.
static func of(kinds: Array[Asteroid]) -> AsteroidMix:
	var mix := AsteroidMix.new()
	for kind in kinds:
		if kind != null:
			mix.asteroids.append(kind)
	if mix.asteroids.is_empty():
		mix.asteroids.append(Asteroid.new())
	mix.shares.resize(mix.asteroids.size())
	mix.shares.fill(1.0 / mix.asteroids.size())
	return mix


func get_count() -> int:
	return asteroids.size()


## The share of [param asteroid], 0 if it is not in the mix.
func get_share(asteroid: Asteroid) -> float:
	var index := asteroids.find(asteroid)
	return shares[index] if index >= 0 else 0.0


## One kind picked in proportion to the shares.
func pick(rng: SpaceRandom) -> Asteroid:
	return asteroids[maxi(rng.pick_weighted(shares), 0)]


## How many of [param model_count] shapes each kind gets: at least one each while there are enough shapes, and
## the rest to the kinds whose share is furthest from what they have. (With more kinds than shapes the biggest shares
## get one each and the others none.) The list is in the order of [member asteroids].
func get_model_counts(model_count: int) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(asteroids.size())
	var wanted := maxi(model_count, 1)
	# The kinds that get a shape, by share, biggest first.
	var order: Array[int] = []
	for index in asteroids.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return shares[a] > shares[b] or (shares[a] == shares[b] and a < b))
	var kept := order.slice(0, mini(wanted, order.size()))
	var kept_total := 0.0
	for index in kept:
		counts[index] = 1
		kept_total += shares[index]
	for _step in wanted - kept.size():
		var best: int = kept[0]
		var best_gap := -INF
		for index in kept:
			var gap: float = shares[index] / kept_total * wanted - counts[index]
			if gap > best_gap + 0.000001:
				best_gap = gap
				best = index
		counts[best] += 1
	return counts


## Which kind each of [param model_count] shapes is, as an index into [member asteroids]. Shapes of one kind are
## together.
func allocate(model_count: int) -> PackedInt32Array:
	var counts := get_model_counts(model_count)
	var kinds := PackedInt32Array()
	for index in counts.size():
		for _model in counts[index]:
			kinds.append(index)
	return kinds


## The chance that an asteroid uses each of [param model_count] shapes, adding up to 1: its kind's share divided
## by the number of shapes of that kind.
func get_model_weights(model_count: int) -> PackedFloat32Array:
	var counts := get_model_counts(model_count)
	var kept_total := 0.0
	for index in counts.size():
		if counts[index] > 0:
			kept_total += shares[index]
	var weights := PackedFloat32Array()
	for index in counts.size():
		for _model in counts[index]:
			weights.append(shares[index] / kept_total / counts[index])
	return weights
