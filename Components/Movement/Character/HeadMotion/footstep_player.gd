@icon("uid://brigdyunqa18")
class_name FootstepPlayer
extends Node
## Plays footsteps from how a character moves, and nothing else.
##
## Walking on the ground, the character takes a step every [member walk_step_distance] meters (more for a
## sprint, less for a stroll or a crouch). The first step is taken the moment it sets off after standing
## still, and landing from a fall is a step too, harder the harder it landed. Steps are quieter the slower
## the character goes, and in a crouch.
##
## Each step is two sounds at once: the character's own ([member character_sound]) and the sound of what
## it is standing on (the [SurfaceMaterial] under its feet). So every character keeps its own footstep, and
## every surface sounds the same whoever walks on it. The surface is found with a ray straight down from
## the feet at the moment of each step. Ground without a [SurfaceMaterial] sounds like the default surface
## (see [SurfaceMaterial]).
##
## It reads the body it is a child of (a [WalkingCharacter3D] says whether it is crouching) and, when there
## is one next to it, the [CharacterController] for whether the feet are on the ground. It does not depend
## on a head bob, so a character with none still has footsteps.

## Emitted for every step that is played. Either stream may be null.
signal step_played(character_stream: AudioStream, surface_stream: AudioStream, surface: SurfaceMaterial)
## A foot came down. [param foot_index] alternates between 0 and 1 and [param strength] is how hard.
signal stepped(foot_index: int, strength: float)

## Found next to this node when left empty. Optional.
@export var controller: CharacterController

@export_group("Steps")
## Meters walked between steps at a walk.
@export_range(0.2, 10.0, 0.05, "suffix:m") var walk_step_distance := 1.8
## Meters between steps at a sprint, the stroll and when crouched.
@export_range(0.2, 10.0, 0.05, "suffix:m") var sprint_step_distance := 2.4
@export_range(0.2, 10.0, 0.05, "suffix:m") var stroll_step_distance := 1.6
@export_range(0.2, 10.0, 0.05, "suffix:m") var crouch_step_distance := 1.3
## The speed that counts as walking at full pace, when the body is not a [WalkingCharacter3D], which knows. Moving
## faster than this by [member sprint_ratio] is a sprint, slower than [member stroll_ratio] a stroll.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var walking_speed := 5.0
@export_range(1.0, 3.0, 0.01) var sprint_ratio := 1.25
@export_range(0.1, 1.0, 0.01) var stroll_ratio := 0.65
## Slower than this, the feet do not move.
@export_range(0.0, 5.0, 0.05, "suffix:m/s") var minimum_speed := 0.5
## How loud a crouched step is, and a stroll's, next to a walk's.
@export_range(0.0, 2.0, 0.05) var crouch_loudness := 0.6
@export_range(0.0, 2.0, 0.05) var stroll_loudness := 0.8

@export_group("Sounds")
## This character's own footstep, played with every step whatever it walks on. Use an
## AudioStreamRandomizer for variety. Leave empty for none.
@export var character_sound: AudioStream
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var base_volume_db := 0.0
## Each step is a little lower or higher than the last, by up to this share.
@export_range(0.0, 0.5, 0.01) var pitch_variation := 0.06
## Each step is a little louder or quieter than the last, by up to this much.
@export_range(0.0, 12.0, 0.1, "suffix:dB") var volume_variation_db := 1.5

@export_group("Ground Check")
## How far below the feet to look for the ground.
@export_range(0.1, 3.0, 0.05, "suffix:m") var ground_check_distance := 0.6

@export_group("Playback")
## Where the sound comes from. The body's feet when left empty.
@export var sound_origin: Node3D
## Sounds that may play at once. Every step uses two.
@export_range(2, 16) var voices := 6
@export var bus: StringName = &"Master"
@export_range(1.0, 200.0, 1.0, "suffix:m") var max_distance := 30.0
@export_range(0.1, 20.0, 0.1, "suffix:m") var unit_size := 4.0

## Time in the air that makes a touchdown a step.
const LANDING_STEP_MINIMUM_AIR_TIME := 0.1
## Standing still for this long makes the next step come at once.
const IDLE_BEFORE_FIRST_STEP := 0.3
## The fall speed of the hardest landing.
const FULL_IMPACT_SPEED := 14.0

var _body: CharacterBody3D
var _players: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _distance := 0.0
var _foot := 0
var _idle_time := 0.0
var _air_time := 0.0
var _was_grounded := true
var _previous_vertical_speed := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("FootstepPlayer must be a child of a CharacterBody3D.")
		set_physics_process(false)
		return
	if not is_instance_valid(controller):
		controller = _find_controller()
	if not is_instance_valid(sound_origin):
		sound_origin = _body
	_was_grounded = _is_grounded()
	for index in voices:
		var player := AudioStreamPlayer3D.new()
		player.name = "FootstepVoice%d" % index
		player.bus = bus
		player.max_distance = max_distance
		player.unit_size = unit_size
		sound_origin.add_child.call_deferred(player)
		_players.append(player)


func _physics_process(delta: float) -> void:
	var grounded := _is_grounded()
	var up := _body.global_basis.y.normalized()
	var vertical_speed := _body.velocity.dot(up)
	var planar := _body.velocity - up * vertical_speed
	var speed := planar.length()
	var walking := _can_walk()

	# Touching down after time in the air is a step, and the walk carries on from it.
	if grounded and not _was_grounded and walking and _air_time >= LANDING_STEP_MINIMUM_AIR_TIME:
		var hardness := clampf(-_previous_vertical_speed / FULL_IMPACT_SPEED, 0.0, 1.0)
		_distance = 0.0
		_idle_time = 0.0
		_step(1.0 + hardness * 0.8)
	_air_time = 0.0 if grounded else _air_time + delta

	var gait := _get_gait(speed)
	var minimum := minimum_speed * (0.8 if is_crouching() else 1.0)
	if grounded and walking and speed >= minimum:
		# Setting off after standing still: the first step is heard at once.
		if _idle_time > IDLE_BEFORE_FIRST_STEP:
			_distance = 0.0
			# Judged by the speed being set off at, not the first slow ticks.
			var aimed := maxf(speed, controller.get_target_speed() if is_instance_valid(controller) else 0.0)
			_step(_get_strength(_get_gait(aimed), aimed))
		_idle_time = 0.0
		_distance += speed * delta
		var distance := _get_step_distance(gait)
		while _distance >= distance:
			_distance -= distance
			_step(_get_strength(gait, speed))
	else:
		_idle_time += delta
	_was_grounded = grounded
	_previous_vertical_speed = vertical_speed


## The surface the character is standing on: its [SurfaceMaterial], or the default surface
## when the ground has none.
func get_surface_underfoot() -> SurfaceMaterial:
	if _body == null:
		return SurfaceMaterial.get_default()
	var up := _body.global_basis.y.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		_body.global_position + up * 0.1,
		_body.global_position - up * ground_check_distance,
		_body.collision_mask,
		[_body.get_rid()],
	)
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return SurfaceMaterial.get_default()
	return SurfaceMaterial.from_collider(hit["collider"])


## Plays one step now: the character's sound and the sound of the ground underfoot.
func play_step(strength := 1.0) -> void:
	var surface := get_surface_underfoot()
	var surface_sound := surface.step_sound if surface != null else null
	if character_sound == null and surface_sound == null:
		return
	var loudness := base_volume_db + linear_to_db(clampf(strength, 0.05, 2.0))
	if character_sound != null:
		_play(character_sound, loudness, 1.0)
	if surface_sound != null:
		_play(surface_sound, loudness + surface.step_volume_db, surface.step_pitch)
	step_played.emit(character_sound, surface_sound, surface)


func is_crouching() -> bool:
	if is_instance_valid(controller):
		return controller.is_crouching()
	return _body is WalkingCharacter3D and (_body as WalkingCharacter3D).is_crouching()


func _step(strength: float) -> void:
	var foot := _foot
	_foot = 1 - _foot
	stepped.emit(foot, strength)
	play_step(strength)


func _is_grounded() -> bool:
	if is_instance_valid(controller):
		return controller.is_grounded()
	return _body != null and _body.is_on_floor()


## Whether the feet can be walking at all: not flying, not held still by a lock.
func _can_walk() -> bool:
	if is_instance_valid(controller):
		return not controller.is_flying() and controller.is_movement_permitted()
	return true


func _get_walking_speed() -> float:
	if _body is WalkingCharacter3D:
		return (_body as WalkingCharacter3D).movement_speed.value
	return walking_speed


## 0 walk, 1 sprint, 2 stroll, 3 crouch.
func _get_gait(speed: float) -> int:
	if is_crouching():
		return 3
	var ratio := speed / maxf(_get_walking_speed(), 0.01)
	if ratio >= sprint_ratio:
		return 1
	if ratio <= stroll_ratio:
		return 2
	return 0


func _get_step_distance(gait: int) -> float:
	match gait:
		1:
			return sprint_step_distance
		2:
			return stroll_step_distance
		3:
			return crouch_step_distance
	return walk_step_distance


## How hard a foot lands: harder with speed, and scaled by how loud the gait is. A sneak or a slow stroll is
## quiet, and both together are close to silent.
func _get_strength(gait: int, speed: float) -> float:
	var intensity := clampf(speed / maxf(_get_walking_speed(), 0.01), 0.0, 1.5)
	var loudness := 1.0
	match gait:
		2:
			loudness = stroll_loudness
		3:
			loudness = crouch_loudness
	return loudness * pow(intensity, 1.5)


func _play(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if _players.is_empty():
		return
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	player.stream = stream
	player.volume_db = volume_db + randf_range(-volume_variation_db, volume_variation_db)
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_variation, pitch_variation))
	player.play()


func _find_controller() -> CharacterController:
	if _body == null:
		return null
	for child in _body.get_children():
		if child is CharacterController:
			return child as CharacterController
	return null
