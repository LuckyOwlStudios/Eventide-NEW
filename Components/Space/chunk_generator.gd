class_name ChunkGenerator
extends RefCounted
## Works out what is in one chunk of a system: where each asteroid is, how big, which model and
## how it is turned. It makes no nodes. A chunk's contents depend on nothing but the system, the
## chunk's coordinates and the model count, so the same chunk comes out the same wherever and
## whenever it is made: the player's machine and everybody else's agree without sending a thing,
## and a chunk that is unloaded and loaded again is unchanged.
##
## Space is cut into cubes ([member chunk_size] a side) and a chunk is named by its cube's
## [Vector3i] coordinates. An asteroid always lies completely inside its own chunk, so two chunks
## never put asteroids into each other and each can be built or dropped alone.
##
## How thick the asteroids are changes from place to place, in belts and voids as big as
## [member StarSystem.cluster_size], and with the system's difficulty.

## The chunk size that [member StarSystem.asteroid_density] is counted for.
const REFERENCE_CHUNK_SIZE := 500.0
## A chunk never holds more than this, however thick the belt.
const MAX_ASTEROIDS := 40
## How often a spot that is taken is tried again with another before giving up on that asteroid.
const PLACEMENT_TRIES := 6
## The space kept between two asteroids.
const GAP := 2.0

## One asteroid in a chunk.
class Spec:
	extends RefCounted
	## From the corner of the chunk.
	var position := Vector3.ZERO
	var radius := 1.0
	## Which of the [member AsteroidShapes.models] it is.
	var model := 0
	var basis := Basis.IDENTITY

var system: StarSystem
var chunk_size: float
var model_count: int

var _cluster_noise: FastNoiseLite
## The chance of each model being the one an asteroid uses, which is how much of the system each kind of
## asteroid is (see [method AsteroidMix.get_model_weights]).
var _model_weights := PackedFloat32Array()


func _init(for_system: StarSystem, size: float = REFERENCE_CHUNK_SIZE, models: int = AsteroidShapes.DEFAULT_MODEL_COUNT) -> void:
	system = for_system
	chunk_size = size
	model_count = maxi(models, 1)
	var mix := system.asteroid_mix if system.asteroid_mix != null else AsteroidMix.make(0.0, [], 0)
	_model_weights = mix.get_model_weights(model_count)
	_cluster_noise = FastNoiseLite.new()
	_cluster_noise.seed = SpaceRandom.combine(system.system_seed, 0x636C7573) & 0x7FFFFFFF
	_cluster_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cluster_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cluster_noise.fractal_octaves = 2
	_cluster_noise.frequency = 1.0 / maxf(system.cluster_size, 1.0)


## Where the corner of chunk [param coord] is, in the world.
func get_origin(coord: Vector3i) -> Vector3:
	return Vector3(coord) * chunk_size


## The chunk that contains [param point].
func get_coord(point: Vector3) -> Vector3i:
	return Vector3i((point / chunk_size).floor())


## How thick the field is at the middle of chunk [param coord], as asteroids per chunk. Many chunks
## hold close to none (the voids) and some several times the system's average (the belts).
func get_expected_count(coord: Vector3i) -> float:
	var center := (Vector3(coord) + Vector3.ONE * 0.5) * chunk_size
	var noise := _cluster_noise.get_noise_3d(center.x, center.y, center.z)
	var richness := smoothstep(-0.3, 0.45, noise)
	var volume := pow(chunk_size / REFERENCE_CHUNK_SIZE, 3.0)
	return system.asteroid_density * volume * lerpf(0.05, 2.4, richness)


## Everything in chunk [param coord].
func generate(coord: Vector3i) -> Array[Spec]:
	var specs: Array[Spec] = []
	var rng := SpaceRandom.new(SpaceRandom.chunk_seed(system.system_seed, coord))
	var expected := get_expected_count(coord)
	var count := int(expected)
	if rng.next_float() < expected - float(count):
		count += 1
	count = mini(count, MAX_ASTEROIDS)
	var origin := get_origin(coord)

	for _asteroid in count:
		var radius := lerpf(system.smallest_radius, system.largest_radius, pow(rng.next_float(), 3.0))
		if radius * 2.0 + GAP >= chunk_size:
			continue
		var spec := Spec.new()
		spec.radius = radius
		spec.model = maxi(rng.pick_weighted(_model_weights), 0)
		spec.basis = rng.rotation()
		var placed := false
		for _try in PLACEMENT_TRIES:
			var span := chunk_size - radius * 2.0
			spec.position = Vector3(radius, radius, radius) + Vector3(rng.next_float(), rng.next_float(), rng.next_float()) * span
			if _is_clear(spec, specs, origin):
				placed = true
				break
		if placed:
			specs.append(spec)
	return specs


## Whether [param candidate] is out of the way of the arrival area and of the asteroids [param placed] already.
func _is_clear(candidate: Spec, placed: Array[Spec], origin: Vector3) -> bool:
	var world_position := origin + candidate.position
	if world_position.distance_to(system.arrival_position) < system.arrival_clear_radius + candidate.radius:
		return false
	for other in placed:
		if candidate.position.distance_to(other.position) < candidate.radius + other.radius + GAP:
			return false
	return true
