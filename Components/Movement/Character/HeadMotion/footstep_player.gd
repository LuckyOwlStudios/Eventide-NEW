@icon("uid://brigdyunqa18")
class_name FootstepPlayer
extends Node
## Plays footstep sounds every time [HeadMotion] says a foot has landed.
##
## Each step is two sounds at once: the character's own ([member character_sound]) and
## the sound of what it is standing on (the [SurfaceMaterial] under its feet). So every
## character keeps its own footstep, and every surface sounds the same whoever walks on it.
##
## The surface is found with a ray straight down from the feet at the moment of each step.
## Ground without a [SurfaceMaterial] sounds like the default surface (see [SurfaceMaterial]).
##
## The sound is triggered by the same event that dips the head, so the two cannot drift
## apart. Each step is quieter or louder with how hard the foot landed and how fast the
## character is going.

## Emitted for every step that is played. Either stream may be null.
signal step_played(character_stream: AudioStream, surface_stream: AudioStream, surface: SurfaceMaterial)

## Found next to this node when left empty.
@export var head_motion: HeadMotion

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

var _players: Array[AudioStreamPlayer3D] = []
var _next_voice := 0


func _ready() -> void:
	if not is_instance_valid(head_motion):
		head_motion = _find_head_motion()
	if not is_instance_valid(head_motion):
		push_error("FootstepPlayer needs a HeadMotion next to it.")
		return
	if not is_instance_valid(sound_origin):
		sound_origin = get_parent() as Node3D
	if not is_instance_valid(sound_origin):
		push_error("FootstepPlayer needs a Node3D to play sounds from.")
		return
	for index in voices:
		var player := AudioStreamPlayer3D.new()
		player.name = "FootstepVoice%d" % index
		player.bus = bus
		player.max_distance = max_distance
		player.unit_size = unit_size
		sound_origin.add_child.call_deferred(player)
		_players.append(player)
	head_motion.footstep.connect(_on_footstep)


## The surface the character is standing on: its [SurfaceMaterial], or the default surface
## when the ground has none.
func get_surface_underfoot() -> SurfaceMaterial:
	var body := head_motion.controller.get_body() if is_instance_valid(head_motion) else null
	if body == null:
		return SurfaceMaterial.get_default()
	var up := body.global_basis.y.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		body.global_position + up * 0.1,
		body.global_position - up * ground_check_distance,
		body.collision_mask,
		[body.get_rid()],
	)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
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


func _on_footstep(_foot_index: int, strength: float, _profile: HeadBobProfile) -> void:
	play_step(strength)


func _find_head_motion() -> HeadMotion:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is HeadMotion:
			return child as HeadMotion
	return null
