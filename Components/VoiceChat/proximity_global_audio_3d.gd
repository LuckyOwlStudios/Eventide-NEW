class_name ProximityGlobalAudio3D
extends AudioStreamPlayer3D

## Base player for audio that crossfades between positional and global outputs.
## Subclasses can provide any stream source, including generated network voice.

signal playback_started
signal playback_stopped

@export_category("Playback")

## Starts this audio component automatically when it enters the scene tree.
@export var start_enabled := true

## Restarts ordinary non-looping streams when they finish.
@export var loop_enabled := true

@export_category("Proximity and Global Mix")

## Enables the non-positional global output. Disable this to use only positional audio.
@export var global_channel_enabled := true

## Distance in world units where positional audio remains full and global audio is silent.
@export_range(0.0, 1000.0, 0.5, "or_greater") var proximity_full_distance := 8.0

## Distance where global audio is full and positional audio is silent.
## This value must be greater than proximity_full_distance.
@export_range(0.5, 2000.0, 0.5, "or_greater") var global_full_distance := 25.0

## Volume adjustment for the positional side of the crossfade.
@export_range(-24.0, 12.0, 0.5) var proximity_volume_offset_db := 0.0

## Volume adjustment for the non-positional side of the crossfade.
@export_range(-24.0, 12.0, 0.5) var global_volume_offset_db := -3.0

## Audio bus used by the non-positional output. Falls back to Master if missing.
@export var global_audio_bus: StringName = &"Master"

@export_category("Debug")

## Prints playback and crossfade-region changes to Godot's Output panel.
@export var debug_enabled := false

var _global_player: AudioStreamPlayer
var _overall_volume_db := 0.0
var _audio_active := false
var _last_region := -1


func _ready() -> void:
	_configure_source_stream()
	_overall_volume_db = volume_db
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	max_distance = 0.0
	attenuation_filter_cutoff_hz = 20500.0
	finished.connect(_on_positional_finished)

	_global_player = AudioStreamPlayer.new()
	_global_player.name = "GlobalAudioOutput"
	_global_player.stream = stream
	_global_player.bus = _validated_audio_bus(global_audio_bus)
	add_child(_global_player)
	_after_audio_outputs_created()

	if start_enabled:
		_start_audio_when_ready()
	else:
		_update_channel_blend()


func _process(delta: float) -> void:
	_update_channel_blend()
	_keep_outputs_synchronized()
	_process_audio(delta)


func _exit_tree() -> void:
	_audio_exit_tree()


func start_audio() -> void:
	if stream == null:
		push_warning("ProximityGlobalAudio3D needs an audio resource in its Stream property.")
		return

	_global_player.stream = stream
	play()
	_global_player.play()
	_audio_active = true
	_on_audio_playback_started()
	_update_channel_blend()
	_debug("Audio playback started.")
	playback_started.emit()


func stop_audio() -> void:
	stop()
	if _global_player != null:
		_global_player.stop()
	_audio_active = false
	_on_audio_playback_stopped()
	_update_channel_blend()
	_debug("Audio playback stopped.")
	playback_stopped.emit()


func toggle_audio() -> void:
	if _audio_active:
		stop_audio()
	else:
		start_audio()


func is_audio_active() -> bool:
	return _audio_active


func set_audio_volume_db(value: float) -> void:
	_overall_volume_db = value
	_update_channel_blend()


func _configure_source_stream() -> void:
	pass


func _after_audio_outputs_created() -> void:
	pass


func _start_audio_when_ready() -> void:
	start_audio()


func _process_audio(_delta: float) -> void:
	pass


func _audio_exit_tree() -> void:
	pass


func _on_audio_playback_started() -> void:
	pass


func _on_audio_playback_stopped() -> void:
	pass


func _can_mix_audio() -> bool:
	return _audio_active


func _update_channel_blend() -> void:
	if not _can_mix_audio():
		_set_channel_gains(0.0, 0.0)
		return
	if not global_channel_enabled:
		_set_channel_gains(1.0, 0.0)
		_report_region(0)
		return

	var listener := get_viewport().get_camera_3d()
	if listener == null:
		_set_channel_gains(1.0, 0.0)
		return

	var fade_start := maxf(proximity_full_distance, 0.0)
	var fade_end := maxf(global_full_distance, fade_start + 0.001)
	var distance_to_listener := global_position.distance_to(listener.global_position)
	var blend := clampf(
		(distance_to_listener - fade_start) / (fade_end - fade_start),
		0.0,
		1.0
	)
	blend = smoothstep(0.0, 1.0, blend)
	_set_channel_gains(1.0 - blend, blend)

	if distance_to_listener <= fade_start:
		_report_region(0)
	elif distance_to_listener >= fade_end:
		_report_region(2)
	else:
		_report_region(1)


func _set_channel_gains(proximity_gain: float, global_gain: float) -> void:
	volume_db = (
		_overall_volume_db
		+ proximity_volume_offset_db
		+ linear_to_db(maxf(proximity_gain, 0.0001))
	)
	if _global_player != null:
		_global_player.volume_db = (
			_overall_volume_db
			+ global_volume_offset_db
			+ linear_to_db(maxf(global_gain, 0.0001))
		)


func _keep_outputs_synchronized() -> void:
	if stream is AudioStreamGenerator:
		return
	if not _audio_active or not playing or not _global_player.playing:
		return
	var positional_time := get_playback_position()
	var global_time := _global_player.get_playback_position()
	if absf(positional_time - global_time) > 0.05:
		_global_player.seek(positional_time)


func _on_positional_finished() -> void:
	if loop_enabled and _audio_active:
		play()
		_global_player.stop()
		_global_player.play()
		_on_audio_playback_started()
	else:
		_audio_active = false
		_on_audio_playback_stopped()
		_update_channel_blend()
		playback_stopped.emit()


func _report_region(region: int) -> void:
	if region == _last_region:
		return
	_last_region = region
	var names := ["proximity", "crossfade", "global"]
	_debug("Entered %s region." % names[region])


func _validated_audio_bus(requested_bus: StringName) -> StringName:
	if AudioServer.get_bus_index(requested_bus) >= 0:
		return requested_bus
	push_warning("Global audio bus '%s' does not exist; using Master." % requested_bus)
	return &"Master"


func _debug(message: String) -> void:
	if debug_enabled:
		print("[ProximityGlobalAudio3D:%s] %s" % [name, message])
